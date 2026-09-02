import Foundation

/// GET https://api.anthropic.com/api/oauth/usage — the same endpoint Claude Code's `/usage` uses.
enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let userAgent = "NotchUsage/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (macOS)"

    enum Failure: LocalizedError {
        case unauthorized
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Claude rejected the token (401)."
            case .rateLimited(let r):
                if let r { return "Rate limited by Claude. Retrying in \(Int(r / 60)) min." }
                return "Rate limited by Claude."
            case .http(let c, let b): return "Usage request failed (HTTP \(c)): \(b)"
            case .badResponse: return "Unexpected response from the usage endpoint."
            }
        }
    }

    static func fetch(token: String) async throws -> Usage {
        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200..<300: return try Usage(json: data)
        case 401, 403: throw Failure.unauthorized
        case 429:
            let ra = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw Failure.rateLimited(retryAfter: ra)
        case let c: throw Failure.http(c, String(decoding: data.prefix(200), as: UTF8.self))
        }
    }
}
