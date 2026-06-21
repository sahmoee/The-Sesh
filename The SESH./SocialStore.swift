//
//  SocialStore.swift
//  SESH
//
//  The social engine. Talks to the SESH Worker for friends' presence, Cyphers,
//  chat, and live streams, and falls back to a rich seeded local state so the
//  app is fully usable offline and on first launch. The networking layer is
//  isolated behind SeshAPI so a real backend can grow without touching the UI.
//

import SwiftUI

@Observable
final class SocialStore {
    // Current user. Starts as a local placeholder and is replaced by the
    // signed-in identity via configure(...) at app launch.
    var me = SeshUser(id: "me", handle: "@you", displayName: "You",
                      activity: .idle, lastSeen: Date(), streak: 0, isFriend: false)

    var friends: [SeshUser] = []
    var cyphers: [Cypher] = []
    var rooms: [ChatRoom] = []
    var liveStreams: [LiveStream] = []
    var feed: [ActivityEvent] = []

    /// Messages keyed by room id.
    private var messagesByRoom: [String: [ChatMessage]] = [:]

    /// Cypher the user is currently in (local view of membership).
    var activeCypherID: String?
    /// True while the user is broadcasting.
    var isBroadcasting = false

    var online = false           // did the Worker respond?
    var loading = false

    private let api = SeshAPI()
    private var pollTask: Task<Void, Never>?
    private var openRoomID: String?     // room whose chat we're actively polling

    /// The identity sent to the Worker on every call.
    private var identity: SeshIdentity {
        SeshIdentity(userID: me.id, handle: me.handle, name: me.displayName, code: friendCode)
    }

