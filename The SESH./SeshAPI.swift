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
    private var base: URL? { URL(string: BuildConfig.workerURL) }

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

    /// Shared decoder (ISO-8601 dates) so each call doesn't allocate one.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func makeRequest(_ path: String, method: String = "GET",
                             identity: SeshIdentity?, body: Data? = nil,
                             idempotencyKey: String? = nil) -> URLRequest? {
        guard let base, let url = URL(string: path, relativeTo: base) else { return nil }
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

    struct ActivityBody: Encodable { var activity: String; var detail: String }
    struct MessageBody: Encodable { var id: String; var text: String }
    struct TokenBody: Encodable { var token: String }
    struct FriendCodeBody: Encodable { var code: String }
    struct TargetUserBody: Encodable { var userID: String }

    func postActivity(_ activity: SeshActivity, detail: String?, identity: SeshIdentity?) async {
        _ = await post("/api/activity", body: ActivityBody(activity: activity.rawValue, detail: detail ?? ""))
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

    /// Fetch a page of older messages before a given timestamp (pagination).
    func fetchMessages(roomID: String, before: Date?, limit: Int, identity: SeshIdentity?) async -> [ChatMessage]? {
        var path = "/api/rooms/\(roomID)/messages?limit=\(limit)"
        if let before {
            let iso = ISO8601DateFormatter().string(from: before)
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
