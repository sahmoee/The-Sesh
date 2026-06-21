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

/// One-shot snapshot of the social world from the Worker.
struct SeshSnapshot: Codable {
    var friends: [SeshUser]
    var cyphers: [Cypher]
    var rooms: [ChatRoom]
    var live: [LiveStream]
    var feed: [ActivityEvent]
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
                             identity: SeshIdentity?, body: Data? = nil) -> URLRequest? {
        guard let base, let url = URL(string: path, relativeTo: base) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let id = identity {
            req.setValue(id.userID, forHTTPHeaderField: "x-sesh-user")
            req.setValue(id.handle, forHTTPHeaderField: "x-sesh-handle")
            req.setValue(id.name, forHTTPHeaderField: "x-sesh-name")
            req.setValue(id.code, forHTTPHeaderField: "x-sesh-code")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    // MARK: Reads

    func fetchSnapshot(identity: SeshIdentity?) async -> SeshSnapshot? {
        guard let req = makeRequest("/api/snapshot", identity: identity) else { return nil }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try Self.decoder.decode(SeshSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    func fetchMessages(roomID: String, identity: SeshIdentity?) async -> [ChatMessage]? {
        guard let req = makeRequest("/api/rooms/\(roomID)/messages", identity: identity) else { return nil }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
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

    /// POST returning a typed result so callers can distinguish a network failure
    /// from a rate-limit (HTTP 429) and surface the right message.
    @discardableResult
    func postResult(_ path: String, identity: SeshIdentity?, _ payload: [String: Any]) async -> Result<Void, APIError> {
        var body = payload
        if let id = identity {
            body["userID"] = id.userID; body["handle"] = id.handle; body["name"] = id.name; body["code"] = id.code
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let req = makeRequest(path, method: "POST", identity: identity, body: data) else {
            return .failure(.invalidRequest)
        }
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200...299: return .success(())
            case 429:        return .failure(.rateLimited)
            case 404:        return .failure(.notFound)
            default:         return .failure(.server(code))
            }
        } catch {
            return .failure(.network)
        }
    }

    func postActivity(_ activity: SeshActivity, detail: String?, identity: SeshIdentity?) async {
        await post("/api/activity", identity: identity, ["activity": activity.rawValue, "detail": detail ?? ""])
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
        await post("/api/push/register", identity: identity, ["token": token])
    }
    /// Remove a token (sign-out / permission revoked).
    func unregisterPush(token: String, identity: SeshIdentity?) async {
        await post("/api/push/unregister", identity: identity, ["token": token])
    }

    func sendMessage(_ m: ChatMessage, identity: SeshIdentity?) async {
        await post("/api/rooms/\(m.roomID)/messages", identity: identity, ["id": m.id, "text": m.text])
    }

    /// Add a friend by their code. Returns true on success.
    func addFriend(code: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/friends/add", identity: identity, ["code": code])
    }

    /// Block / unblock a user (their content disappears from your snapshot & chat).
    func block(userID: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/block", identity: identity, ["userID": userID])
    }
    func unblock(userID: String, identity: SeshIdentity?) async -> Bool {
        await post("/api/unblock", identity: identity, ["userID": userID])
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
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try Self.decoder.decode([ChatMessage].self, from: data)
        } catch { return nil }
    }
}
