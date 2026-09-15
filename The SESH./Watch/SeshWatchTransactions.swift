import Foundation
import SwiftData
import CryptoKit

private enum SeshWatchConflict: LocalizedError {
    case rejected(String)
    var errorDescription: String? { if case .rejected(let message) = self { return message }; return nil }
}
@MainActor enum SeshWatchTransactions {
    private struct Applied: Codable { var digest: String; var receipt: SeshWatchReceipt }
    static func apply(_ command: SeshWatchCommand, epoch: UUID, session: AppSession) throws -> SeshWatchReceipt {
        try command.validate()
        guard command.epoch == epoch else { throw SeshWatchError.invalid("This action belongs to an earlier iPhone journal. Sync again.") }
        let store = SeshDataStore.shared
        guard !store.isEphemeral, !store.isUnavailable, let container = store.container else { throw SeshWatchError.invalid("iPhone storage is unavailable. Keep this action queued and unlock iPhone to retry.") }
        let context = ModelContext(container); context.autosaveEnabled = false
        let key = "watch-receipts/" + epoch.uuidString + "/" + command.id.uuidString
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(command)).map { String(format: "%02x", $0) }.joined()
        let descriptor = FetchDescriptor<SDRecord>(predicate: #Predicate { $0.key == key })
        if let existing = try context.fetch(descriptor).first {
            let applied = try JSONDecoder().decode(Applied.self, from: existing.payload)
            guard applied.digest == digest else { throw SeshWatchError.invalid("This action's identifier was reused with different data. Review it on Apple Watch.") }
            return applied.receipt
        }
        let collection = "watch-receipts"
        guard try context.fetchCount(FetchDescriptor<SDRecord>(predicate: #Predicate { $0.collection == collection })) < 20_000 else {
            throw SeshWatchError.invalid("Watch receipt storage is full. Existing queued actions are preserved.")
        }
        var rejection: String?
        do {
        switch command.kind {
        case .log:
            let id = command.id, log = command.log!
            guard try context.fetch(FetchDescriptor<SDJournalEntry>(predicate: #Predicate { $0.id == id })).isEmpty else { throw SeshWatchConflict.rejected("A record already has this identifier. Review the journal on iPhone.") }
            var entry = JournalEntry(id: id, date: log.date, strain: log.strain, method: log.method, rating: log.rating,
                mood: log.mood.flatMap(Mood.init(rawValue:)), notes: log.notes)
            entry.durationMinutes = log.durationMinutes; entry.amount = log.amount; entry.amountUnit = log.amount == nil ? nil : log.unit
            entry.moodBefore = log.moodBefore; entry.moodAfter = log.moodAfter; entry.sessionTags = log.tags.isEmpty ? nil : log.tags
            if let purchaseID = log.purchaseID, let amount = log.amount {
                let purchaseKey = "purchases/" + purchaseID.uuidString
                guard let record = try context.fetch(FetchDescriptor<SDRecord>(predicate: #Predicate { $0.key == purchaseKey })).first,
                      var purchase = try? JSONDecoder().decode(Purchase.self, from: record.payload),
                      purchase.unit == log.unit, purchase.strain.caseInsensitiveCompare(log.strain) == .orderedSame,
                      purchase.amount.isFinite, purchase.used.isFinite, purchase.amount > 0, purchase.used >= 0, purchase.used <= purchase.amount,
                      amount <= purchase.remaining else {
                    throw SeshWatchConflict.rejected("Stash changed or has insufficient quantity. Refresh, then review the log before resending.")
                }
                purchase.used = min(purchase.amount, purchase.used + amount)
                record.payload = try encoder.encode(purchase)
            }
            context.insert(SDJournalEntry(entry))
        case .thought:
            let id = command.id
            guard try context.fetch(FetchDescriptor<SDThought>(predicate: #Predicate { $0.id == id })).isEmpty else { throw SeshWatchConflict.rejected("This thought identifier is already present.") }
            context.insert(SDThought(HighThought(id: id, date: command.createdAt, text: command.text!, visibilityRaw: PostVisibility.privatePost.rawValue)))
        case .favorite:
            let id = command.recordID!
            guard let record = try context.fetch(FetchDescriptor<SDJournalEntry>(predicate: #Predicate { $0.id == id })).first else { throw SeshWatchConflict.rejected("This journal entry was removed on iPhone.") }
            if command.flag == true { record.categoryRaw = SeshCategory.personalFaves.rawValue }
            else if record.categoryRaw == SeshCategory.personalFaves.rawValue { record.categoryRaw = nil }
        case .pin:
            let id = command.recordID!
            guard try context.fetchCount(FetchDescriptor<SDJournalEntry>(predicate: #Predicate { $0.id == id })) > 0 else { throw SeshWatchConflict.rejected("This journal entry was removed on iPhone.") }
            guard JournalStudioStore.shared.change({ if command.flag == true { $0.pinned.insert(id) } else { $0.pinned.remove(id) } }) else {
                throw SeshWatchError.invalid("Journal Studio could not save this pin. Unlock iPhone and retry.")
            }
        case .addStash:
            let row = command.stash!, purchaseKey = "purchases/" + command.id.uuidString
            guard try context.fetch(FetchDescriptor<SDRecord>(predicate: #Predicate { $0.key == purchaseKey })).isEmpty else { throw SeshWatchConflict.rejected("This stash identifier already exists.") }
            let purchase = Purchase(id: row.id, date: row.date, strain: row.strain, amount: row.amount, unit: row.unit, cost: row.cost, used: row.used)
            context.insert(SDRecord(key: purchaseKey, collection: "purchases", date: row.date, payload: try encoder.encode(purchase)))
        case .addGoal:
            let row = command.goal!
            if let existing = session.goals.first(where: { $0.id == command.id }) {
                guard existing.title == row.title, existing.kind.rawValue == row.kind, existing.target == row.target,
                      existing.createdAt == command.createdAt, existing.note == row.note, existing.active == row.active else {
                    throw SeshWatchConflict.rejected("The saved goal changed. Review it on iPhone before creating another.")
                }
            } else {
                guard let kind = GoalKind(rawValue: row.kind), session.addGoal(SeshGoal(id: row.id, kind: kind, title: row.title, target: row.target,
                    unit: kind == .smokeLess ? "sessions/week" : kind == .spendLess ? "$/week" : nil, createdAt: command.createdAt, note: row.note, active: row.active)) else {
                    throw SeshWatchError.invalid("The personal goal could not be saved on iPhone. Open Goals and retry.")
                }
            }
        case .goalActive:
            guard var goal = session.goals.first(where: { $0.id == command.recordID }) else { throw SeshWatchConflict.rejected("This goal was removed on iPhone.") }
            let expected = goal; goal.active = command.flag!
            if goal != expected, !session.updateGoal(goal, replacing: expected) { throw SeshWatchError.invalid("This goal could not be updated. Review it on iPhone.") }
        }
        } catch let conflict as SeshWatchConflict {
            context.rollback(); rejection = conflict.localizedDescription
        }
        // Terminal conflicts receive a durable receipt too, so this UUID can
        // never succeed later merely because a deleted target was recreated.
        let receipt = SeshWatchReceipt(commandID: command.id, epoch: epoch, accepted: rejection == nil, retryable: false,
            message: rejection ?? "Saved privately on iPhone")
        context.insert(SDRecord(key: key, collection: collection, date: Date(), payload: try encoder.encode(Applied(digest: digest, receipt: receipt))))
        do { try context.save() } catch { context.rollback(); throw SeshWatchError.invalid("iPhone could not commit this action. Your watch copy is still queued. Free storage or unlock iPhone and retry.") }
        if rejection == nil { session.watchDidCommit() }
        return receipt
    }
}
