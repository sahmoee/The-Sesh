//
//  NotificationCenter.swift
//  The SESH
//
//  Central notification engine. Turns friend activity (which already arrives via
//  SocialStore's polling) into three surfaces:
//    1. In-app banner — shown when the app is foregrounded (scenePhase .active).
//    2. Lock-screen / system notification — a local UNNotificationRequest, used
//       when the app is NOT active (backgrounded).
//    3. A persistent in-app inbox (the bell screen), kept across launches.
//
//  ANTI-SPAM (in-app AND lock screen): friends flipping status rapidly, or many
//  friends being active at once, must NOT produce a flood. Three guards:
//    - Per-friend cooldown: after we surface a status change for a friend, further
//      status changes from that same friend are coalesced (inbox-only, no banner /
//      no lock-screen alert) until the cooldown elapses.
//    - Global rate limit: at most a few *surfaced* status alerts per minute across
//      all friends; the rest still land in the inbox silently.
//    - Banner shows only the newest item (no stacked backlog).
//  Invites and chats are exempt from the status throttle (they're not spammy and
//  the user expects them), but still de-dupe by id.
//
//  NOTE ON FULLY-CLOSED DELIVERY: if the app is force-quit, iOS won't run our
//  polling, so a friend's change can only reach the device as a REMOTE push from
//  the Cloudflare Worker via APNs (token plumbing already in PushNotifications).
//  Local notifications de-dupe against remote pushes by id.
//

import SwiftUI
import UserNotifications
import Observation

// MARK: - Model

/// One item in the in-app notification inbox.
struct SeshNotification: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case status        // a friend changed their activity/status
        case invite        // a friend invited you to a sesh / cypher
        case chat          // a friend sent you a message
        case milestone     // a friend hit a record / milestone
    }
    var id: String
    var kind: Kind
    var title: String
    var body: String
    var at: Date
    var read: Bool = false
    /// Optional SF Symbol override; otherwise derived from kind.
    var iconName: String?

    var icon: String {
        if let iconName { return iconName }
        switch kind {
        case .status:    return "dot.radiowaves.left.and.right"
        case .invite:    return "person.crop.circle.badge.plus"
        case .chat:      return "bubble.left.and.bubble.right.fill"
        case .milestone: return "rosette"
        }
    }
}

// MARK: - Manager

@Observable
@MainActor
final class NotificationManager {
    /// The persistent inbox, newest first.
    private(set) var inbox: [SeshNotification] = []

    /// The banner currently shown in-app (nil = none). Driven by NotificationBanner.
    var activeBanner: SeshNotification?

