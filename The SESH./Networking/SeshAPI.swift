//
//  SeshAPI.swift
//  The SESH
//
//  Networking layer to the SESH Worker. Every call carries the signed-in
//  user's identity (id / handle / name) so the backend attributes presence,
//  cyphers, live, and chat to the real person. Calls fail soft: reads return
//  nil and writes no-op on error, so the app keeps working offline on seed.
//

import Foundation
import os

/// One-shot snapshot of the social world from the Worker.
struct SeshSnapshot: Codable {
    var friends: [SeshUser]
    var cyphers: [Cypher]
    var rooms: [ChatRoom]
    var live: [LiveStream]
    var feed: [ActivityEvent]
}

/// Result of a Spotify playlist export (from the Worker).
struct SpotifyExportResponse: Codable {
    var added: Int          // how many tracks were matched + added
    var total: Int          // how many were requested
    var url: String?        // open.spotify.com playlist URL
}

/// The caller's identity, sent with every request.
struct SeshIdentity {
    var userID: String
    var handle: String
    var name: String
    var code: String = ""
}

/// Typed networking failures so the UI can show meaningful messages instead of
/// silently no-op'ing.
enum APIError: Error {
    case network          // no connection / request threw
    case rateLimited      // HTTP 429 — too many requests
    case notFound         // HTTP 404
    case server(Int)      // other non-2xx
    case invalidRequest   // couldn't build the request

    var userMessage: String {
        switch self {
        case .network:       return "No connection. Check your internet and try again."
        case .rateLimited:   return "Slow down a sec — too many requests. Try again shortly."
        case .notFound:      return "Couldn't find that."
        case .server:        return "Something went wrong on our end. Try again."
        case .invalidRequest: return "Couldn't send that request."
        }
    }
}

/// (#C1) Every request now carries `Authorization: Bearer <session>` from
/// SeshAuth; the Worker rejects unauthenticated calls, so the old x-sesh-*
/// identity headers are gone. (#C5) Writes accept an idempotency key so the
/// offline outbox can replay them safely. MainActor-isolated because it reads
/// SeshAuth's token and is only ever called from MainActor stores.
@MainActor
struct SeshAPI {
    /// One shared session for the whole app. Creating a URLSession per request
    /// (as before) prevents connection reuse/keep-alive and reallocates the
    /// config each call. A single configured session is reused everywhere.
    private static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    private var session: URLSession { Self.sharedSession }

