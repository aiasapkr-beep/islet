import Foundation
import Combine
import ServiceManagement

/// Single source of truth for the UI: polls the usage endpoint, refreshes the
/// token when needed, and exposes user settings.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var usage: Usage?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var plan: String?
    @Published private(set) var sourceName: String?

    // Settings (persisted in UserDefaults)
    @Published var showNotch: Bool { didSet { defaults.set(showNotch, forKey: "showNotch") } }
    @Published var autoRefreshToken: Bool { didSet { defaults.set(autoRefreshToken, forKey: "autoRefreshToken") } }
    @Published var showMenuBarText: Bool { didSet { defaults.set(showMenuBarText, forKey: "showMenuBarText") } }
    @Published var launchAtLogin: Bool {
        didSet { if launchAtLogin != oldValue { applyLaunchAtLogin() } }
    }

    var pollInterval: TimeInterval = 60
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var backoffUntil: Date?
    private var inFlight = false

    private init() {
        defaults.register(defaults: ["showNotch": true, "autoRefreshToken": true, "showMenuBarText": true])
        showNotch = defaults.bool(forKey: "showNotch")
        autoRefreshToken = defaults.bool(forKey: "autoRefreshToken")
        showMenuBarText = defaults.bool(forKey: "showMenuBarText")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// NOTCHUSAGE_MOCK=1 shows sample data without touching the Keychain or network (for screenshots/dev).
    static let mock = ProcessInfo.processInfo.environment["NOTCHUSAGE_MOCK"] == "1"

    func start() {
        if Self.mock {
            usage = Usage(fiveHour: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 13 * 60)),
                          sevenDay: UsageWindow(utilization: 71, resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600)),
                          sevenDayOpus: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600)))
            plan = "max"; sourceName = "mock"; lastUpdated = Date()
            ActivityMonitor.shared.activeWindow = 3600
            ActivityMonitor.shared.touch()
            return
        }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(force: Bool = false) {
        Task { await refreshNow(force: force) }
    }

    /// Short text for the menu bar item, e.g. "42% · 18%".
    var menuBarTitle: String {
        guard let u = usage else { return errorMessage == nil ? "…" : "!" }
        let a = u.fiveHour?.percentText ?? "–"
        let b = u.sevenDay?.percentText ?? "–"
        return "\(a) · \(b)"
    }

    var planText: String {
        guard let p = plan, !p.isEmpty else { return "Claude" }
        return "Claude " + p.prefix(1).uppercased() + p.dropFirst()
    }

    func refreshNow(force: Bool = false) async {
        if inFlight { return }
        if !force, let b = backoffUntil, b > Date() { return }
        inFlight = true
        isLoading = true
        defer { inFlight = false; isLoading = false }

        do {
            var (creds, source) = try CredentialStore.load()
            plan = creds.subscriptionType
            sourceName = source.description
            var refreshed = false
            Log.info("credentials from \(source), plan=\(creds.subscriptionType ?? "?"), expired=\(creds.isExpired), canRefresh=\(creds.canRefresh)")

            if creds.isExpired {
                creds = try await refreshCredentials(creds, source)
                refreshed = true
            }
            do {
                usage = try await UsageAPI.fetch(token: creds.accessToken)
            } catch UsageAPI.Failure.unauthorized where !refreshed {
                creds = try await refreshCredentials(creds, source)
                usage = try await UsageAPI.fetch(token: creds.accessToken)
            } catch UsageAPI.Failure.rateLimited where !refreshed && creds.canRefresh && autoRefreshToken {
                // The endpoint answers 429 (not 401) to stale tokens; one refresh usually clears it.
                creds = try await refreshCredentials(creds, source)
                usage = try await UsageAPI.fetch(token: creds.accessToken)
            }
            lastUpdated = Date()
            backoffUntil = nil
            errorMessage = nil
            Log.info("usage ok: 5h=\(usage?.fiveHour?.percentText ?? "-") 7d=\(usage?.sevenDay?.percentText ?? "-")")
        } catch UsageAPI.Failure.rateLimited(let retryAfter) {
            let wait = min(max(retryAfter ?? 300, 60), 15 * 60)
            backoffUntil = Date().addingTimeInterval(wait)
            errorMessage = UsageAPI.Failure.rateLimited(retryAfter: wait).errorDescription
            Log.error("rate limited, retry-after=\(retryAfter ?? -1), waiting \(wait)s")
        } catch {
            errorMessage = error.localizedDescription
            Log.error(error.localizedDescription)
        }
    }

    private func refreshCredentials(_ creds: Credentials, _ source: CredentialSource) async throws -> Credentials {
        guard autoRefreshToken else { throw StoreError.tokenExpired }
        Log.info("refreshing token…")
        let fresh = try await OAuth.refresh(creds)
        try CredentialStore.save(fresh, to: source)
        Log.info("token refreshed and saved to \(source)")
        return fresh
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Launch at login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    enum StoreError: LocalizedError {
        case tokenExpired
        var errorDescription: String? {
            "Claude token expired. Run `claude` in Terminal, or enable “Auto-refresh token” in the menu."
        }
    }
}
