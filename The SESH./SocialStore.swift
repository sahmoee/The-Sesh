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

/// (#2) Explicitly MainActor-isolated: this store mutates @Observable UI state
/// from many async Tasks (polling, chat sends, push registration, realtime
/// events). Under Swift 6 strict concurrency every mutation is now checked to
/// happen on the main actor instead of relying on call-site discipline.
@Observable
@MainActor
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

    /// (#App14/#C6) Rich connectivity state for the UI, derived from the shared
    /// path monitor + server reachability + sync activity.
    var connectivity: ConnectivityState { ConnectivityMonitor.shared.state }

    /// (#C8) Revision of the last applied snapshot (the Worker's ETag).
    private var snapshotETag: String?

    /// Set by the app at launch so polled friend events become notifications.
    weak var notifications: NotificationManager?

    private let api = SeshAPI()
    private var pollTask: Task<Void, Never>?
    private var openRoomID: String?     // room whose chat we're actively polling

    /// (#C3) Push-driven realtime channel. While connected, the server tells us
    /// when social state changes and we pull one snapshot — the poll loop drops
    /// to a slow safety-net cadence instead of hammering every 12 seconds.
    private let realtime = SeshRealtime()

    /// (#C5) Durable offline queue for writes.
    private let outbox = OfflineOutbox.shared

    /// The identity sent to the Worker on every call.
    private var identity: SeshIdentity {
        SeshIdentity(userID: me.id, handle: me.handle, name: me.displayName, code: friendCode)
    }

    /// Public read-only view of the current identity, for sibling stores
    /// (e.g. the scrobbler / Spotify auth) that call the same Worker.
    var identitySnapshot: SeshIdentity { identity }

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

    /// Initial load: authenticate, try the Worker, start realtime + fallback
    /// polling, and replay any writes queued while offline.
    func bootstrap() async {
        // (#15) Show the last persisted server state instantly (cold offline
        // launches get real content, not empty screens).
        if friends.isEmpty, let cached = SocialCache.loadSnapshot() {
            apply(cached, notify: false)
            snapshotETag = SocialCache.snapshotETag()
        }
        // (#C6) Refresh + replay the moment the network path comes back.
        ConnectivityMonitor.shared.onReconnect = { [weak self] in
            guard let self else { return }
            self.outbox.scheduleReplay(api: self.api)
            Task { await self.refresh() }
        }
        await ensureSession()
        await refresh()
        realtime.onChange = { [weak self] in
            Task { await self?.refresh() }
        }
        realtime.onStateChange = { [weak self] state in
            guard let self else { return }
            if state == .connected {
                // Reconnected: replay queued writes, then converge.
                self.outbox.scheduleReplay(api: self.api)
                Task { await self.refresh() }
            }
        }
        realtime.connect()
        startPolling(every: 60)   // slow safety net behind the socket (#C3)
        outbox.scheduleReplay(api: api)
    }

    /// (#C1) Make sure we hold a session token. Apple users get their session
    /// in AuthManager.handle() (which has the identity token); this covers the
    /// guest path and app relaunches.
    func ensureSession() async {
        guard SeshAuth.shared.token == nil else { return }
        if me.id.hasPrefix("dev_") {
            await SeshAuth.shared.exchangeGuest(deviceID: me.id, handle: me.handle,
                                                name: me.displayName, code: friendCode)
        }
    }

    /// Sign-out teardown (#C9): unregister this device's push token so the
    /// backend stops pushing to a signed-out device, drop the session, and
    /// close the realtime channel.
    func signOut() async {
        if let tok = pushToken {
            _ = await api.post("/api/push/unregister", body: SeshAPI.TokenBody(token: tok))
        }
        teardown()
        SeshAuth.shared.signOut()
    }

    /// (#8) Central ownership of every long-lived task this store spawns.
    /// Cancels polling, the realtime socket, the post-sesh status fade, and
    /// any in-flight outbox replay. Called on sign-out; also safe to call
    /// when the social layer should go fully quiet (e.g. background audits).
    func teardown() {
        stopPolling()
        vibingFadeTask?.cancel(); vibingFadeTask = nil
        realtime.disconnect()
        outbox.cancelReplay()
    }

    func refresh() async {
        loading = true
        ConnectivityMonitor.shared.isSyncing = true
        defer { loading = false; ConnectivityMonitor.shared.isSyncing = false }

        switch await api.fetchSnapshot(identity: identity, etag: snapshotETag) {
        case .fresh(let snapshot, let etag):
            online = true
            ConnectivityMonitor.shared.serverReachable = true
            snapshotETag = etag
            apply(snapshot)
            SocialCache.saveSnapshot(snapshot, etag: etag)   // (#15)
            if let room = openRoomID, let msgs = await api.fetchMessages(roomID: room, identity: identity) {
                messagesByRoom[room] = msgs
                SocialCache.saveMessages(msgs, roomID: room)
            }
        case .notModified:                                    // (#C8)
            online = true
            ConnectivityMonitor.shared.serverReachable = true
        case .failure:
            online = false
            ConnectivityMonitor.shared.serverReachable = false
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
                // (#C6) Don't hammer the radio while offline — the reconnect
                // hook refreshes immediately when the path returns.
                guard ConnectivityMonitor.shared.pathSatisfied else { continue }
                await self.api.heartbeat(identity: self.identity)
                await self.refresh()
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    private func apply(_ s: SeshSnapshot, notify: Bool = true) {
        // Capture prior unread-per-room to detect new incoming chat messages.
        let priorUnread = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.unread) })

        friends = s.friends
        cyphers = s.cyphers
        rooms = s.rooms
        liveStreams = s.live
        feed = s.feed

        // Turn newly-arrived friend events into notifications. The manager applies
        // its own anti-spam throttle so rapid status flips don't flood the user.
        let events = s.feed
        let myHandle = me.handle
        let openRoom = openRoomID
        var chatNotes: [(title: String, body: String, id: String)] = []
        for room in s.rooms {
            let before = priorUnread[room.id] ?? 0
            if room.unread > before, room.id != openRoom {
                chatNotes.append((title: room.name,
                                  body: room.lastMessage ?? "New message",
                                  id: "chat-\(room.id)-\(room.lastMessageAt?.timeIntervalSince1970 ?? 0)"))
            }
        }

        if let notifications, notify {
            Task { @MainActor in
                notifications.ingestFeed(events, myHandle: myHandle)
                for n in chatNotes {
                    notifications.notify(kind: .chat, title: n.title, body: n.body, id: n.id)
                }
            }
        }
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
        // Keep the user-facing status roughly in sync when the activity is driven
        // by sesh events (start/stage/end), so existing call sites move the status
        // machine without each needing to know about SeshStatus.
        syncStatus(from: activity)
        // Only broadcast (and drop a feed event) when the status actually changed,
        // so rapid re-sets of the same status don't spam friends with duplicates.
        guard changed else { return }
        lastPostedActivity = activity
        lastPostedDetail = detail
        let event = ActivityEvent(id: UUID().uuidString, userHandle: me.handle,
                                  userName: me.displayName, activity: activity,
                                  detail: detail, at: Date())
        feed.insert(event, at: 0)
        // (#App16) Privacy gates: nothing leaves the device unless shared.
        let privacy = PrivacySettings.shared
        guard privacy.shareActivity else { return }
        let sharedDetail = privacy.shareStrainDetails ? (detail ?? "") : ""
        // (#C5) Presence/status writes queue offline and replay idempotently.
        if let body = try? SeshAPI.encoder.encode(
            SeshAPI.ActivityBody(activity: activity.rawValue, detail: sharedDetail)) {
            outbox.enqueue(path: "/api/activity", body: body)
            outbox.scheduleReplay(api: api)
        }
    }

    /// Last status/detail we actually broadcast, used to suppress duplicate posts.
    private var lastPostedActivity: SeshActivity?
    private var lastPostedDetail: String?

    // MARK: - User status (automatic state machine + manual override)

    /// The user's own displayed status. Defaults to away; the app moves it to
    /// ready on open, through rollingUp/smoking during a sesh, then vibing and
    /// back to away after a sesh ends.
    var myStatus: SeshStatus = .away
    private var vibingFadeTask: Task<Void, Never>?

    /// Map a sesh-driven activity onto myStatus. Only the sesh states drive the
    /// status here; idle is left to the explicit vibing/away transitions so we
    /// don't clobber the post-sesh "vibing" with an "away" the moment activity
    /// clears.
    private func syncStatus(from activity: SeshActivity) {
        switch activity {
        case .rollingUp, .lighting, .packingBowl:
            myStatus = .rollingUp
        case .smoking, .hittingBong:
            myStatus = .smoking
        default:
            break
        }
    }

    /// Manually set the status (from the dropdown). Cancels any pending fade.
    func setStatus(_ status: SeshStatus, detail: String? = nil) {
        vibingFadeTask?.cancel(); vibingFadeTask = nil
        applyStatus(status, detail: detail)
    }

    /// Apply a status and mirror it to the broadcast activity.
    private func applyStatus(_ status: SeshStatus, detail: String? = nil) {
        myStatus = status
        setMyActivity(status.activity, detail: detail)
    }

    /// Called on app open: become "ready" only if currently away and not seshing.
    /// Auto-transitions always win, so an active sesh status is left untouched.
    func enterReadyIfAway() {
        guard myStatus == .away else { return }
        applyStatus(.ready)
    }

    /// Called when a sesh ends: go to vibing, then fade to away after a while.
    func enterVibingThenAway(after seconds: UInt64 = 1800) {
        vibingFadeTask?.cancel()
        applyStatus(.vibing)
        vibingFadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double(seconds)))
            guard !Task.isCancelled, let store = self else { return }
            // Only fade if still vibing (a new sesh or manual change cancels this).
            if store.myStatus == .vibing { store.applyStatus(.away) }
        }
    }

    /// Invite friends (by display name) to a sesh. Resolves names to handles and
    /// tells the Worker, which pushes each invited friend.
    func inviteFriends(named names: [String], detail: String? = nil) {
        let handles = friends
            .filter { names.contains($0.displayName) }
            .map(\.handle)
        guard !handles.isEmpty else { return }
        Task { await api.postInvite(handles: handles, detail: detail, identity: identity) }
    }

    /// Update the current user's now-playing track and broadcast it to friends.
    /// De-dupes: only posts when the track actually changed, so re-reads of the
    /// same song don't spam the Worker.
    func setNowPlaying(_ np: NowPlaying) {
        if me.nowPlaying?.title == np.title && me.nowPlaying?.artist == np.artist
            && me.nowPlaying?.source == np.source { me.nowPlaying = np; return }
        me.nowPlaying = np
        // (#App16) Now-playing stays local unless music sharing is on.
        guard PrivacySettings.shared.shareMusic else { return }
        Task { await api.postNowPlaying(np, identity: identity) }
    }

    /// Clear the current user's now-playing (stopped / source disabled).
    func clearNowPlaying() {
        guard me.nowPlaying != nil else { return }
        me.nowPlaying = nil
        Task { await api.clearNowPlaying(identity: identity) }
    }

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
        // (#15) Cached page first so the room isn't blank offline.
        if messagesByRoom[roomID] == nil, let cached = SocialCache.loadMessages(roomID: roomID) {
            messagesByRoom[roomID] = cached
        }
        Task {
            if let msgs = await api.fetchMessages(roomID: roomID, identity: identity) {
                messagesByRoom[roomID] = msgs
                SocialCache.saveMessages(msgs, roomID: roomID)
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
        // (#C5) Through the outbox: delivered now if online, queued + replayed
        // with the message id as idempotency key if not. No more silently
        // vanished messages.
        if let body = try? SeshAPI.encoder.encode(SeshAPI.MessageBody(id: msg.id, text: trimmed)) {
            outbox.enqueue(path: "/api/rooms/\(roomID)/messages", body: body, key: msg.id)
            outbox.scheduleReplay(api: api)
        }
        Task {
            // Converge with the server (and pick up others' messages).
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
