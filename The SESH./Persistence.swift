//
//  Persistence.swift
//  The SESH
//
//  SwiftData persistence layer. The app's domain models stay as Codable structs
//  (JournalEntry / HighThought) so every view, stat, export, and the
//  iCloud sync keep working unchanged. This file adds a real SwiftData store
//  *underneath* that — @Model classes, a ModelContainer, indexed fetches, and a
//  schema version for migrations — and converts between the two representations
//  at the boundary.
//
//  Why a repository instead of making the domain types @Model directly:
//   - SwiftData @Model types are reference types and can't be Codable structs,
//     which the export, comparison, and conflict-merge code all rely on.
//   - Keeping the boundary here means the 9 files that use JournalEntry never
//     change, and we still get on-disk SwiftData with migration support.
//

import Foundation
import SwiftData
import os

// MARK: - @Model records (on-disk representation)

@Model
final class SDJournalEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var strain: String
    var extraStrains: [String]?
    var method: String
    var rating: Double
    var moodRaw: String?
    var smokeAgainRaw: String?
    var categoryRaw: String?
    var customCategory: String?
    var notes: String
    var price: Double?
    var photoName: String?
    var sessionType: String?
    var sessionTags: [String]?
    var champion: String?
    var durationMinutes: Int?
    var companions: [String]?
    var effects: [String]?
    var attachedThoughtID: UUID?
    var moodBefore: Int?
    var moodAfter: Int?
    var amount: Double?
    var amountUnit: String?

    init(_ e: JournalEntry) {
        id = e.id; date = e.date; strain = e.strain; extraStrains = e.extraStrains; method = e.method; rating = e.rating
        moodRaw = e.mood?.rawValue; smokeAgainRaw = e.smokeAgain?.rawValue
        categoryRaw = e.category?.rawValue; customCategory = e.customCategory; notes = e.notes; price = e.price
        photoName = e.photoName; sessionType = e.sessionType; sessionTags = e.sessionTags; champion = e.champion; durationMinutes = e.durationMinutes
        companions = e.companions; effects = e.effects; attachedThoughtID = e.attachedThoughtID
        moodBefore = e.moodBefore; moodAfter = e.moodAfter; amount = e.amount; amountUnit = e.amountUnit
    }

    /// Update this record in place from a struct (edit flow).
    func apply(_ e: JournalEntry) {
        date = e.date; strain = e.strain; extraStrains = e.extraStrains; method = e.method; rating = e.rating
        moodRaw = e.mood?.rawValue; smokeAgainRaw = e.smokeAgain?.rawValue
        categoryRaw = e.category?.rawValue; customCategory = e.customCategory; notes = e.notes; price = e.price
        photoName = e.photoName; sessionType = e.sessionType; sessionTags = e.sessionTags; champion = e.champion; durationMinutes = e.durationMinutes
        companions = e.companions; effects = e.effects; attachedThoughtID = e.attachedThoughtID
        moodBefore = e.moodBefore; moodAfter = e.moodAfter; amount = e.amount; amountUnit = e.amountUnit
    }

    var asStruct: JournalEntry {
        JournalEntry(
            id: id, date: date, strain: strain, extraStrains: extraStrains, method: method, rating: rating,
            mood: moodRaw.flatMap(Mood.init(rawValue:)),
            smokeAgain: smokeAgainRaw.flatMap(SmokeAgain.init(rawValue:)),
            category: categoryRaw.flatMap { SeshCategory(rawValue: SeshCategory.migrate($0)) },
            customCategory: customCategory,
            notes: notes, price: price, photoName: photoName,
            sessionType: sessionType, sessionTags: sessionTags, champion: champion, durationMinutes: durationMinutes,
            companions: companions, effects: effects, attachedThoughtID: attachedThoughtID,
            moodBefore: moodBefore, moodAfter: moodAfter, amount: amount, amountUnit: amountUnit)
    }
}

@Model
final class SDThought {
    @Attribute(.unique) var id: UUID
    var date: Date
    var text: String
    var isFavorite: Bool
    var tagRaw: String?
    var highlighted: Bool
    var visibilityRaw: String?

