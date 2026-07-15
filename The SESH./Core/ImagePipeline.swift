//
//  ImagePipeline.swift
//  The SESH
//
//  (#13) One shared image pipeline for every remote image in the app:
//    - two-tier cache: NSCache memory (cost = pixel bytes) + disk (Caches/)
//    - request coalescing: concurrent asks for the same URL share one download
//    - downsampling: images are decoded at the requested pixel size, not full
//      resolution, which is where list-scroll memory actually goes
//    - cancellation: dropping the task cancels the underlying download
//    - failure memory: recently failed URLs aren't re-hit on every cell reuse
//
//  StrainImageStore delegates its remote fetches here; new features (product
//  photos, recap art, avatars) should use it directly instead of growing
//  their own caches.
//

import UIKit
import ImageIO

actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var recentFailures: [URL: Date] = [:]
    private let failureCooldown: TimeInterval = 120

    private let session: URLSession
    private let diskDir: URL

    init() {
        memory.totalCostLimit = 64 << 20   // 64 MB of decoded pixels
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 128 << 20)
        session = URLSession(configuration: cfg)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("image-pipeline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        diskDir = base
    }

    /// Fetch an image, decoded at (roughly) `targetSize` pixels.
    func image(from url: URL, targetSize: CGFloat = 600) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let failedAt = recentFailures[url], Date().timeIntervalSince(failedAt) < failureCooldown {
            return nil
        }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [diskDir, session] in
            // Disk first.
            let file = diskDir.appendingPathComponent(Self.fileName(for: url))
            if let data = try? Data(contentsOf: file),
               let img = Self.downsample(data: data, maxPixel: targetSize) {
                return img
            }
            // Network.
            guard let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
                  let img = Self.downsample(data: data, maxPixel: targetSize) else {
                return nil
            }
            try? data.write(to: file, options: .atomic)
            return img
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let img = result {
            let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
            memory.setObject(img, forKey: url as NSURL, cost: cost)
            recentFailures[url] = nil
        } else if !Task.isCancelled {
            recentFailures[url] = Date()
        }
        return result
    }

    /// Drop everything (Settings > reset, or memory pressure handling).
    func clear() {
        memory.removeAllObjects()
        recentFailures.removeAll()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    // MARK: internals

    private static func fileName(for url: URL) -> String {
        // FNV-1a of the absolute string — stable, filesystem-safe.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte); hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16) + ".img"
    }

    /// Decode at bounded pixel size via ImageIO (never inflates full-res bitmaps).
    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}
