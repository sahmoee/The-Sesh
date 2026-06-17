//
//  AppleAuth.swift
//  The SESH
//
//  Sign in with Apple. Stores the stable Apple user identifier and the name
//  Apple returns on first sign-in (Apple only provides the name once). Identity
//  is mirrored to iCloud so the signed-in profile follows the user to a new
//  device. Requires the "Sign in with Apple" capability on the app target.
//

import SwiftUI
import AuthenticationServices

@Observable
final class AuthManager {
    var userID: String?          // stable Apple user identifier
    var fullName: String?
    var email: String?
    var isSignedIn: Bool { userID != nil }

    private let idKey = "sesh.apple.userID"
    private let nameKey = "sesh.apple.name"
    private let emailKey = "sesh.apple.email"

    init() {
        CloudSync.pullIntoDefaults(keys: [idKey, nameKey, emailKey])
        let d = UserDefaults.standard
        userID = d.string(forKey: idKey)
        fullName = d.string(forKey: nameKey)
        email = d.string(forKey: emailKey)
    }

    /// Configure the request to ask for name + email.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    /// Handle the completion from SignInWithAppleButton.
    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            userID = cred.user
            CloudSync.set(cred.user, forKey: idKey)
            if let name = cred.fullName {
                let parts = [name.givenName, name.familyName].compactMap { $0 }
                let joined = parts.joined(separator: " ")
                if !joined.isEmpty { fullName = joined; CloudSync.set(joined, forKey: nameKey) }
            }
            if let mail = cred.email { email = mail; CloudSync.set(mail, forKey: emailKey) }
            Haptics.success()
        case .failure:
            Haptics.warning()
        }
    }

    func signOut() {
        userID = nil; fullName = nil; email = nil
        let d = UserDefaults.standard
        d.removeObject(forKey: idKey); d.removeObject(forKey: nameKey); d.removeObject(forKey: emailKey)
    }
}

// MARK: - Sign-in screen

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSession.self) private var session
    @Environment(\.colorScheme) private var scheme

    var onContinueWithout: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer()
                // Wordmark lockup
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("The").font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(Palette.text.opacity(0.9))
                    Text("SESH").font(.system(size: 60, weight: .bold, design: .serif)).foregroundStyle(Palette.text).tracking(1)
                }
                Text("Your cannabis companion.\nTrack, sesh & connect.")
                    .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center).padding(.top, 10)

                Spacer()

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        auth.configure(request)
                    } onCompletion: { result in
                        auth.handle(result)
                        if let name = auth.fullName, session.userName == "Alex" || session.userName.isEmpty {
                            session.userName = name; session.save()
                        }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    Button {
                        onContinueWithout?()
                    } label: {
                        Text("Continue without signing in")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Text("Signing in syncs your sessions, thoughts, and settings across your devices via iCloud.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
                .padding(.horizontal, 28).padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Compact sign-in button (for Profile when signed out)

struct AppleSignInRow: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSession.self) private var session
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            auth.configure(request)
        } onCompletion: { result in
            auth.handle(result)
            if let name = auth.fullName, session.userName == "Alex" || session.userName.isEmpty {
                session.userName = name; session.save()
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
