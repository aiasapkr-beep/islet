import Foundation
import Security

/// Claude Code stores its OAuth credentials as a JSON blob:
/// {"claudeAiOauth": {"accessToken","refreshToken","expiresAt"(ms),"refreshTokenExpiresAt","scopes","subscriptionType","rateLimitTier"}}
/// On macOS it lives in the login Keychain (service "Claude Code-credentials");
/// on other platforms in ~/.claude/.credentials.json. We keep the raw dictionary so
/// a round-trip write never drops keys we don't know about.
struct Credentials {
    private(set) var raw: [String: Any]

    private var oauth: [String: Any] { raw["claudeAiOauth"] as? [String: Any] ?? [:] }

    var accessToken: String { oauth["accessToken"] as? String ?? "" }
    var refreshToken: String? { oauth["refreshToken"] as? String }
    var subscriptionType: String? { oauth["subscriptionType"] as? String }
    var rateLimitTier: String? { oauth["rateLimitTier"] as? String }
    var expiresAt: Date? { msDate(oauth["expiresAt"]) }
    var refreshTokenExpiresAt: Date? { msDate(oauth["refreshTokenExpiresAt"]) }

    /// Treat the token as expired one minute early to avoid racing the server clock.
    var isExpired: Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSinceNow < 60
    }
    var canRefresh: Bool {
        guard let r = refreshToken, !r.isEmpty else { return false }
        if let re = refreshTokenExpiresAt, re.timeIntervalSinceNow < 0 { return false }
        return true
    }

    init(data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = obj["claudeAiOauth"] as? [String: Any],
              let t = o["accessToken"] as? String, !t.isEmpty else {
            throw CredentialError.malformed
        }
        raw = obj
    }

    func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
    }

    func updated(accessToken: String, refreshToken: String?, expiresIn: TimeInterval) -> Credentials {
        var copy = self
        var o = oauth
        o["accessToken"] = accessToken
        if let r = refreshToken, !r.isEmpty { o["refreshToken"] = r }
        o["expiresAt"] = Int((Date().timeIntervalSince1970 + expiresIn) * 1000)
        copy.raw["claudeAiOauth"] = o
        return copy
    }

    private func msDate(_ v: Any?) -> Date? {
        guard let n = (v as? NSNumber)?.doubleValue, n > 0 else { return nil }
        return Date(timeIntervalSince1970: n / 1000)
    }
}

enum CredentialSource: CustomStringConvertible {
    case keychain              // direct SecItem access (may prompt for permission)
    case securityCLI(String)   // /usr/bin/security (account name), no per-app prompt
    case file(URL)

    var description: String {
        switch self {
        case .keychain: return "Keychain"
        case .securityCLI: return "Keychain"
        case .file(let u): return u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }
}

enum CredentialError: LocalizedError {
    case notFound
    case malformed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Claude Code credentials not found. Run `claude` and sign in first."
        case .malformed: return "Credentials found but not in the expected format."
        case .keychain(let s):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Keychain error: \(msg)"
        }
    }
}

enum CredentialStore {
    static let service = "Claude Code-credentials"

    static var fileURL: URL {
        let env = ProcessInfo.processInfo.environment
        let dir = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        return dir.appendingPathComponent(".credentials.json")
    }

    /// Async entry points run the blocking Keychain/subprocess work on a background queue,
    /// so the main actor is never blocked (blocking it wedges Swift's concurrency executor).
    static func loadAsync() async throws -> (Credentials, CredentialSource) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try load() })
            }
        }
    }

    static func saveAsync(_ creds: Credentials, to source: CredentialSource) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try save(creds, to: source) })
            }
        }
    }

    static func load() throws -> (Credentials, CredentialSource) {
        // 1) /usr/bin/security: an Apple-signed tool already trusted for this item on most
        //    machines, so it reads the token without raising a per-app Keychain prompt.
        if let (data, account) = readViaSecurityCLI() {
        }
        // 2) Direct SecItem access. Correct everywhere, but the first read from a new app
        //    identity raises the "Islet wants to use ... Keychain" confirmation dialog.
        var keychainError: Error?
        do {
            if let data = try readKeychain() {
                return (try Credentials(data: data), .keychain)
            }
        } catch { keychainError = error }
        // 3) The file Claude Code uses on non-macOS (or a custom CLAUDE_CONFIG_DIR).
        if let data = try? Data(contentsOf: fileURL) {
            return (try Credentials(data: data), .file(fileURL))
        }
        throw keychainError ?? CredentialError.notFound
    }

    static func save(_ creds: Credentials, to source: CredentialSource) throws {
        let data = try creds.data()
        switch source {
        case .keychain: try writeKeychain(data)
        case .securityCLI(let account): try writeViaSecurityCLI(data, account: account)
        case .file(let url): try data.write(to: url, options: [.atomic])
        }
    }

    // MARK: /usr/bin/security

    /// Runs `security` with stdout captured through a temp file. Using a file (not a Pipe)
    /// means we never have to drain a pipe while blocking a thread, so this is safe to call
    /// synchronously from the main actor without risking a pipe-buffer deadlock.
    private static func runSecurity(_ args: [String]) -> (Int32, Data) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = args
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("islet-sec-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else { return (-1, Data()) }
        defer { try? FileManager.default.removeItem(at: tmp) }
        proc.standardOutput = handle
        proc.standardError = FileHandle.nullDevice
        // Wait via terminationHandler + semaphore. waitUntilExit() deadlocks when called on
        // the main thread, and Process's handler fires on its own queue, so this is safe there.
        let done = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in done.signal() }
        do { try proc.run() } catch { try? handle.close(); return (-1, Data()) }
        done.wait()
        try? handle.close()
        let data = (try? Data(contentsOf: tmp)) ?? Data()
        return (proc.terminationStatus, data)
    }

    /// Reads the raw JSON blob and the account name it is stored under, if the tool succeeds.
    private static func readViaSecurityCLI() -> (Data, String)? {
        let (code, data) = runSecurity(["find-generic-password", "-s", service, "-w"])
        guard code == 0 else { return nil }
        var blob = data
        if blob.last == 0x0A { blob.removeLast() }
        guard !blob.isEmpty else { return nil }
        // The account is needed to update the same item in place later.
        let (mcode, meta) = runSecurity(["find-generic-password", "-s", service, "-g"])
        var account = NSUserName()
        if mcode == 0, let text = String(data: meta, encoding: .utf8),
           let range = text.range(of: "\"acct\"<blob>=\"") {
            let rest = text[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") { account = String(rest[..<end]) }
        }
        return (blob, account)
    }

    private static func writeViaSecurityCLI(_ data: Data, account: String) throws {
        // -U updates the existing item in place, preserving its access control.
        guard let json = String(data: data, encoding: .utf8) else { throw CredentialError.malformed }
        let (code, _) = runSecurity(["add-generic-password", "-U", "-s", service, "-a", account, "-w", json])
        guard code == 0 else { throw CredentialError.keychain(errSecAuthFailed) }
    }

    // MARK: Keychain

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    private static func readKeychain() throws -> Data? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw CredentialError.keychain(status)
        }
    }

    private static func writeKeychain(_ data: Data) throws {
        let status = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }
}
