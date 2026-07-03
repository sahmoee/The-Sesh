//
//  SeshFeaturePack.swift
//  The SESH
//
//  Data backbone for the feature pack. Everything here is additive: new stored
//  values on AppSession (via UserDefaults, matching the existing pattern), plus
//  pure read-side aggregations for Smart Picks, Music Stations, Rhythm insights,
//  the per-strain dossier, budget, and inventory. No existing behaviour changes.
//
//  Persistence keys follow the established "ht." (legacy) / "sesh." (new)
//  convention and are declared here as string literals local to this file so the
//  pack is drop-in without editing StorageKeys.swift.
//

import SwiftUI

// MARK: - Sesh Presets (saved strain + method setups)

/// A saved "one-tap start" setup: a strain, a method, and a default vibe. Tapping
/// a preset on Home starts a sesh pre-filled with these, skipping the picker.
struct SeshPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String                 // user label, e.g. "Wake & Bake"
    var strainName: String
    var method: String               // "Joint", "Bong", "Blunt", "Vape", etc.
    var sessionTypeRaw: String       // SessionType.rawValue
    var createdAt = Date()

    var sessionType: SessionType { SessionType(rawValue: sessionTypeRaw) ?? .relaxing }
    var subtitle: String { "\(strainName) · \(method)" }
}

// MARK: - Custom status presets (reusable in the StatusPill dropdown)

/// A saved custom status string the user can re-pick from the pill dropdown.
struct SavedStatus: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var createdAt = Date()
}

// MARK: - Smart Pick (recommendation)

/// A scored strain recommendation with a short human reason.
struct SmartPick: Identifiable {
    var id: String { strainName }
    let strainName: String
    let score: Double          // 0...1 normalized
    let reason: String
    let avgRating: Double
    let sessions: Int
}

// MARK: - Music Station (generated from captured song history)

/// A station is a themed collection of songs pulled from your sesh history,
/// grouped either by a strain or by a vibe (SessionType).
struct MusicStation: Identifiable {
    enum Kind: Hashable { case strain(String); case vibe(SessionType) }
    var id: String {
        switch kind {
        case .strain(let s): return "strain:\(s)"
        case .vibe(let v):   return "vibe:\(v.rawValue)"
        }
    }
    let kind: Kind
    let title: String
    let subtitle: String
    let songs: [SongTally]
    let symbol: String
    let tint: Color
}

// MARK: - Rhythm buckets (time-of-day / weekday)

struct RhythmBucket: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

// MARK: - AppSession additions

extension AppSession {

    // ---- keys (local to the pack) ----
    private static let presetsKey       = "sesh.presets.v1"
    private static let savedStatusKey   = "sesh.savedStatuses.v1"
    private static let favStrainsKey    = "sesh.favoriteStrains.v1"
    private static let hapticsKey       = "sesh.haptics.enabled.v1"
    private static let budgetKey        = "sesh.monthlyBudget.v1"

    // MARK: Sesh Presets

