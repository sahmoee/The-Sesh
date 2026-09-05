import Foundation

// Only transport/account edges are doubles; policies and outbox are compiled from app source.
@MainActor final class SeshAuth { static let shared = SeshAuth(); var uid: String? = "test-owner" }
@MainActor final class ConnectivityMonitor { static let shared = ConnectivityMonitor(); var pathSatisfied = true }
@MainActor final class PrivacySettings { static let shared = PrivacySettings(); var shareActivity = true; var shareStrainDetails = true }
enum APIError: Error { case network, rateLimited, notFound, invalidRequest, server(Int), cancelled, cooldown(TimeInterval)
    var retryDelay: TimeInterval? { if case .cooldown(let delay) = self { return delay }; return nil }
}
@MainActor struct SeshAPI {
    static var calls = 0
    static var results: [Result<Void, APIError>] = []
    static var suspended: CheckedContinuation<Result<Void, APIError>, Never>?
    static var suspendNext = false
    func postRaw(_ path: String, body: Data, idempotencyKey: String?) async -> Result<Void, APIError> {
        Self.calls += 1
        if Self.suspendNext {
            Self.suspendNext = false
            return await withCheckedContinuation { Self.suspended = $0 }
        }
        return Self.results.isEmpty ? .success(()) : Self.results.removeFirst()
    }
}