    /// A short, shareable friend code derived from the user's stable id.
    /// e.g. "SESH-7K9F". Must be deterministic across launches, so it uses a
    /// fixed hash of the id STRING — Swift's Hashable.hashValue is seeded per
    /// process and would change every launch (breaking the code).
    var friendCode: String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no ambiguous chars
        // FNV-1a over the id's UTF-8 bytes — stable forever for a given id.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in me.id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        var n = hash
        var code = ""
        for _ in 0..<4 { code.append(alphabet[Int(n % UInt64(alphabet.count))]); n /= UInt64(alphabet.count) }
        return "SESH-" + code
    }

    /// Add a friend by their code. Returns a status message for the UI.
    func addFriend(code raw: String) async -> String {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return "Enter a friend code." }
        if code == friendCode { return "That's your own code!" }
        let ok = await api.addFriend(code: code, identity: identity)
        if ok {
            await refresh()
            return "Friend added!"
        }
        return "Couldn't find anyone with that code."
    }

    // MARK: Block / report

    /// Users this person has blocked (also hidden server-side; tracked locally
    /// so the UI updates instantly).
    private(set) var blockedIDs: Set<String> = []

    func block(_ user: SeshUser) async {
        blockedIDs.insert(user.id)
        friends.removeAll { $0.id == user.id }
        feed.removeAll { $0.userHandle == user.handle }
        _ = await api.block(userID: user.id, identity: identity)
        await refresh()
    }

    /// Remove a friend from the local list. (There's no dedicated unfriend
    /// endpoint on the Worker yet, so this is a local removal; to permanently
    /// stop seeing someone, use Block from their profile.)
    func removeFriend(_ user: SeshUser) {
        friends.removeAll { $0.id == user.id }
    }

    func unblock(userID: String) async {
        blockedIDs.remove(userID)
        _ = await api.unblock(userID: userID, identity: identity)
        await refresh()
    }

    func report(user: SeshUser?, messageID: String?, reason: String) async -> Bool {
        await api.report(userID: user?.id, messageID: messageID, reason: reason, identity: identity)
    }

    // MARK: Pagination

    /// Whether a room appears to have older messages to load.
    var hasMoreByRoom: [String: Bool] = [:]

    /// Load an older page of messages for a room (prepends to the local list).
    func loadOlderMessages(in roomID: String) async {
        let current = messagesByRoom[roomID] ?? []
        let oldest = current.map(\.sentAt).min()
        guard let page = await api.fetchMessages(roomID: roomID, before: oldest, limit: 50, identity: identity),
              !page.isEmpty else {
            hasMoreByRoom[roomID] = false
            return
        }
        // Merge, de-dupe by id, keep chronological.
        var merged = page + current
        var seen = Set<String>()
        merged = merged.filter { seen.insert($0.id).inserted }
        merged.sort { $0.sentAt < $1.sentAt }
        messagesByRoom[roomID] = merged
        hasMoreByRoom[roomID] = page.count >= 50
    }

    // MARK: Identity

    /// Wire the signed-in user into the social layer. Call at app launch with
    /// the Apple user id (or a stable fallback) and the display name. A handle
    /// is derived from the name. Safe to call repeatedly.
    func configure(userID: String?, displayName: String) {
        let id = userID ?? Self.deviceFallbackID()
        let name = displayName.isEmpty ? "You" : displayName
        let handle = Self.handle(from: name)
        // Only react if something actually changed.
        guard me.id != id || me.displayName != name || me.handle != handle else { return }
        me = SeshUser(id: id, handle: handle, displayName: name,
                      activity: me.activity, lastSeen: Date(), streak: me.streak, isFriend: false)
        // If we already have a device push token, re-register it under the
        // (now correct) identity so the backend stores it on the right user.
        if let tok = pushToken {
            Task { await api.registerPush(token: tok, identity: identity) }
        }
    }

    // MARK: Push notifications

    /// The latest APNs device token (hex), captured by the AppDelegate.
    private(set) var pushToken: String?

    /// Called when iOS hands us a fresh APNs token. Stores it and registers it
    /// with the backend so friends' "went live" events can reach this device.
    func registerPushToken(_ token: String) {
        pushToken = token
        Task { await api.registerPush(token: token, identity: identity) }
    }

    private static func handle(from name: String) -> String {
        let base = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return "@" + (base.isEmpty ? "you" : String(base.prefix(20)))
    }

    /// Stable per-install id when the user hasn't signed in with Apple.
    private static func deviceFallbackID() -> String {
        let key = "sesh.device.userID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = "dev_" + UUID().uuidString.prefix(12)
        UserDefaults.standard.set(String(fresh), forKey: key)
        return String(fresh)
    }

    // MARK: Lifecycle

    /// Initial load: try the Worker, fall back to seeded data, then start polling.
    func bootstrap() async {
        await refresh()
        startPolling()
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        if let snapshot = await api.fetchSnapshot(identity: identity) {
            online = true
            apply(snapshot)
            // Refresh the open room's messages too.
            if let room = openRoomID, let msgs = await api.fetchMessages(roomID: room, identity: identity) {
                messagesByRoom[room] = msgs
            }
        } else {
            online = false
            if friends.isEmpty { seedLocal() }
        }
    }

    /// Poll the Worker on a short timer so others' presence, cyphers, live, and
    /// chat appear in near-real-time, and send a heartbeat to keep us "active".
    func startPolling(every seconds: UInt64 = 12) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(seconds)))
                guard let self else { return }
                if Task.isCancelled { return }
                await self.api.heartbeat(identity: self.identity)
                await self.refresh()
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    private func apply(_ s: SeshSnapshot) {
        friends = s.friends
        cyphers = s.cyphers
        rooms = s.rooms
        liveStreams = s.live
        feed = s.feed
    }

    // MARK: Activity / presence

    /// When the current activity started — drives the "for X minutes" status timer.
    private(set) var activityStartedAt: Date = Date()

    /// Broadcast my own activity (e.g. when I log a sesh or tap a quick action).
    func setMyActivity(_ activity: SeshActivity, detail: String? = nil) {
        let changed = (me.activity != activity) || (lastPostedDetail != detail)
        if me.activity != activity { activityStartedAt = Date() }
        me.activity = activity
        me.lastSeen = Date()
        // Only broadcast (and drop a feed event) when the status actually changed,
        // so rapid re-sets of the same status don't spam friends with duplicates.
        guard changed else { return }
        lastPostedActivity = activity
        lastPostedDetail = detail
        let event = ActivityEvent(id: UUID().uuidString, userHandle: me.handle,
                                  userName: me.displayName, activity: activity,
                                  detail: detail, at: Date())
        feed.insert(event, at: 0)
        Task { await api.postActivity(activity, detail: detail, identity: identity) }
    }

    /// Last status/detail we actually broadcast, used to suppress duplicate posts.
    private var lastPostedActivity: SeshActivity?
    private var lastPostedDetail: String?

    /// Broadcast a milestone (new roll record, etc.) so friends get a push.
    /// Also drops a local feed event so it shows in the activity list.
    func broadcastMilestone(kind: String, detail: String? = nil) {
        let event = ActivityEvent(id: UUID().uuidString, userHandle: me.handle,
                                  userName: me.displayName, activity: me.activity,
                                  detail: detail, at: Date())
        feed.insert(event, at: 0)
        Task { await api.postMilestone(kind: kind, detail: detail, identity: identity) }
    }

    /// Friends currently doing something (for the presence row).
    var activeFriends: [SeshUser] {
        friends.filter { $0.activity.isActive }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    func friend(byHandle handle: String) -> SeshUser? {
        friends.first { $0.handle == handle }
    }

    // MARK: Cyphers

    func hostCypher(title: String, strainName: String?, visibility: CypherVisibility, live: Bool) -> Cypher {
        let c = Cypher(id: "cy_\(UUID().uuidString.prefix(8))",
                       title: title.isEmpty ? "\(me.displayName)'s Cypher" : title,
                       hostHandle: me.handle, hostName: me.displayName,
                       strainName: strainName,
                       participantIDs: [me.id],
                       maxParticipants: 8,
                       isLive: live,
                       visibility: visibility,
                       startedAt: Date(),
                       note: nil)
        cyphers.insert(c, at: 0)
        activeCypherID = c.id
        isBroadcasting = live
        setMyActivity(live ? .live : .inCypher, detail: c.title)
        // Journey counters (hosting also counts as joining).
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "ht.cyph.hosted.v1") + 1, forKey: "ht.cyph.hosted.v1")
        d.set(d.integer(forKey: "ht.cyph.joined.v1") + 1, forKey: "ht.cyph.joined.v1")
        Task { await api.createCypher(c, identity: identity) }
        return c
    }

    func joinCypher(_ cypher: Cypher) {
        guard let i = cyphers.firstIndex(where: { $0.id == cypher.id }) else { return }
        let alreadyIn = cyphers[i].participantIDs.contains(me.id)
        if !alreadyIn {
            cyphers[i].participantIDs.append(me.id)
            // Count a join only the first time I enter this cypher.
            let d = UserDefaults.standard
            d.set(d.integer(forKey: "ht.cyph.joined.v1") + 1, forKey: "ht.cyph.joined.v1")
        }
        activeCypherID = cypher.id
        setMyActivity(.inCypher, detail: cypher.title)
        Task { await api.joinCypher(cypher.id, identity: identity) }
    }

    func leaveCypher(_ cypherID: String) {
        if let i = cyphers.firstIndex(where: { $0.id == cypherID }) {
            cyphers[i].participantIDs.removeAll { $0 == me.id }
        }
        if activeCypherID == cypherID { activeCypherID = nil }
        isBroadcasting = false
        setMyActivity(.idle)
        Task { await api.leaveCypher(cypherID, identity: identity) }
    }

    func participants(of cypher: Cypher) -> [SeshUser] {
        cypher.participantIDs.compactMap { id in
            if id == me.id { return me }
            return friends.first { $0.id == id }
        }
    }

    // MARK: Live

    func goLive(title: String, strainName: String?) -> LiveStream {
        let stream = LiveStream(id: "lv_\(UUID().uuidString.prefix(8))",
                                hostHandle: me.handle, hostName: me.displayName,
                                title: title.isEmpty ? "\(me.displayName) live" : title,
                                viewerCount: 0, strainName: strainName,
                                startedAt: Date(), cypherID: activeCypherID)
        liveStreams.insert(stream, at: 0)
        isBroadcasting = true
        setMyActivity(.live, detail: title)
        Task { await api.startLive(stream, identity: identity) }
        return stream
    }

    func endLive(_ id: String) {
        liveStreams.removeAll { $0.id == id }
        isBroadcasting = false
        setMyActivity(.idle)
        Task { await api.endLive(id, identity: identity) }
    }

    // MARK: Chat

    func messages(in roomID: String) -> [ChatMessage] {
        messagesByRoom[roomID] ?? []
    }

    /// Open a room: fetch its history now and mark it for live polling.
    func openRoom(_ roomID: String) {
        openRoomID = roomID
        markRoomRead(roomID)
        Task {
            if let msgs = await api.fetchMessages(roomID: roomID, identity: identity) {
                messagesByRoom[roomID] = msgs
            }
        }
    }

    /// Stop live-polling a room's chat when its view goes away.
    func closeRoom(_ roomID: String) {
        if openRoomID == roomID { openRoomID = nil }
    }

    func send(_ text: String, to roomID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = ChatMessage(id: UUID().uuidString, roomID: roomID,
                              senderHandle: me.handle, senderName: me.displayName,
                              text: trimmed, sentAt: Date(), isMe: true)
        messagesByRoom[roomID, default: []].append(msg)
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].lastMessage = trimmed
            rooms[i].lastMessageAt = Date()
        }
        Task {
            await api.sendMessage(msg, identity: identity)
            // Re-sync so we converge with the server (and pick up others' msgs).
            if let msgs = await api.fetchMessages(roomID: roomID, identity: identity) {
                messagesByRoom[roomID] = msgs
            }
        }
    }

    func markRoomRead(_ roomID: String) {
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].unread = 0
        }
    }

    // MARK: Seeded local fallback

    /// Offline fallback. The app ships with NO fake friends or content — when
    /// there's no backend connection we simply show empty states until real data
    /// arrives from the Worker (or the user adds friends / hosts a Cypher).
    private func seedLocal() {
        friends = []
        cyphers = []
        liveStreams = []
        rooms = []
        messagesByRoom = [:]
        feed = []
    }
}
