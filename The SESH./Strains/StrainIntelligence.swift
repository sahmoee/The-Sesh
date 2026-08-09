//
//  StrainIntelligence.swift
//  The SESH
//
//  The "intelligence center" logic for the Strains tab: per-strain personal
//  stats, strain comparison, Find My Vibe (effect matching), and What Should I
//  Buy (best pick from a dealer's list). Plus a small Wishlist store. All of it
//  reads the user's real logged history from AppSession + the StrainStore
//  catalog — no network needed.
//

import SwiftUI

// MARK: - Per-strain personal profile

/// Everything SESH knows about how *you* experience one strain.
struct StrainPersonalStats {
    var name: String
    var sessions: Int
    var averageRating: Double          // 0 if never logged
    var isFavorite: Bool
    var category: SeshCategory?
    var topEffects: [String]           // most-frequent effects you've recorded
    var lastUsed: Date?

    var hasHistory: Bool { sessions > 0 }
}

extension AppSession {
    /// Build a personal stats profile for a strain from logged entries.
    func personalStats(forStrain name: String) -> StrainPersonalStats {
        let logged = entries(forStrain: name)
        let avg = logged.isEmpty ? 0 : logged.map(\.rating).reduce(0, +) / Double(logged.count)

        // Tally effects across all sessions for this strain.
        var effectCounts: [String: Int] = [:]
        for e in logged { for eff in (e.effects ?? []) { effectCounts[eff, default: 0] += 1 } }
        let top = effectCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        let fav = logged.contains { $0.category == .personalFaves }
        let cat = logged.compactMap(\.category).first

        return StrainPersonalStats(name: name, sessions: logged.count, averageRating: avg,
                                   isFavorite: fav, category: cat, topEffects: Array(top),
                                   lastUsed: logged.map(\.date).max())
    }