    /// Cached ISO-8601 formatters. The Worker emits `Date().toISOString()`,
    /// which carries fractional seconds — Foundation's plain `.iso8601`
    /// strategy rejects those, so try fractional first, then second-precision.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// Shared decoder (fraction-tolerant ISO-8601 dates) so each call doesn't
    /// allocate one.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = isoFractional.date(from: s) ?? isoPlain.date(from: s) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "Unparseable ISO-8601 date: \(s)"))
        }
        return d
    }()

    private func makeRequest(_ path: String, method: String = "GET",
                             identity: SeshIdentity?, body: Data? = nil,
                             idempotencyKey: String? = nil) -> URLRequest? {
        guard let url = SeshUnifiedWorker.url(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // (#C1) Verified session token — the Worker derives identity from this,
        // never from client-supplied fields.
        if let token = SeshAuth.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey {
            req.setValue(idempotencyKey, forHTTPHeaderField: "X-Idempotency-Key")
        }
        // (#17) Per-request id, echoed by the Worker's logs for end-to-end traces.
        req.setValue(Diag.requestID(), forHTTPHeaderField: "X-Request-ID")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// (#C1) On a 401, silently refresh the session once and retry.
    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        if http?.statusCode == 401, await SeshAuth.shared.refreshIfNeeded(),
           let token = SeshAuth.shared.token {
            var retry = req
            retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data2, resp2) = try await session.data(for: retry)
            return (data2, (resp2 as? HTTPURLResponse) ?? HTTPURLResponse())
        }
        return (data, http ?? HTTPURLResponse())
    }

    /// (#C7) Retry wrapper for SAFE (idempotent, read-only) requests: up to
    /// `attempts` tries with exponential backoff + jitter. Respects
    /// cancellation, skips retries while the device is offline, and honors
    /// Retry-After on 429/503.
    private func sendWithRetry(_ req: URLRequest, attempts: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var backoff: Double = 0.5
        var lastError: Error = APIError.network
        for attempt in 0..<attempts {
            if Task.isCancelled { break }
            if attempt > 0 && !ConnectivityMonitor.shared.pathSatisfied { break }
            do {
                let (data, resp) = try await send(req)
                if resp.statusCode == 429 || resp.statusCode == 503 {
                    let retryAfter = Double(resp.value(forHTTPHeaderField: "Retry-After") ?? "")
                    let delay = retryAfter ?? (backoff + Double.random(in: 0...0.3))
                    Diag.network.info("retrying \(req.url?.path ?? "?", privacy: .public) after \(delay, privacy: .public)s (\(resp.statusCode))")
                    try await Task.sleep(for: .seconds(delay))
                    backoff = min(backoff * 2, 8)
                    continue
                }
                return (data, resp)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .seconds(backoff + Double.random(in: 0...0.3)))
                    backoff = min(backoff * 2, 8)
                }
            }
        }
        throw lastError
    }

    // MARK: Reads

    /// (#C8) Delta-aware snapshot fetch. Sends If-None-Match with the last seen
    /// revision; the Worker answers 304 with no body when nothing changed.
    enum SnapshotResult {
        case fresh(SeshSnapshot, etag: String?)
        case notModified
        case failure
    }

    func fetchSnapshot(identity: SeshIdentity?, etag: String? = nil) async -> SnapshotResult {
        guard var req = makeRequest("/api/snapshot", identity: identity) else { return .failure }
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, resp) = try await sendWithRetry(req)
            switch resp.statusCode {
            case 304:
                return .notModified
            case 200:
                let snapshot = try Self.decoder.decode(SeshSnapshot.self, from: data)
                return .fresh(snapshot, etag: resp.value(forHTTPHeaderField: "ETag"))
            default:
                Diag.network.warning("snapshot failed: \(resp.statusCode)")
                return .failure
            }
        } catch {
            return .failure
        }
    }

    func fetchMessages(roomID: String, identity: SeshIdentity?) async -> [ChatMessage]? {
        guard let req = makeRequest("/api/rooms/\(roomID)/messages", identity: identity) else { return nil }
        do {
            let (data, resp) = try await sendWithRetry(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode([ChatMessage].self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: Writes (fire-and-forget)

    @discardableResult
    private func post(_ path: String, identity: SeshIdentity?, _ payload: [String: Any]) async -> Bool {
        if case .success = await postResult(path, identity: identity, payload) { return true }
        return false
    }

    /// (#6) Typed variant — Encodable request bodies instead of [String: Any].
    /// New call sites should prefer this; the untyped overloads remain only for
    /// endpoints not yet migrated.
    @discardableResult
    func post<Body: Encodable>(_ path: String, body: Body,
                               idempotencyKey: String? = nil) async -> Result<Void, APIError> {
        guard let data = try? Self.encoder.encode(body) else { return .failure(.invalidRequest) }
        return await postRaw(path, body: data, idempotencyKey: idempotencyKey)
    }

    /// Shared encoder (ISO-8601 dates) for typed request bodies (#6).
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// POST returning a typed result so callers can distinguish a network failure
    /// from a rate-limit (HTTP 429) and surface the right message.
    @discardableResult
    func postResult(_ path: String, identity: SeshIdentity?, _ payload: [String: Any],
                    idempotencyKey: String? = nil) async -> Result<Void, APIError> {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure(.invalidRequest)
        }
        return await postRaw(path, body: data, idempotencyKey: idempotencyKey)
    }

    /// (#C5) Raw POST used both directly and by the OfflineOutbox replay.
    /// The idempotency key makes redelivery safe.
    @discardableResult
    func postRaw(_ path: String, body: Data, idempotencyKey: String? = nil) async -> Result<Void, APIError> {
        guard let req = makeRequest(path, method: "POST", identity: nil, body: body,
                                    idempotencyKey: idempotencyKey) else {
            return .failure(.invalidRequest)
        }
        do {
            let (_, resp) = try await send(req)
            switch resp.statusCode {
            case 200...299: return .success(())
            case 429:        return .failure(.rateLimited)
            case 404:        return .failure(.notFound)
            default:         return .failure(.server(resp.statusCode))
            }
        } catch {
            return .failure(.network)
        }
    }

    struct ActivityBody: Encodable {
        var activity: String
        var detail: String
        var occurredAt: Date = Date()
    }
    struct MessageBody: Encodable { var id: String; var text: String }
    struct TokenBody: Encodable { var token: String }
    struct FriendCodeBody: Encodable { var code: String }
    struct TargetUserBody: Encodable { var userID: String }

    func postActivity(_ activity: SeshActivity, detail: String?, identity: SeshIdentity?) async {
        _ = await post("/api/activity", body: ActivityBody(activity: activity.rawValue, detail: detail ?? ""))
    }

    // MARK: Profile

    private struct ProfileBody: Encodable { var handle: String; var name: String; var code: String }
    private struct ProfileResponse: Decodable { let token: String; let uid: String }

    /// Push the current display name / handle to the Worker.
    ///
    /// The session token itself carries the display name, and the Worker stamps
    /// that name onto every chat message — so renaming yourself only reaches
    /// other people once the session is re-minted. The Worker returns a fresh
    /// token for the SAME verified uid (no re-authentication), which we swap in.
    @discardableResult
    func updateProfile(identity: SeshIdentity?) async -> Bool {
        guard let identity, SeshAuth.shared.token != nil else { return false }
        let body = ProfileBody(handle: identity.handle, name: identity.name, code: identity.code)
        guard let data = try? Self.encoder.encode(body),
              let req = makeRequest("/api/profile", method: "POST", identity: identity, body: data) else { return false }
        do {
            let (payload, resp) = try await send(req)
            guard resp.statusCode == 200,
                  let decoded = try? Self.decoder.decode(ProfileResponse.self, from: payload) else { return false }
            SeshAuth.shared.adoptRefreshedSession(token: decoded.token, uid: decoded.uid,
                                                  handle: identity.handle, name: identity.name,
                                                  code: identity.code)
            return true
        } catch {
            // Fail soft: the name syncs on the next launch's exchange.
            return false
        }
    }

    // MARK: Rooms

    private struct RoomJoinBody: Encodable { var roomID: String }

    /// Register the caller as a member of a chat room (drives "N members").
    func joinRoom(_ roomID: String, identity: SeshIdentity?) async {
        let safeID = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomID
        _ = await post("/api/rooms/\(safeID)/join", body: RoomJoinBody(roomID: roomID))
    }

    // MARK: Scrobbler (now-playing)

    /// Broadcast the current user's now-playing track.
    func postNowPlaying(_ np: NowPlaying, identity: SeshIdentity?) async {
        await post("/api/nowplaying", identity: identity, [
            "title": np.title, "artist": np.artist, "album": np.album ?? "",
            "artworkURL": np.artworkURL ?? "", "source": np.source.rawValue,
            "isPlaying": np.isPlaying])
    }

    /// Clear the current user's now-playing.
    func clearNowPlaying(identity: SeshIdentity?) async {
        await post("/api/nowplaying/clear", identity: identity, [:])
    }

    /// Fetch the user's Spotify now-playing via the Worker (which holds the
    /// refresh token and talks to Spotify). Returns nil if nothing is playing.
    func spotifyNowPlaying(identity: SeshIdentity?) async -> NowPlaying? {
        guard let req = makeRequest("/api/spotify/now-playing", identity: identity) else { return nil }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode(NowPlaying.self, from: data)
        } catch {
            return nil
        }
    }

    /// Exchange a Spotify authorization code for tokens (server-side secret swap).
    func spotifyExchange(code: String, verifier: String, redirectURI: String,
                         identity: SeshIdentity?) async -> Bool {
        await post("/api/spotify/exchange", identity: identity,
                   ["code": code, "verifier": verifier, "redirectURI": redirectURI])
    }

    /// Unlink Spotify (Worker deletes the stored refresh token).
    func spotifyDisconnect(identity: SeshIdentity?) async -> Bool {
        await post("/api/spotify/disconnect", identity: identity, [:])
    }

    // MARK: Spotify search + playlist export (Worker holds the token)

    /// Search Spotify's catalog for tracks (via the Worker).
    func spotifySearch(query: String, identity: SeshIdentity?) async -> [PlaylistTrack] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let req = makeRequest("/api/spotify/search?q=\(encoded)", identity: identity) else { return [] }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else { return [] }
            return try Self.decoder.decode([PlaylistTrack].self, from: data)
        } catch {
            return []
        }
    }

    /// Create (or update) a Spotify playlist with the given tracks. The Worker
    /// matches each track (ISRC first), creates the playlist on the user's
    /// account, adds the matches, and returns the playlist URL + counts.
    func spotifyExportPlaylist(name: String, tracks: [PlaylistTrack], existingID: String?,
                               identity: SeshIdentity?) async -> ExportResult {
        let trackPayload: [[String: Any]] = tracks.map { t in
            [ "title": t.title, "artist": t.artist, "album": t.album ?? "",
              "isrc": t.isrc ?? "", "spotifyURI": t.spotifyURI ?? "" ]
        }
        var body: [String: Any] = ["name": name, "tracks": trackPayload]
        if let existingID { body["existingID"] = existingID }
        guard let data = try? JSONSerialization.data(withJSONObject: enrich(body, identity)),
              let req = makeRequest("/api/spotify/playlist", method: "POST", identity: identity, body: data) else {
            return .failure("Couldn't reach Spotify.")
        }
        do {
            let (respData, resp) = try await send(req)
            let code = resp.statusCode
            guard code == 200 else { return .failure("Spotify export failed (\(code)).") }
            let decoded = try Self.decoder.decode(SpotifyExportResponse.self, from: respData)
            return .success(addedCount: decoded.added, total: decoded.total, url: decoded.url)
        } catch {
            return .failure("Spotify export failed.")
        }
    }

    /// Merge identity fields into a JSON body (mirrors what post() does).
    private func enrich(_ body: [String: Any], _ identity: SeshIdentity?) -> [String: Any] {
        var b = body
        if let id = identity {
            b["userID"] = id.userID; b["handle"] = id.handle; b["name"] = id.name; b["code"] = id.code
        }
        return b
    }

    /// Invite friends to a sesh / cypher. The Worker is responsible for turning
    /// this into a push to each invited friend's device.
    func postInvite(handles: [String], detail: String?, identity: SeshIdentity?) async {
        await post("/api/invite", identity: identity,
                   ["handles": handles, "detail": detail ?? ""])
    }

    /// Broadcast a one-off milestone (e.g. a new roll record) so friends get a
    /// push. `kind` lets the Worker pick the right wording/emoji.
    func postMilestone(kind: String, detail: String?, identity: SeshIdentity?) async {
        await post("/api/milestone", identity: identity, ["kind": kind, "detail": detail ?? ""])
    }

    func heartbeat(identity: SeshIdentity?) async {
        await post("/api/heartbeat", identity: identity, [:])
    }

    func setPresence(online: Bool, identity: SeshIdentity?) async {
        await post("/api/presence", identity: identity, ["online": online])
    }

    func createCypher(_ c: Cypher, identity: SeshIdentity?) async {
        await post("/api/cyphers", identity: identity,
                   ["id": c.id, "title": c.title, "strain": c.strainName ?? "",
                    "live": c.isLive, "visibility": c.visibility.rawValue])
    }
    func joinCypher(_ id: String, identity: SeshIdentity?) async { await post("/api/cyphers/\(id)/join", identity: identity, [:]) }
    func leaveCypher(_ id: String, identity: SeshIdentity?) async { await post("/api/cyphers/\(id)/leave", identity: identity, [:]) }

    func startLive(_ s: LiveStream, identity: SeshIdentity?) async {
        await post("/api/live", identity: identity,
                   ["id": s.id, "title": s.title, "strain": s.strainName ?? "", "cypher": s.cypherID ?? ""])
    }
    func endLive(_ id: String, identity: SeshIdentity?) async { await post("/api/live/\(id)/end", identity: identity, [:]) }

    /// Register this device's APNs token so friends' "went live" events can push.
    func registerPush(token: String, identity: SeshIdentity?) async {
        _ = await post("/api/push/register", body: TokenBody(token: token))
    }
    /// Remove a token (sign-out / permission revoked).
    func unregisterPush(token: String, identity: SeshIdentity?) async {
        _ = await post("/api/push/unregister", body: TokenBody(token: token))
    }

    func sendMessage(_ m: ChatMessage, identity: SeshIdentity?) async {
        _ = await post("/api/rooms/\(m.roomID)/messages", body: MessageBody(id: m.id, text: m.text),
                       idempotencyKey: m.id)
    }

    /// Add a friend by their code. Returns true on success.
    func addFriend(code: String, identity: SeshIdentity?) async -> Bool {
        if case .success = await post("/api/friends/add", body: FriendCodeBody(code: code)) { return true }
        return false
    }

    /// Block / unblock a user (their content disappears from your snapshot & chat).
    func block(userID: String, identity: SeshIdentity?) async -> Bool {
        if case .success = await post("/api/block", body: TargetUserBody(userID: userID)) { return true }
        return false
    }
    func unblock(userID: String, identity: SeshIdentity?) async -> Bool {
        if case .success = await post("/api/unblock", body: TargetUserBody(userID: userID)) { return true }
        return false
    }

    /// Report a user or a message for moderation.
    func report(userID: String?, messageID: String?, reason: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/report", identity: identity,
                   ["userID": userID ?? "", "messageID": messageID ?? "", "reason": reason])
    }

    /// Shared ISO-8601 formatter — allocating one per call is expensive.
    private static let isoFormatter = ISO8601DateFormatter()

    /// Fetch a page of older messages before a given timestamp (pagination).
    func fetchMessages(roomID: String, before: Date?, limit: Int, identity: SeshIdentity?) async -> [ChatMessage]? {
        var path = "/api/rooms/\(roomID)/messages?limit=\(limit)"
        if let before {
            let iso = Self.isoFormatter.string(from: before)
            if let encoded = iso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&before=\(encoded)"
            }
        }
        guard let req = makeRequest(path, identity: identity) else { return nil }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode([ChatMessage].self, from: data)
        } catch { return nil }
    }
}

