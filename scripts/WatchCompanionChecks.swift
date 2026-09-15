import Foundation

/// Production wire/storage policy only. Uses synthetic data and a unique temporary folder.
@main enum WatchCompanionChecks {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); count += 1 }
        func rejects(_ label: String, _ body: () throws -> Void) { do { try body(); preconditionFailure(label) } catch { count += 1 } }
        let now = Date(timeIntervalSince1970: 1_789_430_400), epoch = UUID(), nextEpoch = UUID()
        let log = SeshWatchLog(date: now, strain: "Fixture strain", amount: 0.5, notes: "Private fixture")
        try log.validate(); count += 1
        for bad in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -1, 0, 100_001] {
            var invalid = log; invalid.amount = bad
            rejects("Reject invalid amount") { try invalid.validate() }
        }
        for bad in [Double.nan, .infinity, -1, 0, 11] {
            var invalid = log; invalid.rating = bad
            rejects("Reject invalid rating") { try invalid.validate() }
        }
        for bad in ["1abc", "1,000", "-1", "1.", ".2", "1e2", "nan", "∞", ""] {
            check(SeshWatchContract.decimal(bad, locale: Locale(identifier: "en_US")) == nil, "Strict full decimal")
        }
        check(SeshWatchContract.decimal("0.5", locale: Locale(identifier: "en_US")) == 0.5, "US decimal")
        check(SeshWatchContract.decimal("0,5", locale: Locale(identifier: "fr_FR")) == 0.5, "Localized decimal")
        check(SeshWatchContract.elapsed(start: now, now: now.addingTimeInterval(-100)) == 0, "Future timer never negative")
        check(SeshWatchContract.elapsed(start: now, now: now.addingTimeInterval(1e100)) == 43_200, "Finite extreme timer clamps safely")
        check(SeshWatchContract.elapsed(start: now, now: now.addingTimeInterval(.infinity)) == 0, "Nonfinite timer safe")
        var invalidDate = log; invalidDate.date = Date(timeIntervalSince1970: 1e100)
        rejects("Imported planning dates are bounded") { try invalidDate.validate() }
        var missingAmount = log; missingAmount.amount = nil; missingAmount.purchaseID = UUID()
        rejects("A deduction needs a positive amount") { try missingAmount.validate() }
        var invalidNotes = log; invalidNotes.notes = String(repeating: "e\u{301}", count: 2_001)
        rejects("Notes bounded by characters and bytes") { try invalidNotes.validate() }
        var invalidTags = log; invalidTags.tags = Array(repeating: "Tag", count: 6)
        rejects("Bound tags") { try invalidTags.validate() }
        let command = SeshWatchCommand(epoch: epoch, createdAt: now, kind: .log, log: log)
        let packet = SeshWatchPacket(command: command)
        let roundtrip = try SeshWatchContract.decode(SeshWatchPacket.self, SeshWatchContract.encode(packet))
        try roundtrip.validate(); check(roundtrip.command == command, "Full log payload round trip")
        var wrongChannel = packet; wrongChannel.channel = "another-app"
        rejects("Reject foreign app packets") { try wrongChannel.validate() }
        var wrongVersion = packet; wrongVersion.version = 9
        rejects("Reject unsupported wire version") { try wrongVersion.validate() }
        rejects("Bound wire decoding") { _ = try SeshWatchContract.decode(SeshWatchPacket.self, Data(repeating: 65, count: 60_001)) }
        rejects("Bound wire encoding") { _ = try SeshWatchContract.encode(String(repeating: "a", count: 60_001)) }
        var snapshot = SeshWatchSnapshot(epoch: epoch, generatedAt: now, revision: 10, name: "Fixture")
        snapshot.entries = [SeshWatchEntry(id: command.id, log: log, favorite: false, pinned: false)]
        var state = SeshWatchLocalState(); try state.receive(snapshot); try state.enqueue(command)
        check(state.pending.count == 1, "Persistable offline queue")
        try state.enqueue(command); check(state.pending.count == 1, "Repeated UUID does not duplicate queue")
        var foreign = command; foreign.epoch = nextEpoch
        rejects("No foreign journal command") { try state.enqueue(foreign) }
        var old = snapshot; old.revision = 9; old.name = "Stale"
        try state.receive(old); check(state.snapshot?.name == "Fixture", "Ignore older same-epoch snapshot")
        old.revision = 10; try state.receive(old); check(state.snapshot?.name == "Fixture", "Ignore equal revision")
        old.revision = 11; try state.receive(old); check(state.snapshot?.name == "Stale", "Accept newer revision")
        check(state.pending.count == 1, "Snapshot does not replace pending action")
        var reset = SeshWatchSnapshot(epoch: nextEpoch, generatedAt: now, revision: 0, name: "Reset")
        try state.receive(reset); check(state.snapshot?.epoch == epoch && state.pending.count == 1, "Unsolicited foreign epoch cannot clear a watch")
        state.draft = log; state.timerStarted = now; state.thoughtDraft = "Private draft"
        try state.receive(reset, allowNewEpoch: true)
        check(state.snapshot?.epoch == nextEpoch && state.snapshot?.revision == 0, "Verified reinstall may begin at revision zero")
        check(state.pending.isEmpty && state.draft.strain.isEmpty && state.timerStarted == nil && state.thoughtDraft.isEmpty, "Verified reset clears old private cache/drafts/outbox")
        try state.receive(snapshot); check(state.snapshot?.epoch == nextEpoch, "Delayed old context cannot restore prior epoch")
        var gate = SeshWatchRequestGate(); let first = gate.begin(), latest = gate.begin()
        check(!gate.finish(first) && gate.current == latest, "Old handshake cannot authorize epoch adoption")
        check(gate.finish(latest) && gate.current == nil, "Only correlated current response completes handshake")
        check(!gate.finish(latest), "Duplicate response no longer trusted")
        let cancelled = gate.begin(); gate.cancel(); check(!gate.finish(cancelled), "Cancelled handshake rejects late response")
        reset.enabled = false; reset.revision = 1; try state.receive(reset)
        var nextCommand = command; nextCommand.epoch = nextEpoch
        rejects("Disabled access cannot enqueue") { try state.enqueue(nextCommand) }
        var queued = SeshWatchLocalState(); try queued.receive(snapshot); try queued.enqueue(command)
        let accepted = SeshWatchReceipt(commandID: command.id, epoch: epoch, accepted: true, retryable: false, message: "Saved privately on iPhone", date: now)
        var foreignAck = accepted; foreignAck.epoch = nextEpoch
        try queued.receive(foreignAck); check(queued.pending.count == 1, "Foreign epoch acknowledgement cannot delete work")
        var unrelated = accepted; unrelated.commandID = UUID()
        try queued.receive(unrelated); check(queued.pending.count == 1, "Unrelated receipt cannot delete work")
        var rejected = accepted; rejected.accepted = false; rejected.message = "Stash changed"
        try queued.receive(rejected); check(queued.pending.count == 1 && queued.pending[0].retryable == false, "Terminal rejection remains reviewable")
        rejected.retryable = true; try queued.receive(rejected)
        check(queued.pending[0].retryable, "Storage failure remains retryable")
        try queued.receive(accepted); check(queued.pending.isEmpty, "Matching acknowledgement removes only matching command")
        try queued.receive(accepted); check(queued.pending.isEmpty, "Duplicate receipt is harmless")
        for _ in 0..<100 { var row = command; row.id = UUID(); try queued.enqueue(row) }
        let ids = queued.pending.map(\.id)
        var overflow = command; overflow.id = UUID()
        rejects("Capacity rejects without eviction") { try queued.enqueue(overflow) }
        check(queued.pending.map(\.id) == ids, "Every queued UUID retained at capacity")
        var duplicate = snapshot; duplicate.entries += duplicate.entries
        rejects("Duplicate snapshot identities rejected") { try duplicate.validate() }
        var malformedGoal = SeshWatchGoal(id: UUID(), title: "Limit", kind: "Smoke less", target: 2.5, actual: nil, note: "", active: true)
        rejects("Session limit must be whole") { try malformedGoal.validate() }
        malformedGoal.target = 0; try malformedGoal.validate(); count += 1
        malformedGoal.kind = "Spend less"; malformedGoal.target = nil
        rejects("Monetary goal needs target") { try malformedGoal.validate() }
        let request = SeshWatchPageRequest(epoch: epoch, area: .history, query: "Fixture")
        var page = SeshWatchPage(request: request, total: 40, nextOffset: 20, entries: snapshot.entries)
        try page.validate(); count += 1
        page.nextOffset = 0; rejects("Page cannot point backward or repeat") { try page.validate() }
        page.nextOffset = 41; rejects("Page cannot exceed total") { try page.validate() }
        var bigQuery = request; bigQuery.query = String(repeating: "a", count: 121)
        rejects("Search query bounded") { try bigQuery.validate() }
        bigQuery = request; bigQuery.offset = Int.max
        rejects("Extreme page offsets rejected") { try bigQuery.validate() }
        var draftState = SeshWatchLocalState(); draftState.draft = missingAmount; draftState.amountDraft = "0."
        draftState.thoughtDraft = "Unfinished thought"; draftState.stashDraft.amount = "1."; draftState.goalDraft.target = "2."
        try draftState.validate(); count += 1
        let folder = FileManager.default.temporaryDirectory.appending(path: "sesh-watch-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SeshWatchFile<SeshWatchLocalState>(url: folder.appending(path: "nested/state.json"))
        let firstLoad = try file.load(); check(firstLoad == nil, "Absent state is first launch")
        try file.write(draftState)
        let restored = try file.load()!
        check(restored.amountDraft == "0." && restored.stashDraft.amount == "1." && restored.goalDraft.target == "2.", "Incomplete numeric drafts survive restart unchanged")
        check(restored.thoughtDraft == "Unfinished thought" && restored.draft.purchaseID == missingAmount.purchaseID, "Private draft and explicit deduction survive restart")
        try Data("broken".utf8).write(to: file.url)
        rejects("Corrupt state preserved") { _ = try file.load() }
        rejects("Corrupt state blocks overwrite") { try file.write(SeshWatchLocalState()) }
        let originalBytes = try Data(contentsOf: file.url); check(originalBytes == Data("broken".utf8), "Original corrupt bytes preserved")
        try file.erase(); check(!file.blocked && !FileManager.default.fileExists(atPath: file.url.path), "Explicit reset erases corrupt state")
        try file.write(queued); let reloaded = try file.load()!
        check(reloaded.pending.map(\.id) == ids, "All one hundred actions durable")
        let link = SeshWatchFile<SeshWatchLocalState>(url: folder.appending(path: "link.json"))
        try FileManager.default.createSymbolicLink(at: link.url, withDestinationURL: file.url)
        rejects("Symlink cache rejected") { _ = try link.load() }
        let tracker = SeshWatchDeliveryTracker(); check(tracker.idle, "Idle delegate tracker")
        tracker.begin(); tracker.begin(); tracker.end(); check(!tracker.idle, "Outstanding actor writes keep background work active")
        tracker.end(); check(tracker.idle, "Background completion waits for every accepted callback")
        print("Watch companion checks passed: \(count)")
    }
}
