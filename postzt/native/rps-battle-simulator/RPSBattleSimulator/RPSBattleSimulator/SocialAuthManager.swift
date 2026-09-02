import Foundation
import AuthenticationServices
import Combine

// NOTE: Direct social publishing is retired. All publishing now happens through
// TryPost (the single publisher), so this OAuth path is dormant and no longer
// surfaced in the UI. Kept in place only so the code remains available if it is
// ever revived; the headless CLI export path does not call into SocialUploader.

/// Manages OAuth connections to YouTube, TikTok, and Instagram.
/// Sign-in happens in a native ASWebAuthenticationSession popup (stays in-app,
/// no browser tab), and tokens are persisted in the Keychain.
@MainActor
final class SocialAuthManager: ObservableObject {

    @Published var credentials: SocialCredentials = SocialCredentials.load()
    @Published private(set) var connections: [SocialPlatform: PlatformConnection] = [:]
    @Published var isConnecting: Bool = false
    @Published var lastError: String? = nil

    private var authSession: ASWebAuthenticationSession?

    init() {
        reloadConnectionStates()
    }

    // MARK: - State

    func saveCredentials() {
        if !credentials.save() {
            lastError = "Could not save credentials to the Keychain."
        }
    }

    func reloadConnectionStates() {
        var result: [SocialPlatform: PlatformConnection] = [:]
        for platform in SocialPlatform.allCases {
            if let token = storedToken(for: platform) {
                result[platform] = PlatformConnection(connected: true, accountName: token.accountName)
            } else {
                result[platform] = PlatformConnection(connected: false, accountName: nil)
            }
        }
        connections = result
    }

    func isConnected(_ platform: SocialPlatform) -> Bool {
        connections[platform]?.connected ?? false
    }

    // MARK: - Stored tokens

    private func tokenKey(for platform: SocialPlatform) -> String { "token.\(platform.rawValue)" }

