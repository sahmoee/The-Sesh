//
//  OfflineOutbox.swift
//  The SESH
//
//  (#C5) Durable offline outbox. Social writes (chat messages, activity,
//  friend operations, status changes) are queued locally when they can't be
//  delivered, then replayed in order when connectivity returns. Every
//  operation carries a stable idempotency key, sent as X-Idempotency-Key;
//  the Worker acknowledges duplicates without re-applying them, so a replay
//  that raced a successful-but-unacknowledged send is harmless.
//
//  The queue is persisted to disk (Application Support) so operations survive
//  relaunches, and is bounded to keep pathological backlogs in check.
//

import Foundation
import os

/// One queued write operation.
struct OutboxOperation: Codable, Identifiable {
    let id: String              // idempotency key
    let path: String            // e.g. "/api/rooms/rm_general/messages"
    let body: Data              // JSON payload
    let queuedAt: Date
    var attempts: Int = 0
}

@MainActor
@Observable
final class OfflineOutbox {
    static let shared = OfflineOutbox()

    /// Pending operation count (for a "syncing…" indicator).
    private(set) var pendingCount = 0

    private var queue: [OutboxOperation] = [] {
        didSet { pendingCount = queue.count }
    }
    private var replayTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.sowens.The-SESH-", category: "outbox")
    private static let maxQueued = 500
    private static let maxAttempts = 8

    private init() { load() }

    // MARK: Enqueue

    /// Queue an operation for delivery. Returns the idempotency key.
    @discardableResult
    func enqueue(path: String, body: Data, key: String = UUID().uuidString) -> String {
        queue.append(OutboxOperation(id: key, path: path, body: body, queuedAt: Date()))
        if queue.count > Self.maxQueued { queue.removeFirst(queue.count - Self.maxQueued) }
        persist()
        scheduleReplay()
        return key
    }

    // MARK: Replay

    /// Attempt to deliver everything, oldest first, with exponential backoff
    /// between rounds. Called on reconnect, on app foreground, and after each
    /// enqueue.
    func scheduleReplay(api: SeshAPI = SeshAPI()) {
        guard replayTask == nil, !queue.isEmpty else { return }
        replayTask = Task { [weak self] in
            defer { self?.replayTask = nil }
            var backoff: Double = 1
            while let self, !self.queue.isEmpty, !Task.isCancelled {
                let op = self.queue[0]
                let result = await api.postRaw(op.path, body: op.body, idempotencyKey: op.id)
                switch result {
                case .success:
                    self.queue.removeFirst()
                    self.persist()
                    backoff = 1
                case .failure(let error):
                    switch error {
                    case .notFound, .invalidRequest:
                        // Permanent: drop rather than retry forever.
                        self.log.warning("outbox drop (permanent) path=\(op.path, privacy: .public)")
                        self.queue.removeFirst()
                        self.persist()
                    default:
                        var op0 = self.queue[0]
                        op0.attempts += 1
                        if op0.attempts >= Self.maxAttempts {
                            self.log.warning("outbox drop (max attempts) path=\(op.path, privacy: .public)")
                            self.queue.removeFirst()
                        } else {
                            self.queue[0] = op0
                        }
                        self.persist()
                        // Backoff with jitter before the next round.
                        let delay = backoff + Double.random(in: 0...0.5)
                        try? await Task.sleep(for: .seconds(delay))
                        backoff = min(backoff * 2, 60)
                    }
                }
            }
        }
    }

    func cancelReplay() { replayTask?.cancel(); replayTask = nil }

    // MARK: Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sesh-outbox.json")
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            log.error("outbox persist failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode([OutboxOperation].self, from: data) else { return }
        queue = saved
        pendingCount = saved.count
    }
}
