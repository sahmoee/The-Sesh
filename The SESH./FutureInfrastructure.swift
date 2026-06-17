//
//  FutureInfrastructure.swift
//  The SESH
//
//  SCAFFOLDING ONLY — these three systems require infrastructure that must be
//  provisioned outside this codebase (a paid Cloudflare plan, an Apple Push
//  certificate, a CloudKit container). The types below define the intended
//  shape and document exactly what's left to do, but they are NOT wired into
//  the app yet. Nothing here is called at runtime; it's a roadmap in code.
//
//  When you're ready to implement any of these, follow the TODOs in order.
//

import Foundation

// MARK: - 1. Real-time via WebSockets (replaces polling)
//
// Today the app polls /api/snapshot every ~12s (see SocialStore.startPolling).
// That feels "live" at ~12s granularity. True push needs a persistent socket.
//
// PLAN (Cloudflare Durable Objects + WebSockets):
//   1. Add a Durable Object class to the Worker (one instance per room/cypher),
//      holding the connected WebSockets in memory.
//   2. New route: GET /api/rooms/:id/socket  -> upgrade to WebSocket, register
//      the connection on that room's Durable Object.
//   3. On POST message / activity, the DO broadcasts to all connected sockets.
//   4. Requires a Cloudflare Workers PAID plan (Durable Objects aren't on free).
//   5. Client: replace the poll loop with URLSessionWebSocketTask; keep the
//      poll as a fallback when the socket drops.
//
// The request/response payloads do NOT need to change — only the transport —
// so SeshSnapshot / ChatMessage stay as-is.

enum RealtimeTODO {
    /// Build from BuildConfig.workerURL, swapping https→wss.
    static func socketURL(roomID: String) -> URL? {
        let base = BuildConfig.workerURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(base)/api/rooms/\(roomID)/socket")
    }
    // TODO: final class RoomSocket using URLSessionWebSocketTask:
    //   - connect(roomID:), receive loop decoding ChatMessage, send(text:)
    //   - auto-reconnect with backoff; on failure, SocialStore falls back to poll
}

// MARK: - 2. Push notifications (APNs)
//
// For "Shalise went live", "someone joined your Cypher", "@dro replied".
//
// PLAN:
//   1. Xcode: add the "Push Notifications" capability + Background Modes →
//      Remote notifications. (Adds aps-environment to the entitlements.)
//   2. Request authorization (UNUserNotificationCenter) and register for remote
//      notifications; send the APNs device token to the Worker (new route
//      POST /api/push/register { token }).
//   3. Server side needs to actually SEND pushes — a Worker can call APNs over
//      HTTP/2 with a signed JWT (requires an APNs Auth Key .p8 from your Apple
//      Developer account + Key ID + Team ID stored as Worker secrets).
//   4. Trigger pushes from the events that already exist (activity, cypher join,
//      live start, new message to a friend).
//
// REQUIRES: paid Apple Developer account, APNs Auth Key, and storing secrets in
// the Worker (wrangler secret put APNS_KEY ...).

struct PushRegistration: Codable {
    var token: String
    var userID: String
    // TODO: POST to /api/push/register; store token in KV keyed by userID.
}

enum PushTODO {
    // TODO: in the app delegate / App scene:
    //   - UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge])
    //   - UIApplication.shared.registerForRemoteNotifications()
    //   - didRegisterForRemoteNotificationsWithDeviceToken -> upload token
}

// MARK: - 3. CloudKit photo sync
//
// Today photos live ON-DEVICE only (PhotoStore writes to the documents dir);
// everything else syncs via iCloud key-value store. KVS can't hold images
// (1MB total budget), so photos don't follow you to a new device.
//
// PLAN (CloudKit private database):
//   1. Xcode: add the "iCloud" capability → check "CloudKit" (in addition to
//      the existing Key-value storage). This creates a CloudKit container.
//   2. Define a record type "SeshPhoto" { photoName: String, asset: CKAsset }.
//   3. On save: write the image as a CKAsset to the user's PRIVATE database,
//      keyed by the same photoName the JournalEntry/StrainProfile already store.
//   4. On load (cache miss): fetch the CKAsset by photoName, cache to disk via
//      the existing PhotoStore so the rest of the app is unchanged.
//   5. Handle CKError (network, quota, not-signed-in) by falling back to the
//      local-only behavior that exists today.
//
// REQUIRES: CloudKit container configured in your Apple Developer account.
// The app's photoName indirection means only PhotoStore needs to change.

