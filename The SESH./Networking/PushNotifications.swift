//
//  PushNotifications.swift
//  The SESH
//
//  Registers for remote (APNs) push so friends' "went live / sparked up" events
//  can notify this device. Flow:
//    1. PushManager.shared.requestAndRegister() asks for permission and, if
//       granted, calls registerForRemoteNotifications().
//    2. The AppDelegate receives the device token and hands it to PushManager.
//    3. PushManager forwards it to SocialStore.registerPushToken(_:), which
//       POSTs it to the Worker (/api/push/register).
//
//  REQUIRES (Xcode): the "Push Notifications" capability on the app target, and
//  a paid Apple Developer account. The actual sending is done by the Worker
//  using your APNs .p8 key — see the Worker + README.
//

import SwiftUI
import UserNotifications
import UIKit

/// Bridges UIKit push callbacks into our SwiftUI world.
@MainActor
final class PushManager {
    static let shared = PushManager()
    private init() {}

    /// Set by SeshApp so the manager can forward tokens to the social layer.
    weak var social: SocialStore?

    /// Whether the user has granted notification permission.
    private(set) var authorized = false

    /// Ask for permission (once) and register with APNs if granted.
    func requestAndRegister() {
        guard UserDefaults.standard.object(forKey: DefaultsKey.notifEnabled) as? Bool ?? true else {
            updateEnabled(false)
            return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
            }
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if authorized { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Keep the system registration and Worker token in lockstep with the
    /// user-facing Settings toggle.
    func updateEnabled(_ enabled: Bool) {
        if enabled {
            requestAndRegister()
        } else {
            authorized = false
            UIApplication.shared.unregisterForRemoteNotifications()
            social?.disablePushNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    /// Called by the AppDelegate with the raw APNs token data.
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard !hex.isEmpty else { return }
        social?.registerPushToken(hex)
    }
}

/// UIKit application delegate, attached to SwiftUI via @UIApplicationDelegateAdaptor.
final class SeshAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Registration can fail in the Simulator or without the capability —
        // fail quietly; the rest of the app is unaffected.
    }

    /// Show non-duplicated banners even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Realtime feed ingestion already presents friend activity in-app. Do
        // not show the matching APNs banner as well when foregrounded.
        if notification.request.content.userInfo["kind"] as? String == "friend_activity" {
            return []
        }
        return [.banner, .sound]
    }
}
