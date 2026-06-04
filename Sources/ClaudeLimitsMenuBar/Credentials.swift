import Foundation
import Security

/// Errors surfaced to the UI as a clear "not logged in" state.
enum CredentialError: Error, CustomStringConvertible {
    case notFound
    case malformed
    case refreshFailed(String)

    var description: String {
        switch self {
        case .notFound: return "Not logged in — run `claude` and sign in"
        case .malformed: return "Couldn't read Claude credentials"
        case .refreshFailed(let m): return "Token refresh failed: \(m)"
        }
    }
}

/// The token blob Claude Code stores in the Keychain under service "Claude Code-credentials":
/// `{ "claudeAiOauth": { accessToken, refreshToken, expiresAt(ms), scopes[], subscriptionType, rateLimitTier } }`
struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double            // epoch milliseconds
    var scopes: [String]?
    var subscriptionType: String?
    var rateLimitTier: String?

    var isExpired: Bool {
        // Treat as expired 60s early to avoid races.
        Date().timeIntervalSince1970 * 1000 >= (expiresAt - 60_000)
    }
}

private struct CredentialEnvelope: Codable {
    var claudeAiOauth: OAuthToken
}

/// Reads, refreshes, and writes back the OAuth token shared with the Claude Code CLI.
/// Refreshing in place (SecItemUpdate) keeps a single login working for both the CLI and this app.
enum Credentials {
    static let keychainService = "Claude Code-credentials"
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    // MARK: Keychain I/O

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
    }

    static func readRaw() throws -> Data {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw CredentialError.notFound }
        guard let data = item as? Data else { throw CredentialError.malformed }
        return data
    }

    static func load() throws -> OAuthToken {
        let data = try readRaw()
        guard let env = try? JSONDecoder().decode(CredentialEnvelope.self, from: data) else {
            throw CredentialError.malformed
        }
        return env.claudeAiOauth
    }

    /// Persist an updated token back to the same Keychain entry, preserving any other
    /// fields that were in the original blob (we only touch the OAuth object).
    static func save(_ token: OAuthToken) throws {
        // Re-read so we don't clobber sibling keys we don't model.
        var object: [String: Any] = [:]
        if let data = try? readRaw(),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = json
        }
        object["claudeAiOauth"] = [
            "accessToken": token.accessToken,
            "refreshToken": token.refreshToken,
            "expiresAt": token.expiresAt,
            "scopes": token.scopes ?? [],
            "subscriptionType": token.subscriptionType as Any,
            "rateLimitTier": token.rateLimitTier as Any,
        ]
        let newData = try JSONSerialization.data(withJSONObject: object)

        let attrs: [String: Any] = [kSecValueData as String: newData]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            // Non-fatal: the in-memory token still works for this run.
            NSLog("ClaudeLimits: SecItemUpdate failed (\(status)); token not written back")
        }
    }

    // MARK: Refresh

    private struct RefreshResponse: Codable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Double?      // seconds
    }

    /// Returns a valid (non-expired) token, refreshing and writing it back if needed.
    static func validToken() async throws -> OAuthToken {
        let token = try load()
        guard token.isExpired else { return token }
        return try await refresh(token)
    }

    static func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CredentialError.refreshFailed("no response")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CredentialError.refreshFailed(msg)
        }
        let parsed = try JSONDecoder().decode(RefreshResponse.self, from: data)

        var updated = token
        updated.accessToken = parsed.access_token
        if let rt = parsed.refresh_token { updated.refreshToken = rt }
        if let expiresIn = parsed.expires_in {
            updated.expiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        try save(updated)
        return updated
    }
}
