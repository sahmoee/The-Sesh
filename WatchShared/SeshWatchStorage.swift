import Foundation

/// Local-only private cache/outbox. Writes publish only after atomic commit.
nonisolated final class SeshWatchFile<Value: Codable> {
    let url: URL
    var blocked = false
    private let maximum = 2 * 1_024 * 1_024
    init(url: URL) { self.url = url }
    func load() throws -> Value? {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { blocked = false; return nil }
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, (1...maximum).contains(size) else { throw SeshWatchError.invalid("The saved watch data is unreadable. Your original file is preserved.") }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: maximum + 1) ?? Data()
            let result = try SeshWatchContract.decode(Value.self, data, maximum: maximum)
            blocked = false; return result
        } catch { blocked = true; throw error }
    }
    func write(_ value: Value) throws {
        guard !blocked else { throw SeshWatchError.invalid("Saved watch data could not be read. Retry loading before editing.") }
        let data = try SeshWatchContract.encode(value, maximum: maximum)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    func erase() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        blocked = false
    }
}
nonisolated struct SeshWatchPending: Codable, Identifiable, Equatable, Sendable {
    var command: SeshWatchCommand; var message: String? = nil; var retryable = true
    var id: UUID { command.id }
}
nonisolated struct SeshWatchLocalState: Codable, Sendable {
    var version = 1
    var snapshot: SeshWatchSnapshot? = nil
    var pending: [SeshWatchPending] = []
    var draft = SeshWatchLog()
    var amountDraft = ""
    var thoughtDraft = ""
    var stashDraft = SeshWatchStashDraft()
    var goalDraft = SeshWatchGoalDraft()
    var timerStarted: Date? = nil
    var haptics = true
    var hidePrivateText = false
    var lastReceipt: SeshWatchReceipt? = nil
    mutating func enqueue(_ command: SeshWatchCommand) throws {
        try command.validate()
        guard snapshot?.enabled == true, snapshot?.epoch == command.epoch else { throw SeshWatchError.invalid("Sync with your iPhone before saving.") }
        guard pending.count < SeshWatchContract.maximumQueue else { throw SeshWatchError.invalid("100 actions are waiting. Sync with iPhone before adding another; nothing was removed.") }
        guard !pending.contains(where: { $0.id == command.id }) else { return }
        pending.append(SeshWatchPending(command: command))
    }
    mutating func receive(_ receipt: SeshWatchReceipt) throws {
        try receipt.validate()
        guard let index = pending.firstIndex(where: { $0.id == receipt.commandID && $0.command.epoch == receipt.epoch }) else { return }
        if receipt.accepted { pending.remove(at: index) }
        else { pending[index].message = receipt.message; pending[index].retryable = receipt.retryable }
        lastReceipt = receipt
    }
    mutating func receive(_ next: SeshWatchSnapshot, allowNewEpoch: Bool = false) throws {
        try next.validate()
        if let previous = snapshot {
            if previous.epoch == next.epoch, next.revision <= previous.revision { return }
            if previous.epoch != next.epoch, !allowNewEpoch { return }
        }
        if let previous = snapshot, previous.epoch != next.epoch {
            // Explicit phone reset/re-pair invalidates old private cached data and commands.
            pending.removeAll(); draft = SeshWatchLog(); amountDraft = ""; thoughtDraft = ""; stashDraft = SeshWatchStashDraft(); goalDraft = SeshWatchGoalDraft(); timerStarted = nil; lastReceipt = nil
        }
        snapshot = next
    }
    func validate() throws {
        guard version == 1, pending.count <= SeshWatchContract.maximumQueue, Set(pending.map(\.id)).count == pending.count,
              timerStarted == nil || SeshWatchContract.date(timerStarted!) else { throw SeshWatchError.invalid("Saved watch data needs recovery.") }
        try snapshot?.validate(); try lastReceipt?.validate()
        for row in pending { try row.command.validate(); guard row.message == nil || SeshWatchContract.text(row.message!, maximum: 500) else { throw SeshWatchError.invalid("Invalid queued response.") } }
        // An unfinished draft can have an empty strain, but never unchecked dimensions/text.
        var checked = draft; if checked.strain.isEmpty { checked.strain = "Draft" }; if checked.amount == nil { checked.purchaseID = nil }; try checked.validate()
        guard SeshWatchContract.text(amountDraft, maximum: 40), SeshWatchContract.text(thoughtDraft, maximum: 2_000) else { throw SeshWatchError.invalid("Draft text exceeds its limit.") }
        try stashDraft.validate(); try goalDraft.validate()
    }
}

/// Delegate callbacks count work before hopping to the main actor, so watch
/// background completion cannot race an accepted but not-yet-persisted receipt.
nonisolated final class SeshWatchDeliveryTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func begin() { lock.lock(); count += 1; lock.unlock() }
    func end() { lock.lock(); count = max(0, count - 1); lock.unlock() }
    var idle: Bool { lock.lock(); defer { lock.unlock() }; return count == 0 }
}

nonisolated struct SeshWatchStashDraft: Codable, Equatable, Sendable {
    var name = "", amount = "", cost = "", unit = "g"
    func validate() throws {
        guard SeshWatchContract.text(name, maximum: 120), SeshWatchContract.text(amount, maximum: 40), SeshWatchContract.text(cost, maximum: 40), SeshWatchContract.units.contains(unit) else { throw SeshWatchError.invalid("Review the unfinished stash fields.") }
    }
}
nonisolated struct SeshWatchGoalDraft: Codable, Equatable, Sendable {
    var title = "", kind = "Custom", target = "", note = ""
    func validate() throws {
        guard SeshWatchContract.text(title, maximum: 120), SeshWatchContract.text(target, maximum: 40), SeshWatchContract.text(note, maximum: 500), SeshWatchContract.text(kind, maximum: 40) else { throw SeshWatchError.invalid("Review the unfinished goal fields.") }
    }
}
/// Only the current foreground request may authorize an epoch change.
nonisolated struct SeshWatchRequestGate: Sendable {
    private(set) var current: UUID?
    mutating func begin() -> UUID { let id = UUID(); current = id; return id }
    mutating func finish(_ id: UUID) -> Bool {
        guard current == id else { return false }; current = nil; return true
    }
    mutating func cancel() { current = nil }
}
