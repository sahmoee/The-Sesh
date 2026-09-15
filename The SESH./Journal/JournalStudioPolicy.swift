import Foundation

/// Local-only organization metadata. Journal entries remain owned by AppSession.
struct JournalStudioFilter: Codable, Equatable {
    var query = ""
    var days = 0
    var method = ""
    var pinnedOnly = false
    var notebookID: UUID?
}

struct JournalStudioSavedView: Codable, Identifiable {
    var id = UUID()
    var name: String
    var filter: JournalStudioFilter
}

struct JournalNotebook: Codable, Identifiable {
    var id = UUID()
    var name: String
    var entryIDs: Set<UUID> = []
}

struct JournalReflection: Codable, Identifiable {
    var id: UUID // journal entry identity
    var prompt: String = "What would you like to remember?"
    var text = ""
    var dueAt: Date?
    var completedAt: Date?
}

struct JournalStudioSnapshot: Codable {
    var version = 1
    var pinned: Set<UUID> = []
    var savedViews: [JournalStudioSavedView] = []
    var notebooks: [JournalNotebook] = []
    var reflections: [JournalReflection] = []
    var dismissedDuplicateGroups: Set<String> = []
}

enum JournalStudioPolicy {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validName(_ name: String, existing: [String]) -> String? {
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 60,
              !existing.contains(where: { normalized($0) == normalized(result) }) else { return nil }
        return result
    }

    /// Includes today plus the preceding days, using local calendar boundaries.
    static func includes(_ date: Date, days: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard days > 0 else { return true }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        return date >= start && date < end
    }

    /// Quoting alone doesn't stop spreadsheet formulas. Neutralize formula prefixes.
    static func csvCell(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.first.map { "=+-@".contains($0) } ?? false
        let safe = prefix || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(rows: [[String]]) -> String {
        rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func duplicateKey(ids: [UUID]) -> String {
        ids.map(\.uuidString).sorted().joined(separator: "|")
    }

    static func monthlySpend(_ records: [(Date, Double)], now: Date,
                             calendar: Calendar = .current) -> [(Date, Double)] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        let count = calendar.range(of: .day, in: .month, for: now)?.count ?? 31
        var buckets = Array(repeating: 0.0, count: (count + 6) / 7)
        for (date, price) in records where date >= month.start && date < month.end && price.isFinite && price >= 0 {
            buckets[(calendar.component(.day, from: date) - 1) / 7] += price
        }
        return buckets.enumerated().compactMap { index, total in
            calendar.date(byAdding: .day, value: index * 7, to: month.start).map { ($0, total) }
        }
    }
}
