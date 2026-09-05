import UIKit
import ImageIO

/// Bounded original-byte disk cache plus pixel-size-keyed decoded memory cache.
actor ImagePipeline {
    static let shared = ImagePipeline()

    nonisolated private struct Flight: Sendable {
        let id: UUID
        let task: Task<FetchResult, Never>
        var waiters: Set<UUID>
    }
    // Images are fully decoded before crossing back to the actor and never mutated.
    nonisolated private enum FetchResult: @unchecked Sendable {
        case image(UIImage, downloadedData: Data?)
        case failed
        case cancelled
    }

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Flight] = [:]
    private var recentFailures: [URL: Date] = [:]
    private let failureCooldown: TimeInterval = 120
    private let failureLimit = 256
    private let diskByteLimit = 128 << 20
    private let diskFileLimit = 512
    private var generation = UUID()
    private let session: URLSession
    private let diskDir: URL

    init() {
        memory.totalCostLimit = 64 << 20
        memory.countLimit = 256
        let configuration = URLSessionConfiguration.default
        // The pipeline owns disk caching; avoid storing originals twice.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("image-pipeline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        diskDir = base
    }

    func image(from url: URL, targetSize: CGFloat = 600) async -> UIImage? {
        guard !Task.isCancelled, Self.acceptsURL(url) else { return nil }
        let pixels = SeshReliabilityPolicy.imagePixels(Double(targetSize))
        let key = SeshReliabilityPolicy.imageKey(url, pixels: pixels)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        pruneFailures()
        if recentFailures[url] != nil { return nil }

        let waiter = UUID()
        let currentGeneration = generation
        let flight: Flight
        if var existing = inFlight[key] {
            existing.waiters.insert(waiter)
            inFlight[key] = existing
            flight = existing
        } else {
            let file = diskDir.appendingPathComponent(Self.fileName(for: url))
            let producer = Task.detached(priority: .utility) { [session] in
                await Self.fetch(url: url, file: file, pixels: pixels, session: session)
            }
            flight = Flight(id: UUID(), task: producer, waiters: [waiter])
            inFlight[key] = flight
        }

        let result = await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { await self.cancelWaiter(waiter, key: key, flightID: flight.id) }
        }
        guard !Task.isCancelled, currentGeneration == generation else { return nil }

        // Publish once per flight. A late waiter must not clear a newer request.
        if inFlight[key]?.id == flight.id {
            inFlight[key] = nil
            switch result {
            case .image(let image, let data):
                let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
                memory.setObject(image, forKey: key as NSString, cost: cost)
                recentFailures[url] = nil
                let file = diskDir.appendingPathComponent(Self.fileName(for: url))
                if let data { try? data.write(to: file, options: .atomic) }
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
                pruneDisk()
            case .failed:
                recentFailures[url] = Date()
                pruneFailures()
            case .cancelled:
                break
            }
        }
        if case .image(let image, _) = result { return image }
        return nil
    }

    /// Invalidate before clearing, so suspended work cannot repopulate either tier.
    func clear() {
        generation = UUID()
        for flight in inFlight.values { flight.task.cancel() }
        inFlight.removeAll()
        memory.removeAllObjects()
        recentFailures.removeAll()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    private func cancelWaiter(_ waiter: UUID, key: String, flightID: UUID) {
        guard var flight = inFlight[key], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty {
            flight.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = flight
        }
    }

    private func pruneFailures(now: Date = Date()) {
        recentFailures = recentFailures.filter { now.timeIntervalSince($0.value) < failureCooldown }
        if recentFailures.count > failureLimit {
            for entry in recentFailures.sorted(by: { $0.value < $1.value }).prefix(recentFailures.count - failureLimit) {
                recentFailures[entry.key] = nil
            }
        }
    }

    private func pruneDisk() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: diskDir, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard url.pathExtension == "img", let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, max(values.fileSize ?? 0, 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }
        var total = entries.reduce(0) { $0 + $1.size }
        var count = entries.count
        for entry in entries where total > diskByteLimit || count > diskFileLimit {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                total -= entry.size
                count -= 1
            }
        }
    }

    nonisolated private static func acceptsURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    nonisolated private static func fetch(url: URL, file: URL, pixels: Int, session: URLSession) async -> FetchResult {
        do {
            try Task.checkCancellation()
            if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               attributes.isRegularFile == true,
               let size = attributes.fileSize, size > 0, size <= SeshReliabilityPolicy.maxImageBytes,
               let data = try? Data(contentsOf: file, options: .mappedIfSafe),
               let image = downsample(data: data, maxPixel: pixels) {
                try Task.checkCancellation()
                return .image(image, downloadedData: nil)
            }

            let (bytes, response) = try await session.bytes(from: url)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                  response.url.map(acceptsURL) == true,
                  response.expectedContentLength <= Int64(SeshReliabilityPolicy.maxImageBytes),
                  SeshReliabilityPolicy.acceptsHTTPImage(status: response.statusCode, mime: response.mimeType, bytes: 1) else { return .failed }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < SeshReliabilityPolicy.maxImageBytes else { return .failed }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard SeshReliabilityPolicy.acceptsHTTPImage(status: response.statusCode, mime: response.mimeType, bytes: data.count),
                  let image = downsample(data: data, maxPixel: pixels) else { return .failed }
            try Task.checkCancellation()
            return .image(image, downloadedData: data)
        } catch {
            return Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled ? .cancelled : .failed
        }
    }

    nonisolated private static func fileName(for url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return String(hash, radix: 16) + ".img"
    }

    nonisolated private static func downsample(data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