    init(_ t: HighThought) {
        id = t.id; date = t.date; text = t.text; isFavorite = t.isFavorite
        tagRaw = t.tag?.rawValue; highlighted = t.highlighted; visibilityRaw = t.visibilityRaw
    }
    func apply(_ t: HighThought) {
        date = t.date; text = t.text; isFavorite = t.isFavorite
        tagRaw = t.tag?.rawValue; highlighted = t.highlighted; visibilityRaw = t.visibilityRaw
    }
    var asStruct: HighThought {
        HighThought(id: id, date: date, text: text, isFavorite: isFavorite,
                    tag: tagRaw.flatMap(ThoughtTag.init(rawValue:)), highlighted: highlighted, visibilityRaw: visibilityRaw)
    }
}


// MARK: - Schema & versioning (for migrations)

enum SeshSchemaV1: VersionedSchema {
    // Bumped to 1.1.0 when optional columns (sessionTags, champion on entries;
    // visibilityRaw on thoughts) were added. They're all OPTIONAL, so SwiftData
    // performs an automatic lightweight migration — but the version identifier
    // must change for SwiftData to recognize the new shape and migrate the
    // existing on-disk store instead of throwing. Keeping it at 1.0.0 while the
    // model shape changed was causing a launch-time ModelContainer failure.
    static let versionIdentifier = Schema.Version(1, 1, 0)
    static var models: [any PersistentModel.Type] {
        [SDJournalEntry.self, SDThought.self]
    }
}

/// Bump the version above and add a SeshSchemaV2 + a MigrationStage only when a
/// change needs CUSTOM migration. Additive optional columns migrate
/// automatically (lightweight), so no explicit stage is required here.
enum SeshMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SeshSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Store

/// Thin synchronous wrapper over a SwiftData ModelContext. AppSession owns one
/// of these and keeps its in-memory struct arrays as the source of truth for the
/// UI; this persists them durably and supports indexed fetches.
@MainActor
final class SeshDataStore {
    static let shared = SeshDataStore()

    let container: ModelContainer!
    private var context: ModelContext? { container?.mainContext }

    /// True when SwiftData failed to start and we're running memory-only.
    private(set) var isEphemeral = false
    /// True only if SwiftData is completely unavailable (no container at all).
    /// The app still launches; persistence simply no-ops.
    private(set) var isUnavailable = false

    init() {
        let schema = Schema(SeshSchemaV1.models)

        // 1) Preferred: durable on-disk store with automatic lightweight migration.
        if let onDisk = Self.makeContainer(schema: schema, inMemory: false, migrate: true) {
            container = onDisk
            return
        }
        // 2) On-disk without the migration plan (in case the plan is rejecting it).
        if let onDiskNoPlan = Self.makeContainer(schema: schema, inMemory: false, migrate: false) {
            container = onDiskNoPlan
            return
        }
        // 3) In-memory with the real schema so the app LAUNCHES (session-only data).
        isEphemeral = true
        if let mem = Self.makeContainer(schema: schema, inMemory: true, migrate: false) {
            container = mem
            return
        }
        // 4) In-memory with an EMPTY schema — nothing to fail on.
        if let empty = Self.makeContainer(schema: Schema([]), inMemory: true, migrate: false) {
            container = empty
            return
        }
        // 5) Truly nothing worked. Do NOT trap — leave container nil, flag it,
        //    and let the app run with persistence disabled. (Previously a `try!`
        //    here crashed the app on launch.)
        isUnavailable = true
        container = nil
    }

