import Foundation
import SwiftData
import SwiftUI

// Domain-only compilation adapter: the production domain file references these
// theme colors. No UI or production application storage is constructed here.
enum SeshStage: String { case pickingStrain }
enum Palette {
    static let gold = Color.yellow, green = Color.green, greenBright = Color.green
    static let goldDeep = Color.orange, moodAngry = Color.red
}

/// Actual production SDJournalEntry, SDThought, SDRecord and domain payloads,
/// in a unique disposable store. This does not instantiate SeshDataStore.shared.
@main enum WatchPersistenceChecks {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
        let root = FileManager.default.temporaryDirectory.appending(path: "sesh-watch-models-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(SeshSchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: root.appending(path: "fixture.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let main = container.mainContext; main.autosaveEnabled = false
        let id = UUID(), purchaseID = UUID()
        let journal = JournalEntry(id: id, date: Date(), strain: "Fixture", method: "Joint", rating: 5, mood: .chill, notes: "Private fixture")
        main.insert(SDJournalEntry(journal))
        let purchase = Purchase(id: purchaseID, date: Date(), strain: "Fixture", amount: 5, unit: "g", cost: 20, used: 0)
        let key = "purchases/" + purchaseID.uuidString
        main.insert(SDRecord(key: key, collection: "purchases", date: purchase.date, payload: try JSONEncoder().encode(purchase)))
        try main.save()
        let retained = try main.fetch(FetchDescriptor<SDJournalEntry>()).first!
        let retainedStash = try main.fetch(FetchDescriptor<SDRecord>()).first!
        let transaction = ModelContext(container); transaction.autosaveEnabled = false
        let edited = try transaction.fetch(FetchDescriptor<SDJournalEntry>()).first!
        edited.categoryRaw = SeshCategory.personalFaves.rawValue
        let stash = try transaction.fetch(FetchDescriptor<SDRecord>()).first!
        var consumed = try JSONDecoder().decode(Purchase.self, from: stash.payload)
        consumed.used = 0.5; stash.payload = try JSONEncoder().encode(consumed)
        let receiptKey = "watch-receipts/fixture/" + UUID().uuidString
        transaction.insert(SDRecord(key: receiptKey, collection: "watch-receipts", date: Date(), payload: Data("receipt".utf8)))
        try transaction.save()
        let refetched = try main.fetch(FetchDescriptor<SDJournalEntry>()).first!
        check(refetched.categoryRaw == SeshCategory.personalFaves.rawValue, "Main-context refetch sees private-context favorite")
        check(retained.categoryRaw == SeshCategory.personalFaves.rawValue, "Retained main-context row updates")
        let allRecords = try main.fetch(FetchDescriptor<SDRecord>())
        let reloadedStash = try JSONDecoder().decode(Purchase.self, from: allRecords.first { $0.key == key }!.payload)
        check(reloadedStash.used == 0.5 && reloadedStash.remaining == 4.5, "Main refetch sees stash deduction")
        let retainedValue = try JSONDecoder().decode(Purchase.self, from: retainedStash.payload)
        check(retainedValue.used == 0.5, "Retained stash payload updates")
        check(allRecords.contains { $0.key == receiptKey }, "Receipt durable with matching mutation")
        let rollback = ModelContext(container); rollback.autosaveEnabled = false
        let uncommitted = try rollback.fetch(FetchDescriptor<SDJournalEntry>()).first!
        uncommitted.notes = "Must not survive"
        rollback.insert(SDThought(HighThought(id: UUID(), date: Date(), text: "Must not survive", visibilityRaw: PostVisibility.privatePost.rawValue)))
        rollback.rollback()
        let afterRollback = try main.fetch(FetchDescriptor<SDJournalEntry>()).first!
        let thoughtCount = try main.fetchCount(FetchDescriptor<SDThought>())
        check(afterRollback.notes == "Private fixture", "Rollback does not leak partial notes")
        check(thoughtCount == 0, "Rollback does not leave a thought")
        let second = ModelContext(container)
        let receipt = try second.fetch(FetchDescriptor<SDRecord>(predicate: #Predicate { $0.key == receiptKey }))
        check(receipt.count == 1 && receipt[0].payload == Data("receipt".utf8), "New context reads one durable receipt identity")
        check(refetched.asStruct.id == id && refetched.asStruct.notes == journal.notes, "Domain identity and private notes remain compatible")
        let privateThought = HighThought(id: UUID(), date: Date(), text: "Private", visibilityRaw: PostVisibility.privatePost.rawValue)
        let record = SDThought(privateThought)
        check(record.asStruct.visibility == .privatePost, "Watch thought resolves to private visibility")
        check(SeshSchemaV1.versionIdentifier == Schema.Version(1, 2, 0), "No existing SwiftData migration required")
        print("Watch production-model persistence checks passed: \(checks)")
    }
}
