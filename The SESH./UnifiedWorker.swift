//
//  UnifiedWorker.swift
//  The SESH.
//
//  One place that knows where the backend is.
//
//  The SESH.'s Worker was merged into a single Cloudflare Worker
//  (`sowens-worker`, in Documents/worker) alongside Stocked, Atlas and Astra.
//  The Durable Objects came with it — SocialDO, RoomDO and LoungeDO were
//  *transferred*, not recreated, so every friend graph, chat room and lounge
//  post is the same storage it always was.
//
//  Shipped builds hardcode https://sesh-worker.stocked.workers.dev
//  (BuildConfig.swift:52-59). A workers.dev hostname belongs to a script NAME
//  and cannot be re-pointed, so that URL is kept alive by a ~15-line shim Worker
//  that forwards to the merged one — including the WebSocket upgrades that
//  SeshRealtime depends on.
//
//  New builds should move to the path-prefix form. Flip `useUnifiedEndpoint`,
//  ship, and delete the shim once old builds have aged out.
//

import Foundation

enum SeshUnifiedWorker {

    /// Flip to `true` in the release that moves The SESH. onto the merged
    /// endpoint.
    ///
    /// `false` → https://sesh-worker.stocked.workers.dev (via the shim)
    /// `true`  → https://api.sowensstudios.com/sesh
    static let useUnifiedEndpoint = true

    static let legacyBase = "https://sesh-worker.stocked.workers.dev"
    static let unifiedBase = "https://api.sowensstudios.com/sesh"

    /// Drop-in for `BuildConfig.workerURL`, preserving the DEBUG override so a
    /// debug build can still be pointed at a dev Worker from UserDefaults.
    static var baseURLString: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "sesh.dev.workerURL"), !override.isEmpty {
            return override
        }
        #endif
        return useUnifiedEndpoint ? unifiedBase : legacyBase
    }

    static var baseURL: URL? { URL(string: baseURLString) }

    /// Build a URL for an API path.
    ///
    /// `SeshAPI.makeRequest` uses `URL(string: path, relativeTo: base)`. That
    /// idiom is a trap once a base has a path component: relative resolution
    /// against ".../sesh" DROPS the "/sesh" segment, so "/api/snapshot" would
    /// resolve to "https://api.sowensstudios.com/api/snapshot" and 404.
    ///
    /// This helper concatenates instead, which is correct for both bases. Switch
    /// `SeshAPI` and `SeshAuth` to it BEFORE flipping `useUnifiedEndpoint` —
    /// this is the single most likely way to break the migration.
    static func url(_ path: String) -> URL? {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: baseURLString + suffix)
    }

    /// The realtime socket. Mirrors SeshRealtime.swift:61-67, but built from the
    /// same concatenating helper so it stays correct when the base gains a path.
    static func webSocketURL(token: String) -> URL? {
        guard var comps = URLComponents(string: baseURLString) else { return nil }
        comps.scheme = (comps.scheme == "http") ? "ws" : "wss"
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/api/ws"
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url
    }

    /// The merged Worker's cross-app status page.
    static var unifiedHealthURL: URL? {
        URL(string: "https://api.sowensstudios.com/_unified/health")
    }
}

// Adoption, in order — the first two are prerequisites for the third:
//
//   1. `SeshAPI.makeRequest` (SeshAPI.swift:88)   →  SeshUnifiedWorker.url(path)
//   2. `SeshAuth.exchange`   (SeshAuth.swift:88)  →  SeshUnifiedWorker.url(path)
//      `SeshRealtime.runLoop` (SeshRealtime.swift:61) →  webSocketURL(token:)
//   3. Only then set `useUnifiedEndpoint = true`.
//
// Smoke test after flipping, in this order — each one exercises a different
// layer:
//   • auth exchange (Sign in with Apple + DeviceCheck)
//   • /api/snapshot (ETag / 304 handling)
//   • the presence dot going live (the WebSocket)
//   • send a message with the network off, then on (the offline outbox replaying
//     with X-Idempotency-Key against the new base)
