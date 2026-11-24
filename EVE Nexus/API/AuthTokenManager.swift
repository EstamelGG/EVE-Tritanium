@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager {
    static let shared = AuthTokenManager()
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private let authorization: WidgetAuthorization

    init(authorization: WidgetAuthorization = .shared) {
        self.authorization = authorization
    }

    func authorize(presenting viewController: UIViewController, scopes: [String]) async throws -> OIDAuthState {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let configuration = OIDServiceConfiguration(
                    authorizationEndpoint: EVEConfig.OAuth.authorizationEndpoint,
                    tokenEndpoint: EVEConfig.OAuth.tokenEndpoint
                )
                let request = OIDAuthorizationRequest(
                    configuration: configuration,
                    clientId: EVEConfig.OAuth.clientId,
                    clientSecret: nil,
                    scopes: scopes,
                    redirectURL: EVEConfig.OAuth.redirectURI,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: nil
                )
                let flow = OIDAuthState.authState(byPresenting: request, presenting: viewController) { state, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let state {
                        continuation.resume(returning: state)
                    } else {
                        continuation
                            .resume(throwing: NetworkError.authenticationError("OAuth returned empty auth state"))
                    }
                }
                await self.setAuthorizationFlow(flow)
            }
        }
    }

    private func setAuthorizationFlow(_ flow: OIDExternalUserAgentSession?) {
        currentAuthorizationFlow = flow
    }

    func saveAuthState(_ state: OIDAuthState, for id: Int) async throws {
        guard let refreshToken = state.refreshToken else { throw NetworkError.invalidData }
        try await authorization.install(.init(
            refreshToken: refreshToken,
            accessToken: state.lastTokenResponse?.accessToken,
            expiresAt: state.lastTokenResponse?
                .accessTokenExpirationDate,
            clientID: EVEConfig.OAuth.clientId
        ), id: id)
        try await WidgetStore.shared.removeCharacter(id)
    }

    func getCachedAccessToken(for id: Int) -> String? {
        try? WidgetCredentialStore.read(id)?.accessToken
    }

    func getAccessToken(for id: Int) async throws -> String {
        do {
            guard try await authorization.prepareExistingCredential(for: id, clientID: EVEConfig.OAuth.clientId)
            else { throw WidgetAuthorizationError.needsLogin }
            let token = try await authorization.accessToken(for: id)
            EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(characterId: id, expired: false)
            return token
        } catch WidgetAuthorizationError.needsLogin {
            EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(characterId: id, expired: true)
            throw NetworkError.refreshTokenExpired
        }
    }

    func validateStoredCredentials() async {
        let accounts = EVELogin.shared.loadCharacters().map(\.character)
        for account in accounts {
            let id = account.CharacterID
            do {
                let available = try await authorization.prepareExistingCredential(
                    for: id, clientID: EVEConfig.OAuth.clientId
                )
                if !available {
                    EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(characterId: id, expired: true)
                } else if account.refreshTokenExpired {
                    // Confirm a flagged account can actually renew before restoring it.
                    _ = try await getAccessToken(for: id)
                }
            } catch {
                // A locked/unavailable Keychain or network error is not revoked authorization.
                Logger.error("暂时无法检查角色 \(id) 的授权: \(type(of: error))")
            }
        }
    }

    func clearAllTokens(for id: Int) async {
        do {
            try await authorization.revoke(id)
            try await WidgetStore.shared.removeCharacter(id)
        } catch { Logger.error("无法清除共享授权: \(error)") }
    }
}