// MARK: - The Lounge (SESH-RL-001-R2)
//
// Lives in this file so it can reuse SeshAPI's private request plumbing —
// bearer auth, the silent 401 re-exchange, and the retry ladder. Swift's
// `private` is file-scoped for extensions, so an extension in a separate file
// could not reach `makeRequest`/`sendWithRetry`.

extension SeshAPI {

    /// One page of the Lounge feed. `cursor` is opaque and comes from the
    /// previous page; nil starts a fresh feed session. `session` pins template
    /// stability so post shapes don't jump between pages (§11).
    func fetchLoungeFeed(tab: LoungeTab,
                         filter: LoungeFilter,
                         cursor: String?,
                         sessionID: String?,
                         identity: SeshIdentity?) async -> LoungeFeedPage? {
        var path = "/api/lounge/feed?tab=\(tab.rawValue)&filter=\(filter.rawValue)"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        if let sessionID, let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&session=\(encoded)"
        }
        guard let req = makeRequest(path, identity: identity) else { return nil }
        do {
            let (data, resp) = try await sendWithRetry(req)
            guard resp.statusCode == 200 else {
                Diag.network.warning("lounge feed failed: \(resp.statusCode)")
                return nil
            }
            return try Self.decoder.decode(LoungeFeedPage.self, from: data)
        } catch {
            return nil
        }
    }

    /// Full post plus comments for the expanded view (Phase 3).
    func fetchLoungePost(id: String, identity: SeshIdentity?) async -> LoungePostDetail? {
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let req = makeRequest("/api/lounge/post/\(safeID)", identity: identity) else { return nil }
        do {
            let (data, resp) = try await sendWithRetry(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode(LoungePostDetail.self, from: data)
        } catch {
            return nil
        }
    }

    func reactLounge(postID: String, on: Bool, identity: SeshIdentity?) async -> Bool {
        await post("/api/lounge/react", identity: identity, ["postID": postID, "on": on])
    }

    /// Live-room presence: how many sockets/participants are currently in the
    /// room (Phase 4). Returns nil on any failure so callers can keep the last
    /// known count instead of flashing to zero.
    func fetchRoomPresence(roomID: String, identity: SeshIdentity?) async -> Int? {
        let safeID = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomID
        guard let req = makeRequest("/api/rooms/\(safeID)/presence", identity: identity) else { return nil }
        struct PresenceResponse: Decodable { let count: Int }
        do {
            let (data, resp) = try await sendWithRetry(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode(PresenceResponse.self, from: data).count
        } catch {
            return nil
        }
    }

    /// Returns the recomputed poll so percentages come from the server, not
    /// from an optimistic guess.
    /// Plain `send` (no retry ladder): voting is not idempotent, and a retry
    /// after a flaky response could double-submit.
    func voteLoungePoll(postID: String, choiceID: String, identity: SeshIdentity?) async -> LoungePollContent? {
        let payload: [String: Any] = ["postID": postID, "choiceID": choiceID]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let req = makeRequest("/api/lounge/vote", method: "POST", identity: identity, body: body)
        else { return nil }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode(LoungePollContent.self, from: data)
        } catch {
            return nil
        }
    }

    /// Plain `send` (no retry ladder): commenting is not idempotent, and a
    /// retry after a flaky response could post the comment twice.
    func commentLounge(postID: String, text: String, identity: SeshIdentity?) async -> LoungeComment? {
        let payload: [String: Any] = ["postID": postID, "text": text]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let req = makeRequest("/api/lounge/comment", method: "POST", identity: identity, body: body)
        else { return nil }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else { return nil }
            return try Self.decoder.decode(LoungeComment.self, from: data)
        } catch {
            return nil
        }
    }

    func reportLounge(postID: String, reason: LoungeReportReason, detail: String,
                      identity: SeshIdentity?) async -> Bool {
        await post("/api/lounge/report", identity: identity,
                   ["postID": postID, "reason": reason.rawValue, "detail": detail])
    }

    func hideLounge(postID: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/lounge/hide", identity: identity, ["postID": postID])
    }

    // MARK: Compose (Phase 4)

    /// Typed body for POST /api/lounge/create. Field shapes mirror the Worker's
    /// sanitizers (lounge.ts): media keeps url/aspectRatio (altText is accepted
    /// but optional), poll choices are {id,label} — the server forces votes and
    /// totals to zero at create time, so none are sent.
    struct LoungeCreateBody: Encodable {
        struct Media: Encodable {
            var url: String
            var aspectRatio: Double
            var altText: String?
        }
        struct Track: Encodable {
            var title: String
            var artist: String
            var artworkURL: String?
            var previewURL: String?
            var durationSeconds: Double?
            var vibeTags: [String] = []
        }
        struct PollChoice: Encodable {
            var id: String
            var label: String
        }
        struct Poll: Encodable {
            var question: String
            var choices: [PollChoice]
        }

        /// Not encoded — sent as X-Idempotency-Key so the Worker dedupes a
        /// retried submit instead of double-posting.
        var idempotencyKey: String = UUID().uuidString

        var kind: String
        var text: String
        var media: [Media] = []
        var track: Track?
        var poll: Poll?
        var strainName: String?
        var method: String?
        var mood: String?
        var vibeTags: [String] = []
        var visibility: String

        private enum CodingKeys: String, CodingKey {
            case kind, text, media, track, poll
            case strainName, method, mood, vibeTags, visibility
        }
    }

    private struct LoungeCreateResponse: Decodable {
        var post: LoungePost
    }

    /// Plain `send` (no retry ladder): creation is not idempotent at the
    /// transport level. The draft's idempotency key rides along as
    /// X-Idempotency-Key so an app-level resubmit of the same draft is deduped
    /// by the Worker instead of producing a duplicate post.
    func createLoungePost(_ draft: LoungeCreateBody, identity: SeshIdentity?) async -> LoungePost? {
        guard let body = try? Self.encoder.encode(draft),
              let req = makeRequest("/api/lounge/create", method: "POST", identity: identity,
                                    body: body, idempotencyKey: draft.idempotencyKey)
        else { return nil }
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else {
                Diag.network.warning("lounge create failed: \(resp.statusCode)")
                return nil
            }
            return try Self.decoder.decode(LoungeCreateResponse.self, from: data).post
        } catch {
            return nil
        }
    }

    /// Uploads a compose photo as a raw JPEG body (server cap: 2 MB) and
    /// returns the absolute URL to reference in media[].url. Plain `send`: a
    /// duplicate upload just orphans a blob, but retrying automatically could
    /// stack uploads on a flaky link.
    func uploadLoungeMedia(_ jpeg: Data, identity: SeshIdentity?) async -> String? {
        guard var req = makeRequest("/api/lounge/media", method: "POST",
                                    identity: identity, body: jpeg) else { return nil }
        // makeRequest assumes JSON bodies; this endpoint takes the raw image.
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp) = try await send(req)
            guard resp.statusCode == 200 else {
                Diag.network.warning("lounge media upload failed: \(resp.statusCode)")
                return nil
            }
            struct UploadResponse: Decodable { var url: String }
            return try Self.decoder.decode(UploadResponse.self, from: data).url
        } catch {
            return nil
        }
    }

    /// Ends a live room post (POST /api/lounge/live/end). Lives here with the
    /// rest of the Lounge calls; the live feature drives it.
    func endLoungeLive(postID: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/lounge/live/end", identity: identity, ["postID": postID])
    }
}
