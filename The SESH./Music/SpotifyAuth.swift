//
//  SpotifyAuth.swift
//  The SESH
//
//  Spotify account linking via OAuth (Authorization Code with PKCE). The flow:
//    1. App opens Spotify's authorize URL in an ASWebAuthenticationSession.
//    2. User approves; Spotify redirects to our custom scheme with a `code`.
//    3. App sends the code to OUR Worker (/api/spotify/exchange), which swaps it
//       for tokens using the client secret (kept server-side) and stores the
//       refresh token against the user's identity.
//    4. From then on, the Worker can fetch the user's now-playing on demand.
//
//  The client never holds the client secret. We use PKCE so even the authorize
//  step needs no secret in the app.
//
//  SETUP REQUIRED (see the setup guide): a Spotify Developer app providing the
//  client ID, plus the redirect URI registered there and mirrored here.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Observation

@Observable
@MainActor
final class SpotifyAuth: NSObject {
    /// Whether the user has linked Spotify.
    var isConnected: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.spotifyConnected)

    /// Last error message, for surfacing in the UI.
    var lastError: String?

    private let api = SeshAPI()
    private var identity: SeshIdentity?
    private var session: ASWebAuthenticationSession?
    private var pkceVerifier: String = ""
    /// OAuth `state` for the in-flight authorization; the callback must echo it.
    private var oauthState: String = ""

    // --- These come from your Spotify Developer app (see setup guide) ---
    // The client ID is NOT a secret and is safe to ship.
    static let clientID = SpotifyConfig.clientID
    // Must EXACTLY match a Redirect URI registered in the Spotify dashboard.
    static let redirectURI = SpotifyConfig.redirectURI   // e.g. "thesesh://spotify-callback"
    static let scopes = "user-read-currently-playing user-read-playback-state playlist-modify-public playlist-modify-private"

    func configure(identity: SeshIdentity?) { self.identity = identity }

    // MARK: Connect

    func connect() {
        lastError = nil
        guard !Self.clientID.isEmpty else {
            lastError = "Spotify isn't configured yet."
            return
        }
        // PKCE: make a verifier + its SHA256 challenge, plus an OAuth `state`
        // value so a callback this app didn't start is rejected (RFC 6749 10.12).
        guard let verifier = Self.randomURLSafe(64), let state = Self.randomURLSafe(32) else {
            lastError = "Couldn't start Spotify sign-in securely. Try again."
            return
        }
        pkceVerifier = verifier
        oauthState = state
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
        ]
        guard let url = comps.url else { return }

        let scheme = URL(string: Self.redirectURI)?.scheme
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self else { return }
            if let error {
                // User cancel is not an error worth surfacing loudly.
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    self.lastError = "Spotify sign-in failed."
                }
                return
            }
            let items = callback.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
            } ?? []
            guard state == self.oauthState,
                  items.first(where: { $0.name == "state" })?.value == state else {
                self.lastError = "Spotify sign-in couldn't be verified. Try again."
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                self.lastError = "No authorization code returned."
                return
            }
            Task { await self.exchange(code: code) }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        self.session = s
        s.start()
    }

    /// Send the code (+ PKCE verifier) to our Worker, which does the secret-side
    /// token swap and stores the refresh token against this user.
    private func exchange(code: String) async {
        let ok = await api.spotifyExchange(code: code, verifier: pkceVerifier,
                                           redirectURI: Self.redirectURI, identity: identity)
        isConnected = ok
        UserDefaults.standard.set(ok, forKey: DefaultsKey.spotifyConnected)
        if !ok { lastError = "Couldn't link Spotify. Try again." }
    }

    func disconnect() {
        Task { _ = await api.spotifyDisconnect(identity: identity) }
        isConnected = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.spotifyConnected)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.spotifyRefreshToken)
    }

    // MARK: PKCE helpers

    /// Cryptographically random URL-safe string, or nil if the system RNG
    /// fails — previously a failure silently produced an all-zero verifier.
    private static func randomURLSafe(_ count: Int) -> String? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes).base64URLEncoded()
    }
    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Prefer the active scene's key window. If none is found, build an anchor
        // from a connected window scene (init() without a scene is deprecated in
        // iOS 26); only fall back to a bare window if there's truly no scene.
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first {
            return keyWindow
        }
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return UIWindow(windowScene: scene)
        }
        return ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
