import Foundation

enum CatalogValuePolicy {
    static func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
}

/// Search documents cache normalized reference fields once per catalog revision.
struct CatalogSearchDocument {
    let id: String
    let name: String
    let type: String
    let aliases: [String]
    let traits: [String]
    let breeder: String
    let coverage: Int
}

struct CatalogSearchIndex {
    private struct Row {
        let document: CatalogSearchDocument
        let name: String
        let aliases: [String]
        let traits: [String]
        let breeder: String
    }
    private let rows: [Row]
    private let exact: [String: String]
    let alphabeticIDs: [String]
    init(_ documents: [CatalogSearchDocument]) {
        var seen = Set<String>()
        let unique = documents.filter { seen.insert($0.id).inserted }
        rows = unique.map { Row(document: $0, name: Self.normalize($0.name), aliases: $0.aliases.map(Self.normalize), traits: $0.traits.map(Self.normalize), breeder: Self.normalize($0.breeder)) }
        var names: [String: String] = [:]
        // Display names outrank another strain's alias; producer order keeps custom overrides first.
        for row in rows where !row.name.isEmpty { if names[row.name] == nil { names[row.name] = row.document.id } }
        for row in rows {
            for alias in row.aliases where !alias.isEmpty && names[alias] == nil { names[alias] = row.document.id }
        }
        exact = names
        alphabeticIDs = unique.sorted(by: Self.precedes).map(\.id)
    }
    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func precedes(_ lhs: CatalogSearchDocument, _ rhs: CatalogSearchDocument) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
    func exactID(_ query: String) -> String? { exact[Self.normalize(query)] }
    func prefixID(_ query: String) -> String? {
        let term = Self.normalize(query)
        guard !term.isEmpty else { return nil }
        return rows.first { $0.name.hasPrefix(term) || $0.aliases.contains(where: { $0.hasPrefix(term) }) }?.document.id
    }
    func suggestions(_ query: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let term = Self.normalize(query)
        guard !term.isEmpty else { return [] }
        var prefixes: [String] = [], contains: [String] = []
        for row in rows {
            let keys = [row.name] + row.aliases
            if keys.contains(where: { $0.hasPrefix(term) }) {
                prefixes.append(row.document.id)
                if prefixes.count == limit { return prefixes }
            } else if contains.count < limit && keys.contains(where: { $0.contains(term) }) { contains.append(row.document.id) }
        }
        return Array((prefixes + contains).prefix(limit))
    }
    func search(_ query: String, type: String?, detailedOnly: Bool) -> [String] {
        let term = Self.normalize(query)
        return rows.compactMap { row -> (CatalogSearchDocument, Int)? in
            let item = row.document
            guard type == nil || item.type == type, !detailedOnly || item.coverage >= 4 else { return nil }
            guard !term.isEmpty else { return (item, item.coverage) }
            let rank: Int
            if row.name == term { rank = 100 }
            else if row.name.hasPrefix(term) { rank = 80 }
            else if row.aliases.contains(where: { $0 == term || $0.hasPrefix(term) }) { rank = 70 }
            else if row.name.contains(term) { rank = 60 }
            else if row.breeder.contains(term) { rank = 40 }
            else if row.traits.contains(where: { $0.contains(term) }) { rank = 30 }
            else { return nil }
            return (item, rank + item.coverage)
        }.sorted { $0.1 == $1.1 ? Self.precedes($0.0, $1.0) : $0.1 > $1.1 }.map { $0.0.id }
    }
}

/// Array JSON remains compatible with legacy UserDefaults mirrors. Invalid originals
/// are preserved; ordinary writes cannot turn a failed read into an empty replacement.
final class ProtectedCollectionStore<Value: Codable> {
    let url: URL
    private let maximumBytes: Int
    private(set) var blocked = false
    init(url: URL, maximumBytes: Int = 16 * 1024 * 1024) {
        self.url = url
        self.maximumBytes = max(1, maximumBytes)
    }
    func load(legacy: Data?) throws -> [Value] {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try JSONDecoder().decode([Value].self, from: readBoundedFile())
                blocked = false
                return values
            }
            guard let legacy else { blocked = false; return [] }
            guard legacy.count <= maximumBytes else { throw CollectionError.tooLarge }
            let values = try JSONDecoder().decode([Value].self, from: legacy)
            blocked = false
            try write(values)
            return values
        } catch { blocked = true; throw error }
    }
    @discardableResult func write(_ values: [Value]) throws -> Data {
        guard !blocked else { throw CollectionError.unreadableOriginal }
        let data = try JSONEncoder().encode(values)
        guard data.count <= maximumBytes else { throw CollectionError.tooLarge }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        return data
    }
    private func readBoundedFile() throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        // Chunked reads enforce the limit even when a file grows after opening.
        while let chunk = try file.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty {
            guard chunk.count <= maximumBytes - data.count else { throw CollectionError.tooLarge }
            data.append(chunk)
        }
        return data
    }
    /// Reserved for the app's existing explicit full-data reset.
    func reset() throws {
        let wasBlocked = blocked; blocked = false
        do { try write([]) } catch { blocked = wasBlocked; throw error }
    }
    enum CollectionError: LocalizedError {
        case unreadableOriginal
        case tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadableOriginal: return "The saved collection could not be read. Its original data is preserved; changes are paused."
            case .tooLarge: return "This collection exceeds the supported size. Its original data is preserved."
            }
        }
    }
    static func applicationURL(_ name: String) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("PrivateCollections", isDirectory: true).appendingPathComponent(name)
    }
}

enum PersonalGoalPolicy {
    struct WeekSummary {
        let start: Date
        let end: Date
        let sessions: Int
        let spent: Double
        let ignoredCosts: Int
    }
    static func week(now: Date, sessionDates: [Date], purchases: [(date: Date, cost: Double)], calendar: Calendar = .current) -> WeekSummary {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86400)
        let contains: (Date) -> Bool = { $0 >= interval.start && $0 < interval.end && $0 <= now }
        var total = 0.0, invalid = 0
        for purchase in purchases where contains(purchase.date) {
            guard purchase.cost.isFinite, purchase.cost >= 0, (total + purchase.cost).isFinite else { invalid += 1; continue }
            total += purchase.cost
        }
        return WeekSummary(start: interval.start, end: interval.end, sessions: sessionDates.filter(contains).count, spent: total, ignoredCosts: invalid)
    }
    static func validTarget(_ value: Double?, wholeNumber: Bool) -> Bool {
        guard let value, value.isFinite, value >= 0 else { return false }
        return !wholeNumber || value.rounded() == value
    }
    static func usage(actual: Double, target: Double) -> Double? {
        guard actual.isFinite, actual >= 0, validTarget(target, wholeNumber: false) else { return nil }
        if target == 0 { return actual == 0 ? 0 : 1 }
        return min(1, max(0, actual / target))
    }
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "Unavailable" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
