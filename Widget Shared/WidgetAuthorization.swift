import Foundation
import Security

enum WidgetAuthorizationError: Error {
    case needsLogin
    case keychain(OSStatus)
    case invalidResponse
}

struct WidgetCredential: Codable {
    var refreshToken: String
    var accessToken: String?
    var expiresAt: Date?
    var clientID: String

    func usableAccessToken(at date: Date) -> String? {
        guard let expiresAt, expiresAt > date.addingTimeInterval(60) else { return nil }
        return accessToken
    }
}

enum WidgetCredentialStore {
    private static func query(_ id: Int) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "EVE.WidgetAuthorization",
            kSecAttrAccount as String: String(id),
            kSecAttrAccessGroup as String: WidgetStore.appGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func read(_ id: Int) throws -> WidgetCredential? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw WidgetAuthorizationError.keychain(status) }
        guard let data = result as? Data else { throw WidgetAuthorizationError.invalidResponse }
        return try JSONDecoder().decode(WidgetCredential.self, from: data)
    }

    static func write(_ credential: WidgetCredential, id: Int) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let query = query(id)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WidgetAuthorizationError.keychain(status) }
    }

    static func remove(_ id: Int) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
        else { throw WidgetAuthorizationError.keychain(status) }
    }

    /// The pre-shared-storage app used an account-only Keychain item.
    static func privateToken(_ id: Int) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "token_\(id)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw WidgetAuthorizationError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { throw WidgetAuthorizationError.invalidResponse }
        return token
    }

    static func removePrivateToken(_ id: Int) {
        for account in ["token_\(id)", "token_timestamp_\(id)"] {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
            ] as CFDictionary)
        }
    }
}

actor WidgetAuthorization {
    static let shared = WidgetAuthorization()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func install(_ credential: WidgetCredential, id: Int) async throws {
        let lock = try await WidgetFileLock.acquire("auth-\(id)")
        defer { withExtendedLifetime(lock) {} }
        try WidgetCredentialStore.write(credential, id: id)
    }

    /// Called by the app before credential checks. Never replaces a shared token,
    /// including an empty token recording an explicit logout or invalid_grant.
    func prepareExistingCredential(for id: Int, clientID: String) async throws -> Bool {
        let lock = try await WidgetFileLock.acquire("auth-\(id)")
        defer { withExtendedLifetime(lock) {} }
        if let current = try WidgetCredentialStore.read(id) {
            WidgetCredentialStore.removePrivateToken(id)
            return !current.refreshToken.isEmpty
        }
        guard let token = try WidgetCredentialStore.privateToken(id) else { return false }
        try WidgetCredentialStore.write(.init(refreshToken: token, clientID: clientID), id: id)
        guard try WidgetCredentialStore.read(id)?.refreshToken == token else {
            throw WidgetAuthorizationError.invalidResponse
        }
        WidgetCredentialStore.removePrivateToken(id)
        return true
    }

    func revoke(_ id: Int) async throws {
        let lock = try await WidgetFileLock.acquire("auth-\(id)")
        defer { withExtendedLifetime(lock) {} }
        try WidgetCredentialStore.write(.init(refreshToken: "", clientID: ""), id: id)
    }

    func accessToken(
        for id: Int, rejecting rejectedToken: String? = nil,
        deadline: Date = Date().addingTimeInterval(30)
    ) async throws -> String {
        let lock = try await WidgetFileLock.acquire("auth-\(id)", timeout: max(0, deadline.timeIntervalSinceNow))
        defer { withExtendedLifetime(lock) {} }
        guard var credential = try WidgetCredentialStore.read(id),
              !credential.refreshToken.isEmpty else { throw WidgetAuthorizationError.needsLogin }
        if let token = credential.usableAccessToken(at: Date()), token != rejectedToken {
            return token
        }

        guard Date() < deadline else { throw URLError(.timedOut) }
        var request = URLRequest(url: URL(string: "https://login.eveonline.com/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = min(10, max(1, deadline.timeIntervalSinceNow))
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form([
            "grant_type": "refresh_token", "refresh_token": credential.refreshToken, "client_id": credential.clientID,
        ])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw WidgetAuthorizationError.invalidResponse }
        if response.statusCode == 400,
           (try? JSONDecoder().decode(OAuthFailure.self, from: data).error) == "invalid_grant"
        {
            try WidgetCredentialStore.write(.init(refreshToken: "", clientID: ""), id: id)
            throw WidgetAuthorizationError.needsLogin
        }
        guard response.statusCode == 200 else { throw WidgetAuthorizationError.invalidResponse }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !token.access_token.isEmpty, token.expires_in > 0 else { throw WidgetAuthorizationError.invalidResponse }
        credential.accessToken = token.access_token
        credential.expiresAt = Date().addingTimeInterval(token.expires_in)
        credential.refreshToken = token.refresh_token ?? credential.refreshToken
        try WidgetCredentialStore.write(credential, id: id)
        return token.access_token
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }

    private struct OAuthFailure: Decodable { let error: String }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: TimeInterval
    }
}