@main struct SeshReliabilityChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAILED: \(name)") }
            count += 1
        }
        let policy = SeshReliabilityPolicy.self
        for invalid in ["", "NaN", "inf", "-2", "9999999999999999", "later"] {
            check(policy.retryAfter(invalid) == nil, "invalid retry \(invalid)")
        }
        check(policy.retryAfter(" 12.5 ") == 12.5, "fractional retry seconds")
        check(policy.retryAfter("0") == 0, "zero cooldown")
        check(policy.serverDate("2026-09-05T02:00:00.123Z") != nil, "fractional server date")
        check(policy.serverDate("2026-09-05T02:00:00Z") != nil, "plain server date")
        check(policy.serverDate("not a date") == nil, "invalid server date")
        let epoch = Date(timeIntervalSince1970: 0)
        check(policy.retryAfter("Thu, 01 Jan 1970 00:01:00 GMT", now: epoch) == 60, "HTTP-date retry")
        check(policy.retryAfter("Thu, 01 Jan 1970 00:00:00 GMT", now: epoch.addingTimeInterval(60)) == 0, "past HTTP date")
        check(policy.transient(URLError(.timedOut)), "transient timeout")
        check(!policy.transient(URLError(.cancelled)), "cancellation permanent")
        check(!policy.transient(URLError(.serverCertificateUntrusted)), "certificate no retry")
        check(!policy.transient(NSError(domain: "other", code: 1)), "nontransport no retry")
        check(policy.pathSegment("a/b?#") == "a%2Fb%3F%23", "path segments")
        check(policy.pathSegment("room good") == "room%20good", "path spaces")
        for path in ["https://example.com/api/send", "/private", "/api/../secret", "/api/%2e%2e/secret", "/api/x?token=x", "/api/x#y", "/api/\\x"] {
            check(!policy.validOutboxPath(path), "invalid outbox path")
        }
        check(policy.validOutboxPath("/api/rooms/room%20name/messages"), "valid local API path")
        check(policy.ownerMatches("A", current: "A"), "same owner")
        check(!policy.ownerMatches("A", current: "B"), "foreign owner")
        check(!policy.ownerMatches(nil, current: "A"), "legacy owner not adopted")
        check(!policy.ownerMatches("", current: ""), "empty owner")
        let detailedActivity = Data("{\"detail\":\"private note\"}".utf8)
        check(!policy.mayReplayActivity(detailedActivity, sharesActivity: false, sharesDetails: true), "revoked activity blocked")
        check(!policy.mayReplayActivity(detailedActivity, sharesActivity: true, sharesDetails: false), "revoked details blocked")
        check(policy.mayReplayActivity(Data("{\"detail\":\"\"}".utf8), sharesActivity: true, sharesDetails: false), "detail-free activity allowed")
        check(policy.imagePixels(.nan) == 600, "NaN pixels")
        check(policy.imagePixels(.infinity) == 600, "infinite pixels")
        check(policy.imagePixels(-1) == 600, "negative pixels")
        check(policy.imagePixels(1) == 64, "minimum pixels")
        check(policy.imagePixels(99_999) == 2048, "maximum pixels")
        let imageURL = URL(string: "https://example.com/image.png")!
        check(policy.imageKey(imageURL, pixels: 64) != policy.imageKey(imageURL, pixels: 600), "image variant cache key")
        check(policy.acceptsHTTPImage(status: 200, mime: "image/png", bytes: 8), "valid image response")
        check(!policy.acceptsHTTPImage(status: 404, mime: "image/png", bytes: 8), "reject image 404")
        check(!policy.acceptsHTTPImage(status: 200, mime: "text/html", bytes: 8), "reject html image")
        check(!policy.acceptsHTTPImage(status: 200, mime: "image/png", bytes: 0), "reject empty image")
        check(!policy.acceptsHTTPImage(status: 200, mime: nil, bytes: policy.maxImageBytes + 1), "image byte cap")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sesh-reliability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func outbox(_ name: String, owner: @escaping @MainActor () -> String? = { "A" }) -> OfflineOutbox {
            OfflineOutbox(storageURL: directory.appendingPathComponent(name + ".json"), owner: owner, online: { true }, automaticallyReplay: false)
        }
        let body = Data("{}".utf8)
        let box = outbox("dedupe")
        check(box.enqueue(path: "/api/activity", body: body, key: "one") == "one", "durable enqueue")
        check(box.enqueue(path: "/api/activity", body: body, key: "one") == "one", "same duplicate returns original")
        check(box.pendingCount == 1, "duplicate does not append")
        check(box.enqueue(path: "/api/other", body: body, key: "one") == nil, "conflicting duplicate rejected")
        check(box.queue[0].ownerID == "A", "owner persisted")
        let reloaded = outbox("dedupe")
        check(reloaded.pendingCount == 1 && reloaded.queue[0].ownerID == "A", "owner roundtrip")
        check(box.enqueue(path: "/api/activity", body: Data("not-json".utf8)) == nil, "invalid JSON rejected")
        let anonymous = outbox("anonymous", owner: { nil })
        check(anonymous.enqueue(path: "/api/activity", body: body) == nil && anonymous.pendingCount == 0, "unverified sends preserve composer instead of stranding unowned work")

        let full = outbox("capacity")
        for i in 0..<OfflineOutbox.maxQueued { _ = full.enqueue(path: "/api/activity", body: body, key: "key-\(i)") }
        check(full.enqueue(path: "/api/activity", body: body, key: "overflow") == nil, "overflow rejected")
        check(full.pendingCount == 500 && full.queue.first?.id == "key-0" && full.queue.last?.id == "key-499", "oldest/newest retained")
        check(full.statusMessage != nil, "overflow surfaced")

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("not valid saved JSON".utf8)
        try corrupt.write(to: corruptURL)
        let broken = outbox("corrupt")
        check(broken.storageError != nil, "corruption visible")
        check(broken.enqueue(path: "/api/activity", body: body) == nil, "corrupt file not overwritten")
        let retainedCorrupt = try Data(contentsOf: corruptURL)
        check(retainedCorrupt == corrupt, "corrupt bytes retained")

        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try body.write(to: blockedParent)
        let diskError = OfflineOutbox(storageURL: blockedParent.appendingPathComponent("queue.json"), owner: { "A" }, automaticallyReplay: false)
        check(diskError.enqueue(path: "/api/activity", body: body) == nil && diskError.pendingCount == 0, "failed persistence not optimistic success")

        var current: String? = "A"
        let accounts = outbox("accounts", owner: { current })
        _ = accounts.enqueue(path: "/api/activity", body: body, key: "private-A")
        current = "B"
        SeshAPI.calls = 0
        accounts.scheduleReplay()
        await Task.yield()
        check(SeshAPI.calls == 0 && accounts.heldCount == 1, "foreign account never replays")
        check(!accounts.canRetry, "foreign account cannot adopt via retry")
        let legacyURL = directory.appendingPathComponent("legacy.json")
        try JSONEncoder().encode([OutboxOperation(id: "legacy", path: "/api/activity", body: body, queuedAt: Date())]).write(to: legacyURL)
        let legacy = outbox("legacy")
        check(legacy.heldCount == 1 && !legacy.canRetry, "legacy unowned data held")

        let permanent = outbox("permanent")
        _ = permanent.enqueue(path: "/api/activity", body: body, key: "bad")
        SeshAPI.results = [.failure(.invalidRequest)]
        permanent.scheduleReplay()
        for _ in 0..<20 { await Task.yield() }
        check(permanent.pendingCount == 1 && permanent.queue.first?.heldReason == "invalidRequest", "permanent failure held not erased")

        let exhaustedURL = directory.appendingPathComponent("exhausted.json")
        try JSONEncoder().encode([OutboxOperation(id: "exhausted", path: "/api/activity", body: body, queuedAt: Date(), attempts: Int.max, ownerID: "A")]).write(to: exhaustedURL)
        let exhausted = outbox("exhausted")
        SeshAPI.results = [.failure(.network)]
        exhausted.scheduleReplay()
        for _ in 0..<20 { await Task.yield() }
        check(exhausted.pendingCount == 1 && exhausted.queue[0].attempts == 8, "corrupt attempts clamped without overflow")
        check(exhausted.queue[0].heldReason == "retryLimit", "retry limit retains action")

        let privacy = outbox("privacy")
        _ = privacy.enqueue(path: "/api/activity", body: detailedActivity, key: "private")
        PrivacySettings.shared.shareStrainDetails = false
        let callsBeforePrivacy = SeshAPI.calls
        privacy.scheduleReplay()
        for _ in 0..<20 { await Task.yield() }
        check(SeshAPI.calls == callsBeforePrivacy && privacy.queue[0].heldReason == "privacyChanged", "revoked queued privacy prevents transport")
        PrivacySettings.shared.shareStrainDetails = true

        let cooldown = outbox("cooldown")
        _ = cooldown.enqueue(path: "/api/activity", body: body, key: "later")
        SeshAPI.results = [.failure(.cooldown(45))]
        cooldown.scheduleReplay()
        for _ in 0..<20 { await Task.yield() }
        cooldown.cancelReplay()
        let deadline = cooldown.queue[0].retryAt!
        check(deadline.timeIntervalSinceNow > 40, "server cooldown stored as minimum")
        cooldown.retryHeldOperations()
        cooldown.cancelReplay()
        check(cooldown.queue[0].retryAt == deadline, "manual retry preserves server deadline")

        let cancelled = outbox("cancel")
        _ = cancelled.enqueue(path: "/api/activity", body: body, key: "first")
        SeshAPI.suspendNext = true
        cancelled.scheduleReplay()
        for _ in 0..<20 where SeshAPI.suspended == nil { await Task.yield() }
        cancelled.cancelReplay()
        _ = cancelled.enqueue(path: "/api/activity", body: body, key: "second")
        SeshAPI.suspended?.resume(returning: .success(())); SeshAPI.suspended = nil
        for _ in 0..<20 { await Task.yield() }
        check(cancelled.pendingCount == 2, "cancelled old completion does not dequeue")
        check(cancelled.queue.map(\.id) == ["first", "second"], "queue identity preserved after cancel")
        cancelled.scheduleReplay()
        for _ in 0..<40 { await Task.yield() }
        check(cancelled.pendingCount == 0, "new generation replays retained work")
        print("\(count) Sesh policy and actual-outbox checks passed; isolated fixtures, no live network or simulator.")
    }
}