struct CloudPhotoRef: Codable {
    var photoName: String
    // TODO: CKRecord "SeshPhoto"; CKAsset for the image bytes; private DB.
}

enum CloudKitPhotoTODO {
    // TODO: extend PhotoStore with:
    //   - func uploadIfNeeded(_ name: String)  -> writes CKAsset
    //   - func fetch(_ name: String) async -> UIImage?  -> on local cache miss
    //   - keep all callers using photoName; CloudKit stays an implementation detail
}

// MARK: - 4. Community strain photos (#10)
//
// Today strain photos are either a user's own on-device photo (custom strains)
// or the drawn BudThumb placeholder. To let users CONTRIBUTE photos that other
// users see, the images need to live in shared object storage with moderation —
// they can't be device-local, and they can't go in the social KV (too large).
//
// PLAN (Cloudflare R2 object storage + a moderation queue):
//   1. Add an R2 bucket binding to the Worker (e.g. SESH_PHOTOS). R2 is built
//      for blob storage and is far cheaper than KV for images.
//   2. Upload flow (per submission):
//        - Client compresses to JPEG (~1200px max, < ~300KB).
//        - POST /api/strains/:id/photo (multipart or base64) -> Worker stores
//          the bytes in R2 under a pending/ prefix and records a submission in
//          KV: { strainID, userID, key, status: "pending", at }.
//        - Submissions are NOT shown until approved (see moderation).
//   3. Moderation:
//        - A review queue (GET /api/admin/photo-queue, guarded by ADMIN_KEY).
//        - Approve -> move R2 object from pending/ to public/ and set the
//          strain's communityPhotoURL; reject -> delete the object.
//        - Until you have automated moderation, this is a manual admin step.
//          (Optionally add an image-moderation API call before approval.)
//   4. Serving:
//        - Approved photos are served from R2's public URL (or via the Worker).
//        - StrainProfile gains an optional communityPhotoURL the detail/cards
//          load via StoredImage's remote path (which would need a small
//          extension to fetch+cache a URL, mirroring the local PhotoStore).
//   5. Safety / abuse:
//        - Rate-limit submissions (reuse the Worker's rateLimit helper).
//        - Require sign-in to submit; keep userID with each submission so a
//          bad actor's photos can be bulk-removed.
//
// REQUIRES: an R2 bucket configured in your Cloudflare account + a moderation
// process. Nothing here is wired; it documents the contract.

struct CommunityPhotoSubmission: Codable {
    var strainID: String
    var userID: String
    var imageBase64: String        // compressed JPEG
    // TODO: POST to /api/strains/:id/photo; Worker stores in R2 (pending/).
}

struct CommunityPhotoRef: Codable {
    var strainID: String
    var url: String                // public R2 URL once approved
    var status: String             // "pending" | "approved" | "rejected"
}

enum CommunityPhotoTODO {
    // Build URL for an approved community photo (placeholder shape).
    static func publicURL(base: String, key: String) -> URL? {
        URL(string: "\(base)/\(key)")
    }
    // TODO on the app side:
    //   - PhotoField gains a "Submit to community" option for catalog strains.
    //   - StoredImage gains a remote-URL path that fetches + disk-caches, so the
    //     rest of the app keeps using a single image view.
    //   - StrainProfile.communityPhotoURL is preferred over BudThumb when set.
    // TODO on the Worker side:
    //   - R2 bucket binding, /api/strains/:id/photo (upload, rate-limited),
    //     /api/admin/photo-queue + approve/reject (ADMIN_KEY guarded).
}
