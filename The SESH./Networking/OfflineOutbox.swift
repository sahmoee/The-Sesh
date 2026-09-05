import Foundation
import Observation
import os

/// Additive fields preserve old files; unowned legacy writes are retained, never reassigned.
struct OutboxOperation: Codable, Identifiable {
    let id: String
    let path: String
    let body: Data
    let queuedAt: Date
    var attempts: Int = 0
    var ownerID: String? = nil
    var heldReason: String? = nil
    var retryAt: Date? = nil
}

@MainActor @Observable final class OfflineOutbox {
    static let shared = OfflineOutbox()
    private(set) var queue: [OutboxOperation] = []
    private(set) var storageError: String?
    private var enqueueError: String?
    private var replayTask: Task<Void, Never>?
    private var replayID: UUID?
    private let storageURL: URL
    private let owner: @MainActor () -> String?
    private let online: @MainActor () -> Bool
    private let automaticallyReplay: Bool
    private let log = Logger(subsystem: "com.sowens.The-SESH-", category: "outbox")
    static let maxQueued = 500
    static let maxAttempts = 8

    var pendingCount: Int { queue.count }
    var heldCount: Int { queue.filter { $0.heldReason != nil || !SeshReliabilityPolicy.ownerMatches($0.ownerID, current: owner()) }.count }
    var canRetry: Bool { storageError != nil || queue.contains { SeshReliabilityPolicy.ownerMatches($0.ownerID, current: owner()) && $0.heldReason != "invalidRequest" } }
    var statusMessage: String? {
        if let storageError { return storageError }
        if let enqueueError { return enqueueError }
        if heldCount > 0 { return "Some unsent actions are saved on this device and need review. Nothing was discarded." }
        if !queue.isEmpty { return "\(queue.count) action\(queue.count == 1 ? "" : "s") waiting to sync." }
        return nil
    }

    /// Injection keeps tests away from real accounts, files and network requests.
    init(storageURL: URL? = nil, owner: @escaping @MainActor () -> String? = { SeshAuth.shared.uid },
         online: @escaping @MainActor () -> Bool = { ConnectivityMonitor.shared.pathSatisfied }, automaticallyReplay: Bool = true) {
        self.storageURL = storageURL ?? Self.defaultURL
        self.owner = owner
        self.online = online
        self.automaticallyReplay = automaticallyReplay
        load()
    }

    @discardableResult
    func enqueue(path: String, body: Data, key: String = UUID().uuidString) -> String? {
        guard storageError == nil else { return nil }
        guard let currentOwner = owner(), !currentOwner.isEmpty else {
            enqueueError = "Connect once to verify your social account before sending. Your draft is still available."; return nil
        }
        if let existing = queue.first(where: { $0.id == key }) {
            guard existing.path == path, existing.body == body, existing.ownerID == currentOwner else {
                enqueueError = "That action could not be safely queued. Please try again."; return nil
            }
            return existing.id
        }
        guard !key.isEmpty, key.utf8.count <= 128, SeshReliabilityPolicy.validOutboxPath(path),
              body.count <= SeshReliabilityPolicy.maxJSONBytes,
              (try? JSONSerialization.jsonObject(with: body)) != nil else {
            enqueueError = "That action is not valid. Your existing saved actions are unchanged."; return nil
        }
        guard queue.count < Self.maxQueued else {
            enqueueError = "The offline queue is full. Sync saved actions before sending more."; return nil
        }
        let candidate = queue + [OutboxOperation(id: key, path: path, body: body, queuedAt: Date(), ownerID: currentOwner)]
        guard commit(candidate) else { return nil }
        enqueueError = nil
        if automaticallyReplay { scheduleReplay() }
        return key
    }

    func scheduleReplay(api suppliedAPI: SeshAPI? = nil) {
        let api = suppliedAPI ?? SeshAPI()
        guard replayTask == nil, storageError == nil, online(), let currentOwner = owner(),
              queue.contains(where: { $0.ownerID == currentOwner && $0.heldReason == nil }) else { return }
        let generation = UUID()
        replayID = generation
        replayTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.replayID == generation { self.replayTask = nil; self.replayID = nil } }
            while !Task.isCancelled, self.replayID == generation, self.online(), self.owner() == currentOwner {
                guard let op = self.queue.first(where: { $0.ownerID == currentOwner && $0.heldReason == nil }) else { return }
                if op.path == "/api/activity", !SeshReliabilityPolicy.mayReplayActivity(op.body,
                    sharesActivity: PrivacySettings.shared.shareActivity,
                    sharesDetails: PrivacySettings.shared.shareStrainDetails) {
                    var held = self.queue
                    if let index = held.firstIndex(where: { $0.id == op.id }) { held[index].heldReason = "privacyChanged" }
                    guard self.commit(held) else { return }
                    continue
                }
                if let retryAt = op.retryAt, retryAt > Date() {
                    do { try await Task.sleep(for: .seconds(min(retryAt.timeIntervalSinceNow, 60))) }
                    catch { return }
                    continue
                }
                let result = await api.postRaw(op.path, body: op.body, idempotencyKey: op.id)
                guard !Task.isCancelled, self.replayID == generation, self.owner() == currentOwner,
                      let index = self.queue.firstIndex(where: { $0.id == op.id && $0.ownerID == currentOwner }) else { return }
                var candidate = self.queue
                switch result {
                case .success:
                    candidate.remove(at: index)
                case .failure(let error):
                    if case .cancelled = error { return }
                    if !self.online() { return }
                    switch error {
                    case .notFound, .invalidRequest: candidate[index].heldReason = "invalidRequest"
                    case .server(let code) where (400...499).contains(code): candidate[index].heldReason = "authorizationOrRequest"
                    default:
                        candidate[index].attempts = min(max(0, candidate[index].attempts), Self.maxAttempts - 1) + 1
                        if candidate[index].attempts >= Self.maxAttempts { candidate[index].heldReason = "retryLimit" }
                        let delay = max(error.retryDelay ?? 0, min(pow(2, Double(candidate[index].attempts)), 60) + Double.random(in: 0...0.5))
                        candidate[index].retryAt = Date().addingTimeInterval(delay)
                    }
                }
                guard self.commit(candidate) else { return }
            }
        }
    }

    func retryHeldOperations() {
        if storageError != nil { load(); guard storageError == nil else { return } }
        guard let current = owner() else { return }
        var candidate = queue
        for index in candidate.indices where candidate[index].ownerID == current && candidate[index].heldReason != "invalidRequest" {
            candidate[index].attempts = 0
            candidate[index].heldReason = nil
            // Explicit Retry cannot shorten a server cooldown.
        }
        guard commit(candidate) else { return }
        enqueueError = nil
        scheduleReplay()
    }

    func cancelReplay() {
        replayID = nil
        replayTask?.cancel()
        replayTask = nil
    }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sesh-outbox.json")
    }

    @discardableResult private func commit(_ candidate: [OutboxOperation]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidate)
            try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            queue = candidate
            storageError = nil
            return true
        } catch {
            storageError = "Unsent actions could not be saved. Free device storage and try again; existing actions are retained."
            log.error("outbox persistence failed; retaining prior queue")
            return false
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { storageError = nil; return }
        do {
            queue = try JSONDecoder().decode([OutboxOperation].self, from: Data(contentsOf: storageURL))
            storageError = nil
        } catch {
            storageError = "Saved unsent actions could not be read. The original file is preserved; try again after unlocking the device."
        }
    }
}