    func storedToken(for platform: SocialPlatform) -> StoredToken? {
        guard let json = KeychainStore.load(tokenKey(for: platform)),
              let data = json.data(using: .utf8),
              let token = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }
        return token
    }

    private func saveToken(_ token: StoredToken, for platform: SocialPlatform) {
        if let data = try? JSONEncoder().encode(token),
           let json = String(data: data, encoding: .utf8),
           !KeychainStore.save(json, for: tokenKey(for: platform)) {
            lastError = "Could not save the \(platform.displayName) token to the Keychain."
        }
    }

    // MARK: - Connect / Disconnect

    func connect(_ platform: SocialPlatform) async throws {
        guard credentials.hasCredentials(for: platform) else {
            throw SocialError.notConfigured(platform)
        }
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let state = PKCE.state()
        guard let authURL = platform.buildAuthURL(credentials: credentials, state: state, codeChallenge: challenge) else {
            throw SocialError.authFailed("Could not build the authorization URL.")
        }

        isConnecting = true
        lastError = nil
        defer { isConnecting = false }

        let callback = try await presentAuthSession(url: authURL, callbackScheme: "rpsbattle")
        // Validate the OAuth state parameter to guard against CSRF.
        guard let returnedState = Self.queryValue("state", from: callback), returnedState == state else {
            throw SocialError.authFailed("OAuth state mismatch.")
        }
        guard let code = Self.extractCode(from: callback) else {
            throw SocialError.authFailed("No authorization code in the callback.")
        }

        let token = try await exchangeCode(code, platform: platform, verifier: verifier)
        saveToken(token, for: platform)
        reloadConnectionStates()
    }

    func disconnect(_ platform: SocialPlatform) {
        KeychainStore.delete(tokenKey(for: platform))
        reloadConnectionStates()
    }

    // MARK: - OAuth presentation (in-app popup)

    private func presentAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                self.authSession = nil
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: SocialError.cancelled)
                    } else {
                        continuation.resume(throwing: SocialError.authFailed(error.localizedDescription))
                    }
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: SocialError.authFailed("No callback received."))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session  // retain strongly until completion
            session.start()
        }
    }

    static func extractCode(from url: URL) -> String? {
        queryValue("code", from: url)
    }
    
    static func queryValue(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String, platform: SocialPlatform, verifier: String) async throws -> StoredToken {
        switch platform {
        case .youtube:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "client_id", value: credentials.youtubeClientID),
                URLQueryItem(name: "client_secret", value: credentials.youtubeClientSecret),
                URLQueryItem(name: "redirect_uri", value: platform.callbackURL.absoluteString),
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code_verifier", value: verifier),
            ]
            let url = URL(string: "https://oauth2.googleapis.com/token")!
            let (data, _) = try await Self.postForm(url: url, body: body.percentEncodedQuery ?? "")
            struct G: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double? }
            let g = try JSONDecoder().decode(G.self, from: data)
            return StoredToken(accessToken: g.access_token, refreshToken: g.refresh_token,
                               expiresAt: g.expires_in.map { Date().addingTimeInterval($0) })

        case .tiktok:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client_key", value: credentials.tiktokClientKey),
                URLQueryItem(name: "client_secret", value: credentials.tiktokClientSecret),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "redirect_uri", value: platform.callbackURL.absoluteString),
                URLQueryItem(name: "code_verifier", value: verifier),
            ]
            let url = URL(string: "https://open.tiktokapis.com/v2/oauth/token/")!
            let (data, _) = try await Self.postForm(url: url, body: body.percentEncodedQuery ?? "")
            struct T: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double?; let open_id: String? }
            let t = try JSONDecoder().decode(T.self, from: data)
            return StoredToken(accessToken: t.access_token, refreshToken: t.refresh_token,
                               expiresAt: t.expires_in.map { Date().addingTimeInterval($0) }, accountID: t.open_id)

        case .instagram:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client_id", value: credentials.instagramAppID),
                URLQueryItem(name: "client_secret", value: credentials.instagramAppSecret),
                URLQueryItem(name: "redirect_uri", value: platform.callbackURL.absoluteString),
                URLQueryItem(name: "code", value: code),
            ]
            let url = URL(string: "https://graph.facebook.com/v18.0/oauth/access_token")!
            let (data, _) = try await Self.postForm(url: url, body: body.percentEncodedQuery ?? "")
            struct F: Decodable { let access_token: String; let expires_in: Double? }
            let f = try JSONDecoder().decode(F.self, from: data)
            // Immediately exchange the short-lived token for a long-lived (~60 day) token.
            let longLived = try await exchangeInstagramLongLivedToken(f.access_token)
            return longLived
        }
    }
    
    private func exchangeInstagramLongLivedToken(_ token: String) async throws -> StoredToken {
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "fb_exchange_token"),
            URLQueryItem(name: "client_id", value: credentials.instagramAppID),
            URLQueryItem(name: "client_secret", value: credentials.instagramAppSecret),
            URLQueryItem(name: "fb_exchange_token", value: token),
        ]
        let url = URL(string: "https://graph.facebook.com/v18.0/oauth/access_token?\(body.percentEncodedQuery ?? "")")!
        let (data, _) = try await Self.get(url: url)
        struct F: Decodable { let access_token: String; let expires_in: Double? }
        let f = try JSONDecoder().decode(F.self, from: data)
        // Store the long-lived token itself as the "refresh" token so it can be re-exchanged.
        return StoredToken(accessToken: f.access_token, refreshToken: f.access_token,
                           expiresAt: f.expires_in.map { Date().addingTimeInterval($0) })
    }

    // MARK: - Token refresh

    func validAccessToken(for platform: SocialPlatform) async throws -> String {
        guard var token = storedToken(for: platform) else {
            throw SocialError.notConnected(platform)
        }
        if token.isExpired, let refreshToken = token.refreshToken {
            token = try await refresh(platform: platform, refreshToken: refreshToken)
            saveToken(token, for: platform)
        }
        return token.accessToken
    }

    private func refresh(platform: SocialPlatform, refreshToken: String) async throws -> StoredToken {
        switch platform {
        case .youtube:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client_id", value: credentials.youtubeClientID),
                URLQueryItem(name: "client_secret", value: credentials.youtubeClientSecret),
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
            ]
            let (data, _) = try await Self.postForm(url: URL(string: "https://oauth2.googleapis.com/token")!, body: body.percentEncodedQuery ?? "")
            struct G: Decodable { let access_token: String; let expires_in: Double? }
            let g = try JSONDecoder().decode(G.self, from: data)
            return StoredToken(accessToken: g.access_token, refreshToken: refreshToken,
                               expiresAt: g.expires_in.map { Date().addingTimeInterval($0) })

        case .tiktok:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client_key", value: credentials.tiktokClientKey),
                URLQueryItem(name: "client_secret", value: credentials.tiktokClientSecret),
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
            ]
            let (data, _) = try await Self.postForm(url: URL(string: "https://open.tiktokapis.com/v2/oauth/token/")!, body: body.percentEncodedQuery ?? "")
            struct T: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double?; let open_id: String? }
            let t = try JSONDecoder().decode(T.self, from: data)
            return StoredToken(accessToken: t.access_token, refreshToken: t.refresh_token ?? refreshToken,
                               expiresAt: t.expires_in.map { Date().addingTimeInterval($0) }, accountID: t.open_id)

        case .instagram:
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "grant_type", value: "fb_exchange_token"),
                URLQueryItem(name: "client_id", value: credentials.instagramAppID),
                URLQueryItem(name: "client_secret", value: credentials.instagramAppSecret),
                URLQueryItem(name: "fb_exchange_token", value: refreshToken),
            ]
            let url = URL(string: "https://graph.facebook.com/v18.0/oauth/access_token?\(body.percentEncodedQuery ?? "")")!
            let (data, _) = try await Self.get(url: url)
            struct F: Decodable { let access_token: String; let expires_in: Double? }
            let f = try JSONDecoder().decode(F.self, from: data)
            return StoredToken(accessToken: f.access_token, expiresAt: f.expires_in.map { Date().addingTimeInterval($0) })
        }
    }

    // MARK: - HTTP helpers

    static func postForm(url: URL, body: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialError.tokenExchangeFailed("Invalid response.") }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.tokenExchangeFailed("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return (data, http)
    }

    static func get(url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw SocialError.tokenExchangeFailed("Invalid response.") }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.tokenExchangeFailed("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return (data, http)
    }
}