    /// Strains you've actually logged, ranked by how much you've used them.
    func loggedStrainNames() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in entries.sorted(by: { $0.date > $1.date }) {
            let key = e.strain.lowercased()
            if !seen.contains(key) { seen.insert(key); out.append(e.strain) }
        }
        return out
    }

    // MARK: What Should I Buy?

    /// Score a strain for a buying decision: rating, favorite, and session
    /// volume combine into a 0–100 confidence. Strains you've never tried score
    /// low (you have no evidence) but aren't disqualified.
    func buyScore(forStrain name: String) -> Double {
        let s = personalStats(forStrain: name)
        guard s.hasHistory else { return 12 }            // unknown to you
        let ratingPart = (s.averageRating / 10) * 70     // up to 70
        let favPart = s.isFavorite ? 18.0 : 0            // favorite bonus
        let volumePart = min(Double(s.sessions), 6) / 6 * 12  // up to 12 for consistency
        return min(ratingPart + favPart + volumePart, 100)
    }

    struct BuyPick: Identifiable {
        var id: String { name }
        var name: String
        var score: Double
        var reasons: [String]
        var stats: StrainPersonalStats
    }

    /// Rank a dealer's available strains and explain the winner.
    func whatShouldIBuy(from available: [String]) -> [BuyPick] {
        available.map { name in
            let s = personalStats(forStrain: name)
            var reasons: [String] = []
            if s.isFavorite { reasons.append("In your favorites") }
            if s.averageRating >= 8 { reasons.append(String(format: "Highly rated (%.1f)", s.averageRating)) }
            else if s.hasHistory { reasons.append(String(format: "You rate it %.1f", s.averageRating)) }
            if s.sessions >= 3 { reasons.append("Consistent positive history") }
            if !s.topEffects.isEmpty { reasons.append("Gives you " + s.topEffects.prefix(2).joined(separator: ", ")) }
            if !s.hasHistory { reasons.append("You haven't logged this yet") }
            return BuyPick(name: name, score: buyScore(forStrain: name), reasons: reasons, stats: s)
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: Recommendations (from your own history)

    struct Recommendation: Identifiable {
        var id: String { name }
        var name: String
        var reason: String
        var stats: StrainPersonalStats
    }

    /// Your top strains, ranked by your real ratings + history. Only strains
    /// you've actually logged, so it's genuinely personal (not synthetic).
    func recommendedStrains(limit: Int = 5) -> [Recommendation] {
        loggedStrainNames()
            .map { name -> Recommendation in
                let s = personalStats(forStrain: name)
                let reason: String
                if s.isFavorite {
                    reason = "One of your favorites"
                } else if s.averageRating >= 8 {
                    reason = String(format: "You rate it %.1f/10", s.averageRating)
                } else if s.sessions >= 3 {
                    reason = "You keep coming back to it"
                } else if !s.topEffects.isEmpty {
                    reason = "Gives you " + s.topEffects.prefix(2).joined(separator: ", ")
                } else {
                    reason = String(format: "Rated %.1f over %d sesh%@", s.averageRating, s.sessions, s.sessions == 1 ? "" : "es")
                }
                return Recommendation(name: name, reason: reason, stats: s)
            }
            .sorted { buyScore(forStrain: $0.name) > buyScore(forStrain: $1.name) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Find My Vibe

    /// Rank strains you've logged by how often they produced the desired effects.
    /// Returns (strain, matchCount) for strains with at least one match.
    func findMyVibe(effects desired: Set<String>) -> [(name: String, matches: Int, rating: Double)] {
        guard !desired.isEmpty else { return [] }
        var results: [(String, Int, Double)] = []
        for name in loggedStrainNames() {
            let logged = entries(forStrain: name)
            var matchCount = 0
            for e in logged { for eff in (e.effects ?? []) where desired.contains(eff) { matchCount += 1 } }
            if matchCount > 0 {
                let avg = logged.isEmpty ? 0 : logged.map(\.rating).reduce(0, +) / Double(logged.count)
                results.append((name, matchCount, avg))
            }
        }
        return results.sorted { ($0.1, $0.2) > ($1.1, $1.2) }
    }
}

// MARK: - Effect level for the compare grid

enum EffectLevel: String {
    case high = "High", medium = "Medium", low = "Low", none = "—"
    var tint: Color {
        switch self {
        case .high:   return Palette.greenBright
        case .medium: return Palette.gold
        case .low:    return Palette.textSecondary
        case .none:   return Palette.textTertiary
        }
    }
}

extension AppSession {
    /// How strongly a strain produces an effect, for the comparison table.
    func effectLevel(strain name: String, effect: String) -> EffectLevel {
        let logged = entries(forStrain: name)
        guard !logged.isEmpty else { return .none }
        let hits = logged.count(where: { ($0.effects ?? []).contains(effect) })
        let ratio = Double(hits) / Double(logged.count)
        if ratio >= 0.6 { return .high }
        if ratio >= 0.3 { return .medium }
        if ratio > 0 { return .low }
        return .none
    }
}

// MARK: - Wishlist

struct WishlistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var strainName: String
    var note: String?
    var addedAt = Date()
}

@Observable
final class WishlistStore {
    var items: [WishlistItem] = []
    private let key = "sesh.wishlist.v1"

    init() { load() }

    func contains(_ name: String) -> Bool {
        items.contains { $0.strainName.lowercased() == name.lowercased() }
    }

    func add(_ name: String, note: String? = nil) {
        guard !contains(name) else { return }
        items.insert(WishlistItem(strainName: name, note: note), at: 0)
        save()
    }

    func remove(_ item: WishlistItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func toggle(_ name: String) {
        if let existing = items.first(where: { $0.strainName.lowercased() == name.lowercased() }) {
            remove(existing)
        } else {
            add(name)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WishlistItem].self, from: data) else { return }
        items = decoded
    }
}

// MARK: - Comparison history

/// One past comparison the user ran in the Compare Strains tool.
struct ComparisonRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var strains: [String]
    var comparedAt = Date()
}

/// Remembers the strain sets the user has compared, most-recent first, so they
/// can re-open a past comparison with one tap. Persists to UserDefaults, same
/// pattern as WishlistStore.
@Observable
final class ComparisonHistoryStore {
    private(set) var records: [ComparisonRecord] = []
    private let key = "sesh.comparisonHistory.v1"
    private let maxRecords = 12

    init() { load() }

    /// Record a comparison of 2+ strains. Consecutive edits to the same
    /// comparison (adding/removing one strain) collapse into a single entry
    /// instead of piling up, and an exact repeat jumps back to the top.
    func record(_ names: [String]) {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard cleaned.count >= 2 else { return }
        let newSet = Set(cleaned.map { $0.lowercased() })

        // Collapse "still editing" the most recent comparison (a super/subset
        // of it) so building [A,B] -> [A,B,C] leaves one entry, not three.
        if let first = records.first {
            let firstSet = Set(first.strains.map { $0.lowercased() })
            if newSet.isSubset(of: firstSet) || newSet.isSuperset(of: firstSet) {
                records.removeFirst()
            }
        }
        // Drop any exact set-duplicate elsewhere in the list.
        records.removeAll { Set($0.strains.map { $0.lowercased() }) == newSet }

        records.insert(ComparisonRecord(strains: cleaned), at: 0)
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }
        save()
    }

    func remove(_ record: ComparisonRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ComparisonRecord].self, from: data) else { return }
        records = decoded
    }
}
