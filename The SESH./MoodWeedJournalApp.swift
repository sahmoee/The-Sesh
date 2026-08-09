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
    @State private var comparisonHistory = ComparisonHistoryStore()
    @State private var lounge = LoungeFeedStore()
    @State private var theme = ThemeManager()
    @State private var auth = AuthManager()
    @State private var strainImages = StrainImageStore()
    @State private var notifications = NotificationManager()
    @State private var scrobbler = ScrobbleStore()
    @State private var spotify = SpotifyAuth()
    @State private var playlists = PlaylistStore()
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
            .environment(comparisonHistory)
            .environment(lounge)
            .environment(theme)
            .environment(auth)
            .environment(strainImages)
            .environment(notifications)
            .environment(scrobbler)
            .environment(spotify)
            .environment(playlists)
            .task {
                // Apply the stored haptics preference at launch.
                Haptics.isEnabled = session.hapticsEnabled
                // Let the social layer push friend events into the notifier.
                social.notifications = notifications
                social.configure(userID: auth.userID, displayName: session.userName)
                await social.bootstrap()
                // Cold launch: become "ready" if away (mirrors the scenePhase hook,
                // which only fires on change, not the initial launch).
                social.enterReadyIfAway()
                // Wire the scrobbler to the social layer and start any enabled
                // music sources (Apple Music on-device and/or Spotify polling).
                scrobbler.social = social
                scrobbler.playlists = playlists
                scrobbler.session = session
                scrobbler.configure(identity: social.identitySnapshot)
                spotify.configure(identity: social.identitySnapshot)
                lounge.configure(identity: social.identitySnapshot)
                playlists.spotify = spotify
                playlists.configure(identity: social.identitySnapshot)
                scrobbler.start()
                // Load the strain-image manifest from the Worker (fetch-on-demand;
                // nothing bundled). Falls back to procedural art if unreachable.
                if let base = URL(string: BuildConfig.workerURL) {
                    await strainImages.configure(baseURL: base)
                }
                // Wire push: let the manager reach the social layer, then ask
                // for permission + register once the user is past onboarding.
                PushManager.shared.social = social
                if onboarded && (auth.isSignedIn || skippedSignIn) {
                    PushManager.shared.requestAndRegister()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Foreground -> in-app banner; background -> lock-screen alert.
                notifications.scenePhaseActive = (phase == .active)
                if phase == .active {
                    notifications.dismissBanner()
                    // Opening the app makes you "ready" — but only if you were away
                    // and not mid-sesh, so this never overrides a live status.
                    social.enterReadyIfAway()
                }
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
