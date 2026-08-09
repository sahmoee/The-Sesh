//
//  StrainImageStore.swift
//  The SESH
//
//  Resolves the best available image for a strain, in priority order:
//    1. User photo  — a photo the user attached to this strain (local file via
//       PhotoStore). Always wins; it's real and it's theirs.
//    2. Remote image — a license-clear real photo (or curated art) the Worker
//       serves via a manifest of strainID -> URL. Downloaded once and disk-cached.
//    3. Procedural art — BudThumb, drawn locally from the strain's id + type.
//       Always available, offline, zero cost, zero licensing risk.
//
//  IMPORTANT (licensing): the remote manifest must only ever point at images we
//  have the right to use — Wikimedia Commons / Openverse (CC / public domain) or
//  our own art. It must NEVER contain Leafly/Weedmaps/Google-Images URLs. The app
//  shows the attribution string the manifest provides (some CC licenses require
//  credit). See the Worker README.
//
//  Hosting: the manifest + images are served from the Cloudflare Worker and
//  fetched on demand, so nothing here is bundled and app size is unaffected.
//

import SwiftUI
import Observation

// MARK: - Manifest model

/// One strain's image entry as served by the Worker manifest.
struct StrainImageEntry: Codable, Hashable {
    var url: String
    /// "photo" (real, license-clear) or "art" (curated illustration).
    var kind: String?
    /// Required credit line for CC-licensed photos, e.g. "Photo: Jane Doe / CC BY-SA".
    var attribution: String?
}

// MARK: - Store

@Observable
@MainActor
final class StrainImageStore {
    /// strainID -> remote image entry, loaded from the Worker manifest.
    private var manifest: [String: StrainImageEntry] = [:]

    /// strainID -> local user-photo filename (PhotoStore). Persisted.
    private var userPhotos: [String: String] = [:]

    /// In-memory cache of decoded images, keyed by strainID, to avoid re-reading
    /// from disk on every cell. Bounded.
    private var memoryCache: [String: UIImage] = [:]
    private var cacheOrder: [String] = []
    private let memoryLimit = 120

    /// The base URL the manifest + images are served from. Configured at launch.
    private var baseURL: URL?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        return URLSession(configuration: cfg)
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.strainUserPhotos),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            userPhotos = saved
        }
    }

    // MARK: Configuration

    /// Point the store at the Worker and load the manifest. Safe to call on
    /// launch; failures fall back to art with no error surfaced to the user.
    func configure(baseURL: URL) async {
        self.baseURL = baseURL
        await loadManifest()
    }

    private func loadManifest() async {
        guard let baseURL else { return }
        let url = baseURL.appendingPathComponent("strain-images.json")
        guard let (data, _) = try? await session.data(from: url),
              let decoded = try? JSONDecoder().decode([String: StrainImageEntry].self, from: data)
        else { return }
        manifest = decoded
    }

    // MARK: Resolution

    /// Does this strain have a real or art image available (vs. only procedural)?
    func hasImage(strainID: String) -> Bool {
        userPhotos[strainID] != nil || manifest[strainID] != nil
    }

    /// Attribution to display under a remote photo, if any.
    func attribution(strainID: String) -> String? {
        guard userPhotos[strainID] == nil else { return nil } // user photo: no credit
        return manifest[strainID]?.attribution
    }

    /// Return the best image for a strain, or nil to fall back to BudThumb.
    /// Resolution order: user photo -> remote (cached) -> nil.
    func image(strainID: String) async -> UIImage? {
        if let cached = memoryCache[strainID] { return cached }

        // 1. User photo (local file).
        if let name = userPhotos[strainID],
           let img = await Task.detached(priority: .utility, operation: { PhotoStore.load(name) }).value {
            store(img, for: strainID)
            return img
        }

        // 2. Remote image from the manifest — via the shared pipeline (#13):
        //    coalesced downloads, disk cache, bounded-size decode, cancellation.
        if let entry = manifest[strainID], let url = remoteURL(for: entry.url) {
            if let img = await ImagePipeline.shared.image(from: url) {
                store(img, for: strainID)
                return img
            }
        }

        // 3. Bundled bud photo, deterministically assigned per strain so each
        //    strain always shows the same photo until the user sets their own.
        if let img = Self.bundledBud(for: strainID) {
            store(img, for: strainID)
            return img
        }

        // 4. No image -> caller draws BudThumb.
        return nil
    }

    /// Number of bundled bud photos (bud_01 ... bud_NN).
    static let bundledBudCount = 30

    /// Pick a stable bundled bud photo for a strain id. Same id -> same photo.
    /// (#12) Uses FNV-1a over the id's UTF-8 bytes. Swift's `hashValue` is
    /// randomly seeded per process, so the previous implementation reassigned
    /// every strain a different photo on every launch despite the comment.
    static func bundledBud(for strainID: String) -> UIImage? {
        guard bundledBudCount > 0 else { return nil }
        let name = String(format: "bud_%02d", budIndex(for: strainID))
        return UIImage(named: name)
    }

    /// The 1-based bundled-photo index for a strain id. Internal (not private)
    /// so unit tests can assert cross-launch stability (#16).
    static func budIndex(for strainID: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in strainID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(bundledBudCount)) + 1
    }

    /// Resolve a manifest URL string, allowing either absolute URLs or paths
    /// relative to the Worker base.
    private func remoteURL(for raw: String) -> URL? {
        if raw.hasPrefix("http"), let u = URL(string: raw) { return u }
        return baseURL?.appendingPathComponent(raw)
    }

    // MARK: User photos

    /// Attach a user photo to a strain. Saves the image and remembers the mapping.
    func setUserPhoto(_ image: UIImage, strainID: String) {
        // Remove any prior photo for this strain to avoid orphaned files.
        if let old = userPhotos[strainID] { PhotoStore.delete(old) }
        guard let name = PhotoStore.save(image) else { return }
        userPhotos[strainID] = name
        memoryCache[strainID] = image
        if !cacheOrder.contains(strainID) { cacheOrder.append(strainID) }
        persistUserPhotos()
    }

    /// Remove a user photo for a strain (reverts to remote/art).
    func removeUserPhoto(strainID: String) {
        if let old = userPhotos[strainID] { PhotoStore.delete(old) }
        userPhotos[strainID] = nil
        memoryCache[strainID] = nil
        cacheOrder.removeAll { $0 == strainID }
        persistUserPhotos()
    }

    func hasUserPhoto(strainID: String) -> Bool { userPhotos[strainID] != nil }

    // MARK: Cache plumbing

    private func store(_ image: UIImage, for id: String) {
        memoryCache[id] = image
        // LRU: re-storing an id must move it to the tail, not duplicate it —
        // duplicate entries make eviction evict the wrong (still-hot) images.
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        if cacheOrder.count > memoryLimit {
            let evict = cacheOrder.removeFirst()
            if userPhotos[evict] == nil { memoryCache[evict] = nil }
        }
    }

    private func persistUserPhotos() {
        if let data = try? JSONEncoder().encode(userPhotos) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.strainUserPhotos)
        }
    }
}