    var seshPresets: [SeshPreset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.presetsKey),
                  let v = try? Self.jsonDecoder.decode([SeshPreset].self, from: data) else { return [] }
            return v
        }
        set {
            if let data = try? Self.jsonEncoder.encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.presetsKey)
            }
        }
    }

    func addPreset(_ p: SeshPreset) {
        var list = seshPresets
        list.insert(p, at: 0)
        seshPresets = list
    }
    func deletePreset(_ p: SeshPreset) {
        seshPresets = seshPresets.filter { $0.id != p.id }
    }

    /// Start a sesh from a preset by writing live sesh state directly (the same
    /// mechanism RootView uses for an immediate bong-rip start). Does nothing if
    /// a sesh is already live, so a preset never starts a second concurrent sesh.
    /// Returns true if a new sesh was started. The active sesh then appears on
    /// Home via ActiveSeshCard.
    @discardableResult
    func startPreset(_ preset: SeshPreset) -> Bool {
        guard liveSesh == nil else { return false }
        let state = LiveSeshState(
            startedAt: Date(),
            stageRaw: SeshStage.smoking.rawValue,
            sessionTypeRaw: preset.sessionTypeRaw,
            strainName: preset.strainName,
            attachedThought: "",
            rollFinalSeconds: nil,
            rollMethod: preset.method,
            invited: [])
        saveLiveSesh(state)
        return true
    }

    // MARK: Custom status presets

    var savedStatuses: [SavedStatus] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.savedStatusKey),
                  let v = try? Self.jsonDecoder.decode([SavedStatus].self, from: data) else { return [] }
            return v
        }
        set {
            if let data = try? Self.jsonEncoder.encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.savedStatusKey)
            }
        }
    }

    func rememberStatus(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = savedStatuses
        guard !list.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        list.insert(SavedStatus(text: trimmed), at: 0)
        savedStatuses = Array(list.prefix(12))   // keep the list tidy
    }
    func forgetStatus(_ s: SavedStatus) {
        savedStatuses = savedStatuses.filter { $0.id != s.id }
    }

    // MARK: Favorite strains (independent of the Vault "Favorites" category)

    /// A lightweight starred set of strain names, for the "Your Strains" surface.
    var favoriteStrainNames: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.favStrainsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.favStrainsKey) }
    }
    func isFavoriteStrain(_ name: String) -> Bool {
        favoriteStrainNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    func toggleFavoriteStrain(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        var list = favoriteStrainNames
        if let i = list.firstIndex(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
            list.remove(at: i)
        } else {
            list.append(key)
        }
        favoriteStrainNames = list
    }

    // MARK: Haptics toggle

    /// Whether in-app haptics are enabled (default on). Read by Haptics.
    var hapticsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.hapticsKey) == nil
                ? true : UserDefaults.standard.bool(forKey: Self.hapticsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hapticsKey)
            Haptics.isEnabled = newValue
        }
    }

    // MARK: Monthly budget

    /// User's monthly spend budget (0 = not set).
    var monthlyBudget: Double {
        get { UserDefaults.standard.double(forKey: Self.budgetKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Self.budgetKey) }
    }
    var hasBudget: Bool { monthlyBudget > 0 }

    /// Spend this calendar month, drawn from purchases (falling back to legacy
    /// per-entry prices, matching `totalSpent`'s logic).
    var spentThisMonth: Double {
        let cal = Calendar.current, now = Date()
        let fromPurchases = purchases
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .map(\.cost).reduce(0, +)
        if fromPurchases > 0 { return fromPurchases }
        return thisMonthSpent   // legacy entry prices
    }
    var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(1, spentThisMonth / monthlyBudget)
    }
    var budgetRemaining: Double { max(0, monthlyBudget - spentThisMonth) }
    var isOverBudget: Bool { hasBudget && spentThisMonth > monthlyBudget }

    // MARK: Clear music history

    /// Wipe all captured song plays (the "clear music history" small feature).
    func clearMusicHistory() {
        songPlays.removeAll()
        if let data = try? Self.jsonEncoder.encode([StrainSongPlay]()) {
            UserDefaults.standard.set(data, forKey: "ht.songPlays.v1")
            CloudSync.set(data, forKey: "ht.songPlays.v1")
        }
    }

    // MARK: - Smart Picks

    /// Recommends strains scored from your own ratings and how recently/often you
    /// enjoyed them. Only strains you've logged are considered — no external data.
    func smartPicks(limit: Int = 5) -> [SmartPick] {
        let groups = Dictionary(grouping: entries, by: { $0.strain.lowercased().trimmingCharacters(in: .whitespaces) })
        let now = Date()
        var picks: [SmartPick] = []
        for (_, group) in groups {
            guard let first = group.first, !first.strain.isEmpty else { continue }
            let ratings = group.map(\.rating)
            let avg = ratings.reduce(0, +) / Double(ratings.count)
            guard avg >= 6 else { continue }   // only recommend things you actually liked
            let count = group.count
            // Recency: strains you haven't had in a while but rated highly bubble up.
            let lastDate = group.map(\.date).max() ?? first.date
            let daysSince = max(0, Calendar.current.dateComponents([.day], from: lastDate, to: now).day ?? 0)
            let ratingScore = (avg - 6) / 4                     // 0...1 over 6→10
            let freqScore = min(1, Double(count) / 6)           // rewards proven strains
            let recencyBoost = min(0.25, Double(daysSince) / 120) // gentle "missed you" nudge
            let score = min(1, ratingScore * 0.6 + freqScore * 0.25 + recencyBoost)
            let reason: String
            if daysSince >= 21 { reason = "Rated \(Fmt.rating(avg)) — haven't had it in \(daysSince)d" }
            else if count >= 4 { reason = "A proven favorite (\(count) seshes, \(Fmt.rating(avg))★)" }
            else { reason = "You rated this \(Fmt.rating(avg))★" }
            picks.append(SmartPick(strainName: first.strain, score: score,
                                   reason: reason, avgRating: avg, sessions: count))
        }
        return picks.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    // MARK: - Music Stations

    /// Builds stations from captured song history: one per strain with enough
    /// plays, plus one per vibe. Requires at least a few songs to be meaningful.
    func musicStations(minSongs: Int = 3) -> [MusicStation] {
        guard songPlays.count >= minSongs else { return [] }
        var stations: [MusicStation] = []

        // Vibe stations.
        for (vibe, group) in Dictionary(grouping: songPlays, by: { $0.sessionType }) {
            let songs = MusicMemory.topSongs(group, limit: 30)
            guard songs.count >= minSongs else { continue }
            stations.append(MusicStation(
                kind: .vibe(vibe),
                title: "\(vibe.emoji) \(vibe.rawValue) Station",
                subtitle: "\(group.count) plays from your \(vibe.rawValue.lowercased()) seshes",
                songs: songs, symbol: "music.note.list", tint: Palette.purple))
        }

        // Strain stations.
        for pairing in MusicMemory.pairings(songPlays, limit: 12) where pairing.playCount >= minSongs {
            let songs = MusicMemory.songs(for: pairing.strainName, in: songPlays, limit: 30)
            stations.append(MusicStation(
                kind: .strain(pairing.strainName),
                title: pairing.strainName,
                subtitle: "\(pairing.playCount) plays while smoking this",
                songs: songs, symbol: "leaf.fill", tint: Palette.greenBright))
        }

        // Vibe stations first (broader), then strain stations, each by volume.
        return stations.sorted { $0.songs.count > $1.songs.count }
    }

    // MARK: - Rhythm insights (time-of-day + weekday)

    /// Session counts bucketed into parts of day.
    func timeOfDayRhythm() -> [RhythmBucket] {
        let cal = Calendar.current
        // 0: Morning 5–11, 1: Afternoon 12–16, 2: Evening 17–20, 3: Night 21–4
        var buckets = [0, 0, 0, 0]
        for e in entries {
            let h = cal.component(.hour, from: e.date)
            switch h {
            case 5...11:  buckets[0] += 1
            case 12...16: buckets[1] += 1
            case 17...20: buckets[2] += 1
            default:      buckets[3] += 1
            }
        }
        let labels = ["Morning", "Afternoon", "Evening", "Night"]
        return zip(labels, buckets).map { RhythmBucket(label: $0, count: $1) }
    }

    /// Session counts by weekday (Sun…Sat).
    func weekdayRhythm() -> [RhythmBucket] {
        let cal = Calendar.current
        var buckets = [Int](repeating: 0, count: 7)
        for e in entries {
            let wd = cal.component(.weekday, from: e.date) - 1   // 0-indexed Sun
            if wd >= 0 && wd < 7 { buckets[wd] += 1 }
        }
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return zip(labels, buckets).map { RhythmBucket(label: $0, count: $1) }
    }

    /// The busiest part of day, for a headline line ("You sesh most in the evening").
    var peakTimeOfDay: String? {
        timeOfDayRhythm().max(by: { $0.count < $1.count }).flatMap { $0.count > 0 ? $0.label : nil }
    }

    // MARK: - Per-strain dossier stats

    /// Total spend attributable to a strain (from purchases + legacy entry prices).
    func spend(forStrain name: String) -> Double {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let fromPurchases = purchases
            .filter { $0.strain.lowercased().trimmingCharacters(in: .whitespaces) == key }
            .map(\.cost).reduce(0, +)
        let fromEntries = entries(forStrain: name).compactMap(\.price).reduce(0, +)
        return fromPurchases + fromEntries
    }

    /// The top songs played while smoking a strain (for the dossier).
    func topSongs(forStrain name: String, limit: Int = 5) -> [SongTally] {
        MusicMemory.songs(for: name, in: songPlays, limit: limit)
    }

    // MARK: - Calendar heatmap

    /// Session count per calendar day for the last `days` days, oldest→newest.
    func dailyActivity(days: Int = 119) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byDay: [Date: Int] = [:]
        for e in entries {
            byDay[cal.startOfDay(for: e.date), default: 0] += 1
        }
        var out: [(Date, Int)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            out.append((d, byDay[d] ?? 0))
        }
        return out
    }

    // MARK: - Stash inventory helpers

    /// Purchases running low (≤ 20% of the original amount but not empty).
    var lowStockPurchases: [Purchase] {
        purchases.filter { !$0.isEmpty && $0.amount > 0 && ($0.remaining / $0.amount) <= 0.2 }
    }
    var hasLowStock: Bool { !lowStockPurchases.isEmpty }
}
