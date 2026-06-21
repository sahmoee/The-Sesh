//
//  SeshApp.swift
//  The SESH — your cannabis companion
//

import SwiftUI

@main
struct SeshApp: App {
    @UIApplicationDelegateAdaptor(SeshAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = AppSession()
    @State private var strains = StrainStore()
    @State private var social = SocialStore()
    @State private var wishlist = WishlistStore()
    @State private var theme = ThemeManager()
    @State private var auth = AuthManager()
    @State private var notifications = NotificationManager()
    @AppStorage("sesh.skippedSignIn") private var skippedSignIn = false
    @AppStorage("sesh.onboarded.v2") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboarded {
                    OnboardingView(onDone: { onboarded = true })
                } else if auth.isSignedIn || skippedSignIn {
                    RootView()
                } else {
                    SignInView(onContinueWithout: { skippedSignIn = true })
                }
            }
            .environment(session)
            .environment(strains)
            .environment(social)
            .environment(wishlist)
            .environment(theme)
            .environment(auth)
            .environment(notifications)
            .task {
                // Let the social layer push friend events into the notifier.
                social.notifications = notifications
                social.configure(userID: auth.userID, displayName: session.userName)
                await social.bootstrap()
                // Wire push: let the manager reach the social layer, then ask
                // for permission + register once the user is past onboarding.
                PushManager.shared.social = social
                if onboarded && (auth.isSignedIn || skippedSignIn) {
                    PushManager.shared.requestAndRegister()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Tell the notifier whether we're foreground (banner) or
                // background (lock-screen local notification).
                notifications.scenePhaseActive = (phase == .active)
                if phase == .active { notifications.dismissBanner() }
            }
            .onChange(of: auth.userID) { _, _ in
                social.configure(userID: auth.userID, displayName: session.userName)
            }
            .onChange(of: session.userName) { _, _ in
                social.configure(userID: auth.userID, displayName: session.userName)
            }
        }
    }
}
