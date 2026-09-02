import Foundation

/// Refreshes a Claude Code OAuth access token with the public Claude Code client id.
/// This is the same flow Claude Code itself runs when its token expires.
enum OAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenEndpoints = [
        URL(string: "https://platform.claude.com/v1/oauth/token")!,
        URL(string: "https://console.anthropic.com/v1/oauth/token")!,
    ]

    enum Failure: LocalizedError {
        case noRefreshToken
        case rejected(Int, String)

        var errorDescription: String? {
            switch self {
            case .noRefreshToken: return "Token expired and no refresh token is available. Run `claude` to sign in again."
            case .rejected(let code, let body): return "Token refresh failed (HTTP \(code)): \(body)"
            }
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    static func refresh(_ creds: Credentials) async throws -> Credentials {
        guard creds.canRefresh, let refreshToken = creds.refreshToken else { throw Failure.noRefreshToken }
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        var lastError: Error = Failure.noRefreshToken
        for url in tokenEndpoints {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(UsageAPI.userAgent, forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            do {
                let (data, resp) = try await UsageAPI.session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    lastError = Failure.rejected(code, String(decoding: data.prefix(200), as: UTF8.self))
                    // 4xx means the refresh token itself is bad; no point trying the other host.
                    if (400..<500).contains(code) { throw lastError }
                    continue
                }
                let tok = try JSONDecoder().decode(TokenResponse.self, from: data)
                return creds.updated(accessToken: tok.access_token,
                                     refreshToken: tok.refresh_token,
                                     expiresIn: tok.expires_in ?? 8 * 3600)
            } catch let e as Failure { throw e }
            catch { lastError = error }
        }
        throw lastError
    }
}
