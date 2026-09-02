import Foundation
import CryptoKit

// MARK: - Platform

enum SocialPlatform: String, CaseIterable, Identifiable, Codable {
    case youtube
    case tiktok
    case instagram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        }
    }

    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .tiktok: return "music.note"
        case .instagram: return "camera"
        }
    }

    /// What a "draft" means for each platform.
    var draftDescription: String {
        switch self {
        case .youtube: return "Uploaded privately (draft)"
        case .tiktok: return "Uploaded as self-only (draft)"
        case .instagram: return "Reel published via public URL"
        }
    }

    var callbackURL: URL {
        URL(string: "rpsbattle://oauth/\(rawValue)")!
    }

    var scopes: [String] {
        switch self {
        case .youtube:
            return ["https://www.googleapis.com/auth/youtube.upload"]
        case .tiktok:
            return ["user.info.basic", "video.publish"]
        case .instagram:
            return ["instagram_basic", "instagram_content_publish", "pages_show_list", "pages_read_engagement"]
        }
    }

    var scopesJoined: String {
        switch self {
        case .youtube, .instagram:
            return scopes.joined(separator: " ")
        case .tiktok:
            return scopes.joined(separator: ",")
        }
    }

    /// Builds the OAuth authorization URL for this platform.
    func buildAuthURL(credentials: SocialCredentials, state: String, codeChallenge: String) -> URL? {
        var components = URLComponents()
        switch self {
        case .youtube:
            components.scheme = "https"
            components.host = "accounts.google.com"
            components.path = "/o/oauth2/v2/auth"
            components.queryItems = [
                URLQueryItem(name: "client_id", value: credentials.youtubeClientID),
                URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopesJoined),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
            ]
        case .tiktok:
            components.scheme = "https"
            components.host = "www.tiktok.com"
            components.path = "/v2/auth/authorize/"
            components.queryItems = [
                URLQueryItem(name: "client_key", value: credentials.tiktokClientKey),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopesJoined),
                URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]
        case .instagram:
            components.scheme = "https"
            components.host = "www.facebook.com"
            components.path = "/v18.0/dialog/oauth"
            components.queryItems = [
                URLQueryItem(name: "client_id", value: credentials.instagramAppID),
                URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopesJoined),
                URLQueryItem(name: "state", value: state),
            ]
        }
        return components.url
    }
}

// MARK: - Credentials

/// API credentials supplied by the user from their own developer accounts.
struct SocialCredentials: Codable, Equatable {
    var youtubeClientID: String = ""
    var youtubeClientSecret: String = ""
    var tiktokClientKey: String = ""
    var tiktokClientSecret: String = ""
    var instagramAppID: String = ""
    var instagramAppSecret: String = ""
    /// Instagram's Reels API only accepts a publicly hosted video URL.
    var instagramVideoURL: String = ""

    static let defaultsKey = "socialCredentials"

    static func load() -> SocialCredentials {
        guard let json = KeychainStore.load(defaultsKey),
              let data = json.data(using: .utf8),
              let creds = try? JSONDecoder().decode(SocialCredentials.self, from: data) else {
            return SocialCredentials()
        }
        return creds
    }

    @discardableResult
    func save() -> Bool {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return false }
        return KeychainStore.save(json, for: Self.defaultsKey)
    }

    func hasCredentials(for platform: SocialPlatform) -> Bool {
        switch platform {
        case .youtube: return !youtubeClientID.isEmpty && !youtubeClientSecret.isEmpty
        case .tiktok: return !tiktokClientKey.isEmpty && !tiktokClientSecret.isEmpty
        case .instagram: return !instagramAppID.isEmpty && !instagramAppSecret.isEmpty
        }
    }
}

// MARK: - Stored token

/// OAuth token persisted in the Keychain for a connected platform.
struct StoredToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var accountID: String?
    var accountName: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt.addingTimeInterval(-120)
    }
}

// MARK: - Connection state (UI-facing)

struct PlatformConnection: Codable {
    var connected: Bool
    var accountName: String?
}

// MARK: - Errors

enum SocialError: LocalizedError {
    case notConfigured(SocialPlatform)
    case notConnected(SocialPlatform)
    case authFailed(String)
    case cancelled
    case tokenExchangeFailed(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p):
            return "\(p.displayName) is not configured. Add your API credentials in Settings → Platforms."
        case .notConnected(let p):
            return "\(p.displayName) is not connected. Sign in from Settings → Platforms."
        case .authFailed(let m): return "Authentication failed: \(m)"
        case .cancelled: return "Sign-in was cancelled."
        case .tokenExchangeFailed(let m): return "Could not exchange authorization code: \(m)"
        case .uploadFailed(let m): return "Upload failed: \(m)"
        }
    }
}

// MARK: - PKCE helpers

enum PKCE {
    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLString()
    }

    static func state() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLString()
    }
}

extension Data {
    func base64URLString() -> String {
        var s = base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }
}
