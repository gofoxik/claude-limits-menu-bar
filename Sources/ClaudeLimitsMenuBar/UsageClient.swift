import Foundation

enum UsageError: Error, CustomStringConvertible {
    case http(Int, String)
    case rateLimited(retryAfter: Double)
    case decode(String)

    var description: String {
        switch self {
        case .http(let code, _): return "Usage request failed (HTTP \(code))"
        case .rateLimited: return "Rate limited — backing off"
        case .decode(let m): return "Couldn't parse usage: \(m)"
        }
    }
}

/// Fetches usage from the same endpoint the CLI's `/usage` command uses.
enum UsageClient {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"

    static func fetch() async throws -> UsageResponse {
        // First attempt with the current (possibly just-refreshed) token.
        let token = try await Credentials.validToken()
        do {
            return try await request(accessToken: token.accessToken)
        } catch UsageError.http(401, _) {
            // Token rejected — force a refresh and retry once.
            let refreshed = try await Credentials.refresh(token)
            return try await request(accessToken: refreshed.accessToken)
        }
    }

    private static func request(accessToken: String) async throws -> UsageResponse {
        var req = URLRequest(url: usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.http(-1, "no response")
        }
        if http.statusCode == 429 {
            let header = http.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = header.flatMap(Double.init) ?? 120
            throw UsageError.rateLimited(retryAfter: retryAfter)
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageError.http(http.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageError.decode(String(describing: error))
        }
    }
}
