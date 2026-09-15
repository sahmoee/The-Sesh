import Foundation

/// Pure production-policy and temporary-file tests. Never reads application data.
@main enum CatalogGoalChecks {
    struct Record: Codable, Equatable { let name: String; let value: Double }
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(message) } catch { checks += 1 }
        }
        for invalid: Double? in [nil, -1, 101, .nan, .infinity, .greatestFiniteMagnitude] {
            check(CatalogValuePolicy.percentage(invalid) == nil, "Invalid historical percentage is not a displayable potency")
        }
        check(CatalogValuePolicy.percentage(0) == 0 && CatalogValuePolicy.percentage(100) == 100, "Percentage endpoints stay valid")
        check(CatalogValuePolicy.percentage(23.5) == 23.5, "Preserve fractional percentage")
        let docs = [
            CatalogSearchDocument(id: "z", name: "Blue Café", type: "hybrid", aliases: ["BC", "Northern"], traits: ["Calm", "Citrus"], breeder: "Acme", coverage: 5),
            CatalogSearchDocument(id: "a", name: "Northern", type: "indica", aliases: ["Lights"], traits: ["Earthy"], breeder: "North Co", coverage: 2),
            CatalogSearchDocument(id: "b", name: "Cafe Blue", type: "sativa", aliases: [], traits: [], breeder: "", coverage: 1),
            CatalogSearchDocument(id: "c", name: "Blue Moon", type: "hybrid", aliases: [], traits: ["Creative"], breeder: "", coverage: 4),
            CatalogSearchDocument(id: "z", name: "Duplicate ID", type: "hybrid", aliases: [], traits: [], breeder: "", coverage: 10)
        ]
        let index = CatalogSearchIndex(docs)
        check(CatalogSearchIndex.normalize("  BLÜE--café\n") == "blue cafe", "Normalize diacritics and punctuation once")
        check(index.exactID("blue-cafe") == "z", "Exact punctuation-normalized name")
        check(index.exactID("BC") == "z", "Alias lookup")
        check(index.exactID("Northern") == "a", "Real display name outranks earlier alias")
        check(index.exactID("Duplicate ID") == nil, "First repeated identity wins")
        check(index.exactID("   ") == nil, "No empty exact lookup")
        check(index.prefixID("moon") == nil && index.prefixID("blue") == "z", "Reference lookup does not silently choose a substring-only suggestion")
        check(index.suggestions("blue", limit: -1).isEmpty, "Negative limit safe")
        check(index.suggestions("blue", limit: 0).isEmpty, "Zero limit safe")
        check(index.suggestions(" ", limit: 5).isEmpty, "No blank suggestions")
        check(index.suggestions("blue", limit: 2) == ["z", "c"], "Prefix matches outrank earlier substring")
        check(index.suggestions("blue", limit: 3) == ["z", "c", "b"], "Fill remaining limit with substring")
        check(index.suggestions("lights", limit: 1) == ["a"], "Alias suggestions")
        check(index.suggestions("absent", limit: 5).isEmpty, "Missing suggestions")
        check(index.alphabeticIDs == ["z", "c", "b", "a"], "Deduplicated alphabetical index")
        check(index.search("", type: "hybrid", detailedOnly: true) == ["z", "c"], "Type and coverage combine")
        check(index.search("", type: "indica", detailedOnly: true).isEmpty, "Detailed filter excludes sparse profile")
        check(index.search("citrus", type: nil, detailedOnly: false) == ["z"], "Trait search")
        check(index.search("acme", type: nil, detailedOnly: false) == ["z"], "Breeder search")
        check(index.search("lights", type: nil, detailedOnly: false) == ["a"], "Alias search")
        check(index.search("northern", type: nil, detailedOnly: false).first == "a", "Exact name outranks alias")
        check(index.search("blue", type: "sativa", detailedOnly: false) == ["b"], "Type applies to text matches")
        let ties = CatalogSearchIndex(["b", "a"].map { CatalogSearchDocument(id: $0, name: "Same", type: "unknown", aliases: [], traits: [], breeder: "", coverage: 0) })
        check(ties.alphabeticIDs == ["a", "b"] && ties.search("", type: nil, detailedOnly: false) == ["a", "b"], "Stable ID ties for both sorts")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let now = date(9, 16, 12), monday = date(9, 14)
        let summary = PersonalGoalPolicy.week(now: now, sessionDates: [monday.addingTimeInterval(-1), monday, now, now.addingTimeInterval(1), date(9, 21)], purchases: [(monday, 12.5), (now, 2.5), (date(9, 13), 99), (now.addingTimeInterval(1), 99), (now, .nan), (now, .infinity), (now, -1)], calendar: calendar)
        check(summary.start == monday && summary.end == date(9, 21), "Calendar week honors locale first weekday")
        check(summary.sessions == 2, "Week excludes previous week and future records")
        check(summary.spent == 15, "Only valid recorded current-week purchases")
        check(summary.ignoredCosts == 3, "Surface invalid cost count")
        let overflow = PersonalGoalPolicy.week(now: now, sessionDates: [], purchases: [(now, .greatestFiniteMagnitude), (now, .greatestFiniteMagnitude)], calendar: calendar)
        check(overflow.spent.isFinite && overflow.ignoredCosts == 1, "Addition overflow cannot poison weekly total")
        let spring = PersonalGoalPolicy.week(now: date(3, 8, 13), sessionDates: [], purchases: [], calendar: calendar)
        check(spring.end.timeIntervalSince(spring.start) == 7 * 86400 - 3600, "DST calendar week is not fixed seconds")
        check(!PersonalGoalPolicy.validTarget(nil, wholeNumber: false), "Missing target invalid")
        check(!PersonalGoalPolicy.validTarget(.nan, wholeNumber: false), "NaN target invalid")
        check(!PersonalGoalPolicy.validTarget(.infinity, wholeNumber: false), "Infinite target invalid")
        check(!PersonalGoalPolicy.validTarget(-1, wholeNumber: true), "Negative target invalid")
        check(!PersonalGoalPolicy.validTarget(2.5, wholeNumber: true), "Session target must be whole")
        check(PersonalGoalPolicy.validTarget(2.5, wholeNumber: false), "Spend target allows decimal")
        check(PersonalGoalPolicy.validTarget(0, wholeNumber: true), "Zero limit valid")
        check(PersonalGoalPolicy.usage(actual: 0, target: 0) == 0, "Zero usage and zero limit")
        check(PersonalGoalPolicy.usage(actual: 1, target: 0) == 1, "Nonzero usage versus zero limit")
        check(PersonalGoalPolicy.usage(actual: 4, target: 8) == 0.5, "Partial usage")
        check(PersonalGoalPolicy.usage(actual: 12, target: 8) == 1, "Clamp over-limit display")
        check(PersonalGoalPolicy.usage(actual: .infinity, target: 8) == nil, "Do not display invalid usage")
        check(PersonalGoalPolicy.usage(actual: -1, target: 8) == nil, "No negative usage")
        check(PersonalGoalPolicy.usage(actual: 1, target: .nan) == nil, "Invalid denominator")
        check(PersonalGoalPolicy.number(.nan) == "Unavailable", "Unsafe historical values display missing")
        check(!PersonalGoalPolicy.number(.greatestFiniteMagnitude).isEmpty, "Large finite value does not trap Int conversion")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sesh-catalog-goal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let record = Record(name: "Private", value: 2.5)
        let legacy = try JSONEncoder().encode([record])
        let url = temp.appendingPathComponent("nested/items.json")
        let store = ProtectedCollectionStore<Record>(url: url)
        let empty = try store.load(legacy: nil)
        check(empty.isEmpty && !store.blocked, "First launch does not invent records")
        let migrated = try store.load(legacy: legacy)
        check(migrated == [record], "Legacy array migrates without schema changes")
        let committed = tryData(url)
        let migratedFile = try JSONDecoder().decode([Record].self, from: committed)
        check(migratedFile == [record], "Migration creates durable local original")
        let reloaded = try ProtectedCollectionStore<Record>(url: url).load(legacy: Data("bad mirror".utf8))
        check(reloaded == [record], "Validated file remains authoritative over stale mirror")
        rejects("Encoding failure reported") { _ = try store.write([Record(name: "Invalid", value: .nan)]) }
        check(tryData(url) == committed, "Encode failure leaves prior bytes unchanged")
        let changed = Record(name: "Changed", value: 3)
        try store.write([changed])
        let changedReload = try ProtectedCollectionStore<Record>(url: url).load(legacy: nil)
        check(changedReload == [changed], "Successful replacement round-trips")
        let corrupt = Data("preserve original".utf8)
        try corrupt.write(to: url)
        rejects("Corrupt original reported") { _ = try store.load(legacy: legacy) }
        check(store.blocked, "Unreadable original blocks ordinary edits")
        rejects("Blocked write denied") { _ = try store.write([]) }
        check(tryData(url) == corrupt, "Failed load cannot erase corrupt original or silently use mirror")
        try legacy.write(to: url)
        let recovered = try store.load(legacy: nil)
        check(recovered == [record] && !store.blocked, "Retry after repair resumes normal edits")
        try corrupt.write(to: url)
        rejects("Reset setup catches invalid file") { _ = try store.load(legacy: nil) }
        try store.reset()
        check(tryData(url) == Data("[]".utf8) && !store.blocked, "Only explicit reset may replace unreadable original")
        let invalidMigration = ProtectedCollectionStore<Record>(url: temp.appendingPathComponent("invalid.json"))
        rejects("Invalid legacy migration fails") { _ = try invalidMigration.load(legacy: corrupt) }
        check(invalidMigration.blocked && !FileManager.default.fileExists(atPath: invalidMigration.url.path), "Failed migration creates no empty replacement")
        let obstacle = temp.appendingPathComponent("file-not-folder")
        try Data().write(to: obstacle)
        let ioFailure = ProtectedCollectionStore<Record>(url: obstacle.appendingPathComponent("data.json"))
        rejects("I/O migration failure visible") { _ = try ioFailure.load(legacy: legacy) }
        check(ioFailure.blocked, "Migration failure blocks later optimistic writes")
        let limitedURL = temp.appendingPathComponent("limited.json")
        try legacy.write(to: limitedURL)
        let limited = ProtectedCollectionStore<Record>(url: limitedURL, maximumBytes: 8)
        rejects("Bounded file read") { _ = try limited.load(legacy: nil) }
        check(limited.blocked && tryData(limitedURL) == legacy, "Oversized original preserved")
        let newLimited = ProtectedCollectionStore<Record>(url: temp.appendingPathComponent("small.json"), maximumBytes: 8)
        rejects("Bounded legacy migration") { _ = try newLimited.load(legacy: legacy) }
        let writeLimited = ProtectedCollectionStore<Record>(url: temp.appendingPathComponent("small-write.json"), maximumBytes: 8)
        try writeLimited.write([])
        rejects("Reject oversized replacement") { _ = try writeLimited.write([record]) }
        check(tryData(writeLimited.url) == Data("[]".utf8), "Oversized write leaves saved collection intact")
        print("Catalog and goal checks passed: \(checks)")
    }
    private static func tryData(_ url: URL) -> Data { (try? Data(contentsOf: url)) ?? Data() }
}