    /// Build a ModelContainer, returning nil on failure instead of throwing, so
    /// the initializer can fall through a recovery chain and NEVER trap.
    private static func makeContainer(schema: Schema, inMemory: Bool, migrate: Bool) -> ModelContainer? {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            if migrate {
                return try ModelContainer(for: schema, migrationPlan: SeshMigrationPlan.self, configurations: config)
            } else {
                return try ModelContainer(for: schema, configurations: config)
            }
        } catch {
            Logger(subsystem: "com.sowens.The-SESH-", category: "persistence")
                .error("ModelContainer init failed (inMemory=\(inMemory), migrate=\(migrate)): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Fetch (newest first)

    func fetchEntries() -> [JournalEntry] {
        let d = FetchDescriptor<SDJournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context?.fetch(d)) ?? []).map(\.asStruct)
    }
    func fetchThoughts() -> [HighThought] {
        let d = FetchDescriptor<SDThought>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context?.fetch(d)) ?? []).map(\.asStruct)
    }
    var isEmpty: Bool {
        ((try? context?.fetchCount(FetchDescriptor<SDJournalEntry>())) ?? 0) == 0 &&
        ((try? context?.fetchCount(FetchDescriptor<SDThought>())) ?? 0) == 0
    }

    // MARK: Upserts

    func upsertEntry(_ e: JournalEntry) {
        let id = e.id
        let d = FetchDescriptor<SDJournalEntry>(predicate: #Predicate { $0.id == id })
        if let existing = try? context?.fetch(d).first {
            existing.apply(e)
        } else {
            context?.insert(SDJournalEntry(e))
        }
        try? context?.save()
    }
    func upsertThought(_ t: HighThought) {
        let id = t.id
        let d = FetchDescriptor<SDThought>(predicate: #Predicate { $0.id == id })
        if let existing = try? context?.fetch(d).first { existing.apply(t) }
        else { context?.insert(SDThought(t)) }
        try? context?.save()
    }

    // MARK: Deletes

    func deleteEntry(id: UUID) {
        let d = FetchDescriptor<SDJournalEntry>(predicate: #Predicate { $0.id == id })
        if let m = try? context?.fetch(d).first { context?.delete(m); try? context?.save() }
    }
    func deleteThought(id: UUID) {
        let d = FetchDescriptor<SDThought>(predicate: #Predicate { $0.id == id })
        if let m = try? context?.fetch(d).first { context?.delete(m); try? context?.save() }
    }

    // MARK: Bulk

    /// (#9) Record-level reconciliation: bring the on-disk store in line with
    /// the in-memory working set WITHOUT deleting and re-inserting everything.
    /// Inserts new records, updates changed ones in place, and deletes only the
    /// records that were removed. This is what `AppSession.save()` now calls on
    /// every edit — previously each save wiped and rewrote the whole database,
    /// which scaled O(dataset) per keystroke and risked data loss if the app
    /// died between the delete and the re-insert.
    func sync(entries: [JournalEntry], thoughts: [HighThought]) {
        guard let context else { return }

        // Entries -------------------------------------------------------
        let existingEntries = (try? context.fetch(FetchDescriptor<SDJournalEntry>())) ?? []
        var entryByID = Dictionary(existingEntries.map { ($0.id, $0) },
                                   uniquingKeysWith: { a, _ in a })
        var wantedEntryIDs = Set<UUID>()
        for e in entries {
            wantedEntryIDs.insert(e.id)
            if let record = entryByID[e.id] {
                record.apply(e)          // update in place (no-op writes are cheap)
            } else {
                context.insert(SDJournalEntry(e))
            }
        }
        for (id, record) in entryByID where !wantedEntryIDs.contains(id) {
            context.delete(record)
        }
        entryByID.removeAll()

        // Thoughts ------------------------------------------------------
        let existingThoughts = (try? context.fetch(FetchDescriptor<SDThought>())) ?? []
        var thoughtByID = Dictionary(existingThoughts.map { ($0.id, $0) },
                                     uniquingKeysWith: { a, _ in a })
        var wantedThoughtIDs = Set<UUID>()
        for t in thoughts {
            wantedThoughtIDs.insert(t.id)
            if let record = thoughtByID[t.id] {
                record.apply(t)
            } else {
                context.insert(SDThought(t))
            }
        }
        for (id, record) in thoughtByID where !wantedThoughtIDs.contains(id) {
            context.delete(record)
        }
        thoughtByID.removeAll()

        if context.hasChanges { try? context.save() }
    }

    /// Replace the entire dataset. Kept ONLY for the one-time UserDefaults ->
    /// SwiftData migration into an empty store; everything else uses sync().
    func replaceAll(entries: [JournalEntry], thoughts: [HighThought]) {
        try? context?.delete(model: SDJournalEntry.self)
        try? context?.delete(model: SDThought.self)
        for e in entries { context?.insert(SDJournalEntry(e)) }
        for t in thoughts { context?.insert(SDThought(t)) }
        try? context?.save()
    }

    func wipe() {
        try? context?.delete(model: SDJournalEntry.self)
        try? context?.delete(model: SDThought.self)
        try? context?.save()
    }
}
