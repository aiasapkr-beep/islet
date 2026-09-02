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
    case keychain
    case file(URL)

    var description: String {
        switch self {
        case .keychain: return "Keychain"
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

    static func load() throws -> (Credentials, CredentialSource) {
        var keychainError: Error?
        do {
            if let data = try readKeychain() {
                return (try Credentials(data: data), .keychain)
            }
        } catch { keychainError = error }

        if let data = try? Data(contentsOf: fileURL) {
            return (try Credentials(data: data), .file(fileURL))
        }
        throw keychainError ?? CredentialError.notFound
    }

    static func save(_ creds: Credentials, to source: CredentialSource) throws {
        let data = try creds.data()
        switch source {
        case .keychain: try writeKeychain(data)
        case .file(let url): try data.write(to: url, options: [.atomic])
        }
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
