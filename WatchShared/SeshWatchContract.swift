import Foundation

nonisolated enum SeshWatchContract {
    static let channel = "com.sowens.sesh.watch.v1"
    static let version = 1
    static let maximumWireBytes = 60_000
    static let maximumQueue = 100
    static let methods = ["Joint", "Blunt", "Bowl", "Bong", "Vape", "Dab", "Edible", "Other"]
    static let moods = ["Couch Potato", "Energetic", "Errand Ready", "Productive", "Chill", "Other"]
    static let units = ["g", "mg", "hits", "pieces", "ml"]
    static func date(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970) }
    static func text(_ value: String, maximum: Int, required: Bool = false) -> Bool {
        value.utf8.count <= maximum * 4 && value.count <= maximum && !value.contains("\0") && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    static func encode<T: Encodable>(_ value: T, maximum: Int = maximumWireBytes) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximum else { throw SeshWatchError.invalid("This watch update is too large. Open The SESH. on iPhone.") }
        return data
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data, maximum: Int = maximumWireBytes) throws -> T {
        guard data.count <= maximum else { throw SeshWatchError.invalid("This watch update is too large.") }
        return try JSONDecoder().decode(type, from: data)
    }
    static func decimal(_ text: String, locale: Locale = .current) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let normalized = value.replacingOccurrences(of: separator, with: ".")
        guard value.utf8.count <= 160, value.count <= 40, normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let number = Double(normalized), number.isFinite else { return nil }
        return number
    }
    static func elapsed(start: Date, now: Date = Date()) -> Int {
        let value = now.timeIntervalSince(start)
        return value.isFinite ? Int(min(43_200, max(0, value))) : 0
    }
}
nonisolated enum SeshWatchError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}
nonisolated struct SeshWatchLog: Codable, Equatable, Sendable {
    var date = Date()
    var strain = ""
    var method = "Joint"
    var rating = 5.0
    var mood: String? = nil
    var amount: Double? = nil
    var unit = "g"
    var notes = ""
    var durationMinutes: Int? = nil
    var moodBefore: Int? = nil
    var moodAfter: Int? = nil
    var purchaseID: UUID? = nil
    var tags: [String] = []
    func validate() throws {
        guard SeshWatchContract.date(date), SeshWatchContract.text(strain, maximum: 120, required: true),
              SeshWatchContract.methods.contains(method), rating.isFinite, (1...10).contains(rating),
              mood == nil || SeshWatchContract.moods.contains(mood!), SeshWatchContract.units.contains(unit),
              amount == nil || (amount!.isFinite && amount! > 0 && amount! <= 100_000),
              SeshWatchContract.text(notes, maximum: 2_000), durationMinutes == nil || (0...720).contains(durationMinutes!),
              moodBefore == nil || (0...4).contains(moodBefore!), moodAfter == nil || (0...4).contains(moodAfter!),
              tags.count <= 5, tags.allSatisfy({ SeshWatchContract.text($0, maximum: 40, required: true) }),
              purchaseID == nil || amount != nil else { throw SeshWatchError.invalid("Review the strain, method, amount and timing before saving.") }
    }
}
nonisolated struct SeshWatchEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var log: SeshWatchLog
    var favorite: Bool
    var pinned: Bool
}
nonisolated struct SeshWatchStash: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var strain: String
    var amount: Double
    var used: Double
    var unit: String
    var cost: Double
    var date: Date
    var remaining: Double { max(0, amount - used) }
    func validate() throws {
        guard SeshWatchContract.text(strain, maximum: 120, required: true), SeshWatchContract.text(unit, maximum: 16, required: true),
              amount.isFinite, amount > 0, amount <= 100_000, used.isFinite, (0...amount).contains(used),
              cost.isFinite, (0...1_000_000).contains(cost), SeshWatchContract.date(date) else { throw SeshWatchError.invalid("Review the stash amount, unit and cost.") }
    }
}
nonisolated struct SeshWatchStrain: Codable, Identifiable, Equatable, Sendable {
    var id: String; var name: String; var type: String; var detail: String; var thc: Double?; var cbd: Double?
}
nonisolated struct SeshWatchGoal: Codable, Identifiable, Equatable, Sendable {
    var id: UUID; var title: String; var kind: String; var target: Double?; var actual: Double?; var note: String; var active: Bool
    func validate() throws {
        guard SeshWatchContract.text(title, maximum: 120, required: true), SeshWatchContract.text(note, maximum: 500),
              ["Smoke less", "Spend less", "Tolerance break", "Sleep better", "Be more present", "Custom"].contains(kind),
              target == nil || (target!.isFinite && (0...1_000_000).contains(target!)),
              actual == nil || (actual!.isFinite && (0...1_000_000_000).contains(actual!)),
              kind != "Smoke less" || (target != nil && target!.rounded() == target!),
              kind != "Spend less" || target != nil else { throw SeshWatchError.invalid("Enter a valid personal goal and weekly limit.") }
    }
}
nonisolated struct SeshWatchThought: Codable, Identifiable, Equatable, Sendable { var id: UUID; var date: Date; var text: String }
nonisolated struct SeshWatchSnapshot: Codable, Equatable, Sendable {
    var version = SeshWatchContract.version
    var epoch: UUID
    var generatedAt = Date()
    var revision: Int = 0
    var enabled = true
    var name: String
    var entries: [SeshWatchEntry] = []
    var stash: [SeshWatchStash] = []
    var strains: [SeshWatchStrain] = []
    var goals: [SeshWatchGoal] = []
    var thoughts: [SeshWatchThought] = []
    var totalEntries = 0
    var totalStrains = 0
    var weeklySessions = 0
    var weeklySpend = 0.0
    var phoneSessionStarted: Date? = nil
    var phoneSessionStrain: String? = nil
    var notice: String? = nil
    func validate() throws {
        guard version == SeshWatchContract.version, revision >= 0, SeshWatchContract.date(generatedAt),
              SeshWatchContract.text(name, maximum: 120), entries.count <= 50, stash.count <= 50, strains.count <= 100,
              goals.count <= 30, thoughts.count <= 30, totalEntries >= 0, totalStrains >= 0, weeklySessions >= 0,
              weeklySpend.isFinite, (0...1_000_000_000).contains(weeklySpend),
              phoneSessionStarted == nil || SeshWatchContract.date(phoneSessionStarted!),
              phoneSessionStrain == nil || SeshWatchContract.text(phoneSessionStrain!, maximum: 120),
              notice == nil || SeshWatchContract.text(notice!, maximum: 500),
              Set(entries.map(\.id)).count == entries.count, Set(stash.map(\.id)).count == stash.count,
              Set(strains.map(\.id)).count == strains.count, Set(goals.map(\.id)).count == goals.count,
              Set(thoughts.map(\.id)).count == thoughts.count else { throw SeshWatchError.invalid("The iPhone update could not be read. Update both apps and retry.") }
        for row in entries { try row.log.validate() }
        for row in stash { try row.validate() }
        for row in goals { try row.validate() }
        guard strains.allSatisfy({ SeshWatchContract.text($0.id, maximum: 120) && SeshWatchContract.text($0.name, maximum: 120, required: true) && SeshWatchContract.text($0.detail, maximum: 500) && SeshWatchContract.text($0.type, maximum: 30) && ($0.thc == nil || ($0.thc!.isFinite && (0...100).contains($0.thc!))) && ($0.cbd == nil || ($0.cbd!.isFinite && (0...100).contains($0.cbd!))) }),
              thoughts.allSatisfy({ SeshWatchContract.date($0.date) && SeshWatchContract.text($0.text, maximum: 2_000, required: true) }) else { throw SeshWatchError.invalid("The iPhone update contains unsupported records.") }
    }
}
nonisolated struct SeshWatchCommand: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case log, thought, favorite, pin, addStash, addGoal, goalActive }
    var version = SeshWatchContract.version
    var id = UUID()
    var epoch: UUID
    var createdAt = Date()
    var kind: Kind
    var recordID: UUID? = nil
    var flag: Bool? = nil
    var log: SeshWatchLog? = nil
    var text: String? = nil
    var stash: SeshWatchStash? = nil
    var goal: SeshWatchGoal? = nil
    func validate() throws {
        guard version == SeshWatchContract.version, SeshWatchContract.date(createdAt) else { throw SeshWatchError.invalid("Update both apps before sending this action.") }
        switch kind {
        case .log: guard let log else { throw SeshWatchError.invalid("The log is missing.") }; try log.validate()
        case .thought: guard let text, SeshWatchContract.text(text, maximum: 2_000, required: true) else { throw SeshWatchError.invalid("Enter a private thought up to 2,000 characters.") }
        case .favorite, .pin, .goalActive: guard recordID != nil, flag != nil else { throw SeshWatchError.invalid("Choose a saved record first.") }
        case .addStash: guard let stash, stash.id == id else { throw SeshWatchError.invalid("The stash record is missing.") }; try stash.validate()
        case .addGoal: guard let goal, goal.id == id else { throw SeshWatchError.invalid("The goal is missing.") }; try goal.validate()
        }
    }
}
nonisolated struct SeshWatchReceipt: Codable, Equatable, Sendable {
    var version = SeshWatchContract.version
    var commandID: UUID
    var epoch: UUID
    var accepted: Bool
    var retryable: Bool
    var message: String
    var date = Date()
    func validate() throws {
        guard version == SeshWatchContract.version, SeshWatchContract.date(date), SeshWatchContract.text(message, maximum: 500) else { throw SeshWatchError.invalid("Invalid watch receipt.") }
    }
}
nonisolated struct SeshWatchPacket: Codable, Sendable {
    var channel = SeshWatchContract.channel
    var version = SeshWatchContract.version
    var request = false
    var pageRequest: SeshWatchPageRequest? = nil
    var page: SeshWatchPage? = nil
    var snapshot: SeshWatchSnapshot? = nil
    var command: SeshWatchCommand? = nil
    var receipt: SeshWatchReceipt? = nil
    func validate() throws {
        guard channel == SeshWatchContract.channel, version == SeshWatchContract.version else { throw SeshWatchError.invalid("Update The SESH. on iPhone and Apple Watch.") }
        try snapshot?.validate(); try command?.validate(); try receipt?.validate(); try pageRequest?.validate(); try page?.validate()
    }
}

