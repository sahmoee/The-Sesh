//
//  SeshAuth.swift
//  The SESH
//
//  (#C1) Client half of server-side authentication. The Worker no longer
//  trusts client-supplied identity headers; instead the app exchanges a
//  verified credential for a short-lived session token and sends it as
//  `Authorization: Bearer` on every request.
//
//  Two exchange paths:
//    - exchangeApple(identityToken:) after Sign in with Apple. The Worker
//      verifies the token against Apple's JWKS and binds the session to the
//      Apple `sub`.
//    - exchangeGuest(deviceID:) for "continue without signing in".
//
//  Tokens live ~24h. SeshAPI asks for a refresh on a 401 and retries once,
//  so expiry is invisible to the UI.
//

import Foundation
import Security
import AuthenticationServices
import DeviceCheck

@MainActor
@Observable
final class SeshAuth {
    static let shared = SeshAuth()
    private init() { token = Self.keychainRead() }

    /// The current session token, if any.
    private(set) var token: String?
    /// Verified backend uid ("apple:…" or "guest:…").
    private(set) var uid: String?

    /// Profile fields remembered so an expired guest session can be
    /// re-exchanged silently.
    private var lastHandle = ""
    private var lastName = ""
    private var lastCode = ""
    private var lastGuestDeviceID: String?

    private struct AuthResponse: Decodable { let token: String; let uid: String }

    // MARK: Exchange

    /// Exchange a Sign in with Apple identity token for a session.
    @discardableResult
    func exchangeApple(identityToken: String, handle: String, name: String, code: String) async -> Bool {
        remember(handle: handle, name: name, code: code)
        return await exchange(path: "/api/auth/apple",
                              body: ["identityToken": identityToken,
                                     "handle": handle, "name": name, "code": code])
    }

    /// Exchange a device-scoped guest identity for a session.
    @discardableResult
    func exchangeGuest(deviceID: String, handle: String, name: String, code: String) async -> Bool {
        remember(handle: handle, name: name, code: code)
        lastGuestDeviceID = deviceID
        return await exchange(path: "/api/auth/guest",
                              body: ["deviceID": deviceID,
                                     "handle": handle, "name": name, "code": code])
    }

    /// Called by SeshAPI after a 401. Guests re-exchange from the stored device
    /// id. Apple users, if their credential is still authorized, get a FRESH
    /// identity token and re-exchange — this is what survives a SESSION_SECRET
    /// rotation or a normal token expiry without a hard logout.
    func refreshIfNeeded() async -> Bool {
        if let deviceID = lastGuestDeviceID {
            return await exchangeGuest(deviceID: deviceID, handle: lastHandle,
                                       name: lastName, code: lastCode)
        }
        if let appleUserID = UserDefaults.standard.string(forKey: "sesh.apple.userID"),
           !appleUserID.isEmpty {
            return await reexchangeApple(userID: appleUserID)
        }
        return false
    }

    /// Re-mint a session for an existing Sign in with Apple user.
    ///
    /// `getCredentialState` is a cheap, silent check: only if the user is still
    /// signed in with Apple do we ask for a fresh identity token. For an
    /// authorized user that request is typically frictionless (no sign-in sheet;
    /// at most a quick system confirmation). If the credential was revoked or is
    /// gone, we return false and the app falls back to the normal sign-in screen —
    /// which is correct, because at that point the user really did sign out.
    private func reexchangeApple(userID: String) async -> Bool {
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState =
            await withCheckedContinuation { cont in
                provider.getCredentialState(forUserID: userID) { state, _ in
                    cont.resume(returning: state)
                }
            }
        guard state == .authorized else { return false }
        guard let identityToken = await AppleReauth.freshIdentityToken() else { return false }
        // handle/name/code are profile hints only; the Worker binds the session to
        // the verified Apple `sub` in the identity token, so empty hints are fine.
        return await exchangeApple(identityToken: identityToken,
                                   handle: lastHandle, name: lastName, code: lastCode)
    }

    func signOut() {
        token = nil
        uid = nil
        Self.keychainDelete()
    }

    // MARK: Internals

    private func remember(handle: String, name: String, code: String) {
        lastHandle = handle; lastName = name; lastCode = code
    }

    /// Adopt a session the Worker re-minted for the SAME verified uid — used
    /// after a profile (display name / handle) update, so the name carried in
    /// the session claims, and therefore stamped onto outgoing chat messages,
    /// matches what the user actually set. No re-authentication is involved:
    /// the Worker only issues this in response to an already-valid session.
    func adoptRefreshedSession(token newToken: String, uid newUID: String,
                               handle: String, name: String, code: String) {
        guard !newToken.isEmpty else { return }
        remember(handle: handle, name: name, code: code)
        token = newToken
        uid = newUID
        Self.keychainWrite(newToken)
    }

    private func exchange(path: String, body: [String: String]) async -> Bool {
        guard let base = URL(string: BuildConfig.workerURL),
              let url = URL(string: path, relativeTo: base) else { return false }
        var payload = body
        // (#C2) Attach a DeviceCheck token when available. The Worker validates
        // it with Apple, gating account creation and messaging behind proof of
        // a real Apple device (enforced when DEVICECHECK_REQUIRED=1).
        if let dcToken = await Self.deviceCheckToken() {
            payload["dcToken"] = dcToken
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(payload)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = decoded.token
            uid = decoded.uid
            Self.keychainWrite(decoded.token)
            return true
        } catch {
            return false
        }
    }

    /// Generate a DeviceCheck token (nil on Simulator / unsupported devices).
    private static func deviceCheckToken() async -> String? {
        guard DCDevice.current.isSupported else { return nil }
        return await withCheckedContinuation { cont in
            DCDevice.current.generateToken { data, _ in
                cont.resume(returning: data?.base64EncodedString())
            }
        }
    }

    // MARK: Keychain (session tokens do not belong in UserDefaults)

    private static let service = "com.sowens.The-SESH-.session"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "session-token"]
    }

    private static func keychainRead() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ token: String) {
        let data = Data(token.utf8)
        var q = query()
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    private static func keychainDelete() {
        SecItemDelete(query() as CFDictionary)
    }
}

// MARK: - Silent Sign in with Apple re-request

/// Runs one Sign in with Apple request and returns the fresh identity token,
/// or nil on failure.
@MainActor
private final class AppleReauth: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    static func freshIdentityToken() async -> String? {
        await AppleReauth().run()
    }

    private var continuation: CheckedContinuation<String?, Never>?

    private func run() async -> String? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []          // name/email already stored; don't re-ask
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return await withCheckedContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithAuthorization authorization: ASAuthorization) {
        let token = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .identityToken
            .flatMap { String(data: $0, encoding: .utf8) }
        continuation?.resume(returning: token)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