    /// Whether friend-status notifications are enabled (user setting).
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: DefaultsKey.notifEnabled) }
    }

    /// Current scene phase, set by the app so we know foreground vs background.
    var scenePhaseActive = true

    /// Event ids we've already notified on, so re-polling the same feed doesn't
    /// re-fire. Bounded to a recent window to avoid unbounded growth.
    private var seenIDs: Set<String> = []

    // MARK: Anti-spam tuning

    /// After a friend's status change is *surfaced* (banner/lock screen), further
    /// status changes from that same friend are inbox-only until this elapses.
    private let perFriendCooldown: TimeInterval = 150     // 2.5 min
    /// Max status alerts *surfaced* per rolling window across all friends.
    private let globalWindow: TimeInterval = 60           // 1 min
    private let globalMaxPerWindow = 4

    /// handle -> last time we surfaced a status alert for them.
    private var lastSurfacedForFriend: [String: Date] = [:]
    /// Timestamps of recently surfaced status alerts (for the global rate limit).
    private var recentSurfacedAt: [Date] = []

    var unreadCount: Int { inbox.count(where: { !$0.read }) }

    init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: DefaultsKey.notifEnabled) as? Bool) ?? true
        if let data = d.data(forKey: DefaultsKey.notifInbox),
           let saved = try? JSONDecoder().decode([SeshNotification].self, from: data) {
            inbox = saved
        }
        if let ids = d.array(forKey: DefaultsKey.notifSeenIDs) as? [String] {
            seenIDs = Set(ids)
        }
    }

    // MARK: Ingest

    /// Compare a freshly-polled feed against what we've already seen and notify
    /// for any new events that aren't the current user's own. Call from
    /// SocialStore right after a snapshot is applied.
    func ingestFeed(_ events: [ActivityEvent], myHandle: String) {
        guard enabled else {
            // Still record ids so toggling on later doesn't replay history.
            for e in events { seenIDs.insert(e.id) }
            persistSeen()
            return
        }
        // Oldest -> newest so the inbox ends up newest-first after inserts.
        let fresh = events.sorted(by: { $0.at < $1.at }).filter { !seenIDs.contains($0.id) }
        for event in fresh {
            seenIDs.insert(event.id)
            guard event.userHandle != myHandle else { continue }   // not my own
            let note = SeshNotification(
                id: event.id, kind: .status,
                title: event.userName,
                body: event.activity.phrase.replacingOccurrences(of: "is ", with: "").capitalized
                    + (event.detail.map { " · \($0)" } ?? ""),
                at: event.at)
            // Throttle decides whether this is surfaced or inbox-only.
            deliverStatus(note, friendHandle: event.userHandle)
        }
        trimSeen()
        persistSeen()
    }

    /// Record + deliver a one-off notification (invite, chat, milestone). These
    /// are not subject to the status throttle.
    func notify(kind: SeshNotification.Kind, title: String, body: String,
                id: String = UUID().uuidString, icon: String? = nil) {
        guard enabled || kind != .status else { return }
        // De-dupe by id (covers chat re-detection across polls).
        guard !seenIDs.contains(id) else { return }
        seenIDs.insert(id); persistSeen()
        let note = SeshNotification(id: id, kind: kind, title: title, body: body,
                                    at: Date(), iconName: icon)
        addToInbox(note)
        surface(note)
    }

    // MARK: Delivery

    /// Status delivery with anti-spam. Always records to the inbox; only surfaces
    /// (banner/lock screen) if it passes the per-friend cooldown and global rate
    /// limit.
    private func deliverStatus(_ note: SeshNotification, friendHandle: String) {
        addToInbox(note)

        let now = Date()
        // Per-friend cooldown.
        if let last = lastSurfacedForFriend[friendHandle], now.timeIntervalSince(last) < perFriendCooldown {
            return  // inbox-only
        }
        // Global rate limit (rolling window).
        recentSurfacedAt.removeAll { now.timeIntervalSince($0) > globalWindow }
        if recentSurfacedAt.count >= globalMaxPerWindow {
            return  // inbox-only
        }

        lastSurfacedForFriend[friendHandle] = now
        recentSurfacedAt.append(now)
        surface(note)
    }

    private func addToInbox(_ note: SeshNotification) {
        inbox.insert(note, at: 0)
        if inbox.count > 200 { inbox.removeLast(inbox.count - 200) }
        persistInbox()
    }

    /// Route a notification to a visible surface based on scene phase.
    private func surface(_ note: SeshNotification) {
        if scenePhaseActive {
            activeBanner = note          // banner shows only the newest
        } else {
            scheduleLocal(note)          // lock screen / system banner
        }
    }

    /// Schedule a local notification that surfaces on the lock screen / banner
    /// while the app is backgrounded.
    private func scheduleLocal(_ note: SeshNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        content.threadIdentifier = note.kind.rawValue
        // Use the event id so a remote push with the same id won't duplicate it.
        let request = UNNotificationRequest(identifier: note.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Inbox management

    func markAllRead() {
        guard inbox.contains(where: { !$0.read }) else { return }
        inbox = inbox.map { var n = $0; n.read = true; return n }
        persistInbox()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func clearInbox() {
        inbox.removeAll()
        persistInbox()
    }

    func dismissBanner() { activeBanner = nil }

    // MARK: Persistence

    private func persistInbox() {
        if let data = try? JSONEncoder().encode(inbox) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.notifInbox)
        }
    }
    private func persistSeen() {
        UserDefaults.standard.set(Array(seenIDs), forKey: DefaultsKey.notifSeenIDs)
    }
    /// Keep the seen-id set from growing without bound (cap ~500 ids).
    private func trimSeen() {
        guard seenIDs.count > 500 else { return }
        let keep = Set(inbox.map(\.id))
        seenIDs = seenIDs.intersection(keep).union(Array(seenIDs).suffix(200))
    }
}