nonisolated struct SeshWatchPageRequest: Codable, Equatable, Sendable {
    enum Area: String, CaseIterable, Codable, Sendable { case history, strains, stash, goals, thoughts }
    var id = UUID(); var epoch: UUID; var area: Area; var query = ""; var offset = 0
    func validate() throws {
        guard SeshWatchContract.text(query, maximum: 120), (0...1_000_000).contains(offset) else { throw SeshWatchError.invalid("Shorten the search and try again.") }
    }
}
nonisolated struct SeshWatchPage: Codable, Sendable {
    var request: SeshWatchPageRequest; var total: Int; var nextOffset: Int?
    var entries: [SeshWatchEntry] = []; var strains: [SeshWatchStrain] = []; var stash: [SeshWatchStash] = []; var goals: [SeshWatchGoal] = []; var thoughts: [SeshWatchThought] = []
    func validate() throws {
        try request.validate()
        guard total >= 0, nextOffset == nil || (nextOffset! > request.offset && nextOffset! <= total) else { throw SeshWatchError.invalid("The requested page is unavailable.") }
        var check = SeshWatchSnapshot(epoch: request.epoch, name: "")
        check.entries = entries; check.strains = strains; check.stash = stash; check.goals = goals; check.thoughts = thoughts
        try check.validate()
    }
}
