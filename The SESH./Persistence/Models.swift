//
//  Models.swift
//  HighThoughts
//
//  Domain models + observable session store (UserDefaults persistence).
//

import SwiftUI

// MARK: - Mood (how you feel)

// MARK: - Session store

@MainActor
@Observable
final class AppSession {
    // Shared coders reused across all persistence paths. Encoding/decoding
    // happens on every data mutation (purchases, categories, live-sesh state),
    // so allocating a fresh coder each time was needless churn.
    @ObservationIgnored static let jsonEncoder = JSONEncoder()
    @ObservationIgnored static let jsonDecoder = JSONDecoder()

    var entries: [JournalEntry] = []
    var thoughts: [HighThought] = []

    var userName = "Alex"
    var joinedText = "Joined May 2025"

    /// When iCloud sync last reconciled (for the Settings sync-status row). Nil
    /// until the first sync this launch.
    var lastSyncedAt: Date?

    private let entriesKey  = DefaultsKey.entries
    private let thoughtsKey = DefaultsKey.thoughts
    private let nameKey      = DefaultsKey.name
    private let seededKey    = DefaultsKey.seeded
    private let migratedKey  = DefaultsKey.migrated

    init() {
        // 1. Pull any newer cross-device data from iCloud into UserDefaults.
        CloudSync.pullIntoDefaults(keys: [entriesKey, thoughtsKey, nameKey])
        // 2. One-time migration: if there's legacy UserDefaults data and the
        //    SwiftData store is empty, move it into SwiftData.
        migrateFromUserDefaultsIfNeeded()
        // 3. Load the working set from SwiftData (the local source of truth).
        load()
        loadPurchases()
        loadCustomCategories()
        loadLiveSesh()
        seedIfNeeded()
        // 4. React to changes from other devices — merge rather than overwrite.
        CloudSync.startObserving(keys: [entriesKey, thoughtsKey, nameKey]) { [weak self] in
            self?.mergeFromStorage()
        }
    }

    /// SwiftData store (local, durable). AppSession keeps struct arrays in memory
    /// for the UI and mirrors every change here.
    private let store = SeshDataStore.shared

    /// Moves any pre-SwiftData UserDefaults data into SwiftData exactly once.
    private func migrateFromUserDefaultsIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: migratedKey) else { return }
        guard store.isEmpty else { d.set(true, forKey: migratedKey); return }

        var le: [JournalEntry] = []; var lt: [HighThought] = []
        if let data = d.data(forKey: entriesKey),
           let v = try? Self.jsonDecoder.decode([JournalEntry].self, from: data) { le = v }
        if let data = d.data(forKey: thoughtsKey),
           let v = try? Self.jsonDecoder.decode([HighThought].self, from: data) { lt = v }
        if !le.isEmpty || !lt.isEmpty {
            store.replaceAll(entries: le, thoughts: lt)
        }
        d.set(true, forKey: migratedKey)
    }

    /// Re-read from the local store.
    func reload() { load() }

    /// Conflict-aware merge: union local + incoming entries/thoughts by id
    /// so simultaneous edits on two devices don't clobber each other (instead of
    /// last-write-wins on the whole array). The newest copy of any duplicate id
    /// wins by date; everything else is unioned. The merged result is written to
    /// both SwiftData (local) and iCloud (so both devices converge).
    func mergeFromStorage() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: entriesKey),
           let incoming = try? Self.jsonDecoder.decode([JournalEntry].self, from: data) {
            entries = Self.mergeByID(local: entries, incoming: incoming, id: { $0.id }, date: { $0.date })
        }
        if let data = d.data(forKey: thoughtsKey),
           let incoming = try? Self.jsonDecoder.decode([HighThought].self, from: data) {
            thoughts = Self.mergeByID(local: thoughts, incoming: incoming, id: { $0.id }, date: { $0.date })
        }
        if let name = d.string(forKey: nameKey), !name.isEmpty { userName = name }
        // Converge: persist the merged set locally and push back up.
        // (#9) Record-level sync instead of a destructive replaceAll.
        store.sync(entries: entries, thoughts: thoughts)
        pushToCloud()
        lastSyncedAt = Date()
    }

    /// Union two collections by id, preferring the newer item for duplicates,
    /// returned newest-first. Internal for unit testing (#16).
    static func mergeByID<T>(local: [T], incoming: [T],
                                     id: (T) -> UUID, date: (T) -> Date) -> [T] {
        var byID: [UUID: T] = [:]
        for item in local { byID[id(item)] = item }
        for item in incoming {
            if let existing = byID[id(item)] {
                if date(item) >= date(existing) { byID[id(item)] = item }
            } else {
                byID[id(item)] = item
            }
        }
        return byID.values.sorted { date($0) > date($1) }
    }

    // MARK: Entry CRUD

    func add(_ entry: JournalEntry) { entries.insert(entry, at: 0); save() }
    func delete(_ entry: JournalEntry) {
        PhotoStore.delete(entry.photoName)
        entries.removeAll { $0.id == entry.id }
        save()
    }
    /// Insert or update in place (used by the edit flow).
    func upsert(_ entry: JournalEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        save()
    }
    func toggleFavorite(_ entry: JournalEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].category = entries[i].category == .personalFaves ? nil : .personalFaves
        save()
    }

    /// Canonical display name for a strain already in the log (preserves casing).
    func canonicalStrainName(_ raw: String) -> String {
        let key = normalized(raw)
        return entries.first { normalized($0.strain) == key }?.strain ?? raw
    }

    // MARK: Thought CRUD

    func addThought(_ t: HighThought) { thoughts.insert(t, at: 0); save() }
    func deleteThought(_ t: HighThought) { thoughts.removeAll { $0.id == t.id }; save() }
    func updateThought(_ t: HighThought) {
        guard let i = thoughts.firstIndex(where: { $0.id == t.id }) else { return }
        thoughts[i] = t; save()
    }
    func toggleThoughtFavorite(_ t: HighThought) {
        guard let i = thoughts.firstIndex(where: { $0.id == t.id }) else { return }
        thoughts[i].isFavorite.toggle()
        save()
    }

    // MARK: Maintenance

    /// Wipes all journal data and associated photos.
    func clearAll() {
        for e in entries { PhotoStore.delete(e.photoName) }
        entries.removeAll(); thoughts.removeAll()
        store.wipe()
        pushToCloud()
    }

    /// Full reset: clears data, restores the default identity, and returns the
    /// app to a fresh first-launch state (re-shows onboarding, allows reseeding).
    /// Used by "Reset All Data & Log Out".
    func resetEverything() {
        clearAll()
        userName = "Alex"
        let d = UserDefaults.standard
        d.removeObject(forKey: nameKey)
        d.removeObject(forKey: seededKey)      // allow first-launch seed again
        d.removeObject(forKey: "ht.onboarded.v1") // re-show Home onboarding hint
        d.synchronize()
    }

    // MARK: Derived stats

    var sessionsLogged: Int { entries.count }

    var uniqueStrains: Int {
        Set(entries.map { normalized($0.strain) }).count
    }

    var thisMonthSpent: Double {
        let cal = Calendar.current
        let now = Date()
        return entries.reduce(into: 0.0) { sum, e in
            if let price = e.price, cal.isDate(e.date, equalTo: now, toGranularity: .month) {
                sum += price
            }
        }
    }

    var totalSpent: Double {
        // Spend now comes from the stash/purchase log. Fall back to legacy
        // per-entry prices for any entries logged before the stash existed.
        let purchaseTotal = purchases.map(\.cost).reduce(0, +)
        let legacy = entries.compactMap(\.price).reduce(0, +)
        return purchaseTotal + legacy
    }

    // MARK: Stash / purchases (#stash)

    var purchases: [Purchase] = []
    private let purchasesKey = DefaultsKey.purchases

    /// Total amount remaining across all non-empty purchases (in mixed units;
    /// shown per-purchase in the UI). Used for the Home "in your stash" summary.
    var stashRemaining: [Purchase] { purchases.filter { !$0.isEmpty }.sorted { $0.date > $1.date } }

    func addPurchase(_ p: Purchase) {
        purchases.insert(p, at: 0)
        savePurchases()
    }
    func updatePurchase(_ p: Purchase) {
        if let i = purchases.firstIndex(where: { $0.id == p.id }) { purchases[i] = p; savePurchases() }
    }
    func deletePurchase(_ p: Purchase) {
        purchases.removeAll { $0.id == p.id }
        savePurchases()
    }
    /// Draw down `amount` from a purchase as it's consumed in a sesh.
    func consume(_ amount: Double, from purchaseID: UUID) {
        guard amount > 0, let i = purchases.firstIndex(where: { $0.id == purchaseID }) else { return }
        purchases[i].used = min(purchases[i].amount, purchases[i].used + amount)
        savePurchases()
    }
    private func savePurchases() {
        // (#10) Record-level SwiftData storage; UserDefaults no longer grows
        // with the stash. iCloud KVS mirror kept for cross-device sync.
        store.syncCollection("purchases", items: purchases.compactMap { p in
            guard let data = try? Self.jsonEncoder.encode(p) else { return nil }
            return (id: p.id.uuidString, date: p.date, payload: data)
        })
        if let data = try? Self.jsonEncoder.encode(purchases) {
            CloudSync.set(data, forKey: purchasesKey)
        }
    }
    private func loadPurchases() {
        let payloads = store.recordPayloads(in: "purchases")
        if !payloads.isEmpty {
            purchases = payloads.compactMap { try? Self.jsonDecoder.decode(Purchase.self, from: $0) }
                .sorted { $0.date > $1.date }
        } else if let data = UserDefaults.standard.data(forKey: purchasesKey),
                  let v = try? Self.jsonDecoder.decode([Purchase].self, from: data) {
            // One-time migration out of UserDefaults (#10).
            purchases = v
            savePurchases()
            UserDefaults.standard.removeObject(forKey: purchasesKey)
        }
        loadGoals()
    }

    // MARK: Goals (#goals — "smoke less", "spend less", etc.)

    var goals: [SeshGoal] = []
    private let goalsKey = "ht.goals.v1"

    func addGoal(_ g: SeshGoal) { goals.insert(g, at: 0); saveGoals() }
    func updateGoal(_ g: SeshGoal) {
        if let i = goals.firstIndex(where: { $0.id == g.id }) { goals[i] = g; saveGoals() }
    }
    func deleteGoal(_ g: SeshGoal) { goals.removeAll { $0.id == g.id }; saveGoals() }
    private func saveGoals() {
        if let data = try? Self.jsonEncoder.encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
            CloudSync.set(data, forKey: goalsKey)
        }
    }
    private func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let v = try? Self.jsonDecoder.decode([SeshGoal].self, from: data) {
            goals = v
        }
        loadQuickActions()
    }

    // MARK: Home Quick Actions (personalizable, ordered, uncapped)

    var quickActions: [HomeQuickAction] = HomeQuickAction.defaults
    private let quickActionsKey = "ht.quickActions.v1"

    func addQuickAction(_ a: HomeQuickAction) {
        guard !quickActions.contains(a) else { return }
        quickActions.append(a); saveQuickActions()
    }
    func removeQuickActions(at offsets: IndexSet) {
        quickActions.remove(atOffsets: offsets); saveQuickActions()
    }
    func moveQuickAction(from: IndexSet, to: Int) {
        quickActions.move(fromOffsets: from, toOffset: to); saveQuickActions()
    }
    private func saveQuickActions() {
        if let data = try? Self.jsonEncoder.encode(quickActions) {
            UserDefaults.standard.set(data, forKey: quickActionsKey)
            CloudSync.set(data, forKey: quickActionsKey)
        }
    }
    private func loadQuickActions() {
        if let data = UserDefaults.standard.data(forKey: quickActionsKey),
           let v = try? Self.jsonDecoder.decode([HomeQuickAction].self, from: data) {
            quickActions = v
        }
        loadSessionTools()
    }

    // MARK: Session Tools (in-sesh, personalizable, separate from Quick Actions)

    var sessionTools: [SessionTool] = SessionTool.defaults
    private let sessionToolsKey = "ht.sessionTools.v1"

    func addSessionTool(_ t: SessionTool) {
        guard !sessionTools.contains(t) else { return }
        sessionTools.append(t); saveSessionTools()
    }
    func removeSessionTools(at offsets: IndexSet) {
        sessionTools.remove(atOffsets: offsets); saveSessionTools()
    }
    func moveSessionTool(from: IndexSet, to: Int) {
        sessionTools.move(fromOffsets: from, toOffset: to); saveSessionTools()
    }
    private func saveSessionTools() {
        if let data = try? Self.jsonEncoder.encode(sessionTools) {
            UserDefaults.standard.set(data, forKey: sessionToolsKey)
            CloudSync.set(data, forKey: sessionToolsKey)
        }
    }
    private func loadSessionTools() {
        if let data = UserDefaults.standard.data(forKey: sessionToolsKey),
           let v = try? Self.jsonDecoder.decode([SessionTool].self, from: data) {
            sessionTools = v
        }
        loadSongPlays()
    }

    /// The date of the most recent logged sesh (entry), if any.
    var lastSeshDate: Date? {
        entries.map(\.date).max()
    }

    /// A short "time since last sesh" phrase for the status area, e.g. "5h ago".
    /// Returns nil when there are no sessions yet.
    var timeSinceLastSeshPhrase: String? {
        guard let last = lastSeshDate else { return nil }
        let secs = max(0, Int(Date().timeIntervalSince(last)))
        if secs < 60 { return "just now" }
        let m = secs / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    // MARK: Music memory (songs captured during seshes, tied to strains)

    var songPlays: [StrainSongPlay] = []
    private let songPlaysKey = "ht.songPlays.v1"

    /// Record a song captured during a sesh, tied to the strain. De-dupes a rapid
    /// repeat of the same song+strain within a couple minutes.
    func recordSongPlay(_ play: StrainSongPlay) {
        if let recent = songPlays.first,
           recent.title == play.title, recent.artist == play.artist,
           recent.strainName == play.strainName,
           Date().timeIntervalSince(recent.date) < 120 {
            return
        }
        songPlays.insert(play, at: 0)
        saveSongPlays()
    }
    private func saveSongPlays() {
        // (#10) Song history lives in SwiftData records, not preferences.
        store.syncCollection("songPlays", items: songPlays.compactMap { play in
            guard let data = try? Self.jsonEncoder.encode(play) else { return nil }
            return (id: play.id.uuidString, date: play.date, payload: data)
        })
        if let data = try? Self.jsonEncoder.encode(Array(songPlays.prefix(300))) {
            CloudSync.set(data, forKey: songPlaysKey)
        }
    }
    private func loadSongPlays() {
        let payloads = store.recordPayloads(in: "songPlays")
        if !payloads.isEmpty {
            songPlays = payloads.compactMap { try? Self.jsonDecoder.decode(StrainSongPlay.self, from: $0) }
                .sorted { $0.date > $1.date }
        } else if let data = UserDefaults.standard.data(forKey: songPlaysKey),
                  let v = try? Self.jsonDecoder.decode([StrainSongPlay].self, from: data) {
            songPlays = v
            saveSongPlays()
            UserDefaults.standard.removeObject(forKey: songPlaysKey)
        }
    }

    // MARK: Custom categories (#custom categories)

    private let customCatsKey = DefaultsKey.customCategories
    /// User-defined category names (alongside the built-in SeshCategory set).
    var customCategories: [String] = []

    /// All category names available for assignment: built-ins + custom.
    var allCategoryNames: [String] {
        SeshCategory.allCases.map(\.rawValue) + customCategories
    }

    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Don't duplicate a built-in or existing custom name (case-insensitive).
        let exists = allCategoryNames.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        guard !exists else { return }
        customCategories.append(trimmed)
        saveCustomCategories()
    }

    func renameCategory(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = customCategories.firstIndex(of: old) else { return }
        customCategories[i] = trimmed
        // Re-point any entries using the old custom name.
        for idx in entries.indices where entries[idx].customCategory == old {
            entries[idx].customCategory = trimmed
        }
        saveCustomCategories(); save()
    }

    func deleteCategory(_ name: String) {
        customCategories.removeAll { $0 == name }
        // Clear it from any entries that used it.
        for idx in entries.indices where entries[idx].customCategory == name {
            entries[idx].customCategory = nil
        }
        saveCustomCategories(); save()
    }

    private func saveCustomCategories() {
        if let data = try? Self.jsonEncoder.encode(customCategories) {
            UserDefaults.standard.set(data, forKey: customCatsKey)
            CloudSync.set(data, forKey: customCatsKey)
        }
    }
    private func loadCustomCategories() {
        if let data = UserDefaults.standard.data(forKey: customCatsKey),
           let v = try? Self.jsonDecoder.decode([String].self, from: data) {
            customCategories = v
        }
    }

    // MARK: Champions (#champions — "Your Current Champions")

    /// The most recent strain crowned for each champion category (from entries
    /// that set a champion). Latest entry wins if a category repeats.
    func championStrains() -> [(champion: Champion, strain: String)] {
        var latest: [String: (Date, String)] = [:]
        for e in entries {
            guard let champ = e.champion, !e.strain.isEmpty else { continue }
            if let existing = latest[champ], existing.0 >= e.date { continue }
            latest[champ] = (e.date, e.strain)
        }
        return Champion.allCases.compactMap { c in
            guard let hit = latest[c.rawValue] else { return nil }
            return (c, hit.1)
        }
    }


    // MARK: Resumable live sesh (#persisted sessions)

    private let liveSeshKey = DefaultsKey.liveSesh
    /// The currently-running live sesh, if any. Persisted so navigating away from
    /// the Cyph tab (or backgrounding the app) doesn't end it — it can be resumed.
    var liveSesh: LiveSeshState? = nil

    var hasActiveSesh: Bool { liveSesh != nil }

    func saveLiveSesh(_ state: LiveSeshState) {
        liveSesh = state
        if let data = try? Self.jsonEncoder.encode(state) {
            UserDefaults.standard.set(data, forKey: liveSeshKey)
        }
        // (#App18) Opt-in water / check-in reminders while a sesh is live.
        SeshReminders.scheduleForActiveSesh()
    }
    func clearLiveSesh() {
        liveSesh = nil
        UserDefaults.standard.removeObject(forKey: liveSeshKey)
        SeshReminders.cancel()   // (#App18)
    }
    private func loadLiveSesh() {
        if let data = UserDefaults.standard.data(forKey: liveSeshKey),
           let v = try? Self.jsonDecoder.decode(LiveSeshState.self, from: data) {
            // Safety net: a sesh that's been "active" for an implausibly long time
            // (e.g. the app was killed mid-sesh and never ended) is treated as
            // abandoned and cleared, so it doesn't linger across launches forever.
            if Date().timeIntervalSince(v.startedAt) > 12 * 60 * 60 {
                UserDefaults.standard.removeObject(forKey: liveSeshKey)
                liveSesh = nil
            } else {
                liveSesh = v
            }
        }
    }

    var averageRating: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.rating).reduce(0, +) / Double(entries.count)
    }

    var currentStreak: Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    var highestRatedStrain: String? {
        entries.max(by: { $0.rating < $1.rating })?.strain
    }

    var highestRating: Double {
        entries.map(\.rating).max() ?? 0
    }

    var mostPurchasedStrain: String? {
        var counts: [String: Int] = [:]
        for e in entries { counts[normalized(e.strain), default: 0] += 1 }
        guard let key = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return entries.first { normalized($0.strain) == key }?.strain
    }

    /// Best strain for a given mood (used for "Most Relaxing" etc.).
    func topStrain(for mood: Mood) -> String? {
        var counts: [String: Int] = [:]
        for e in entries where e.mood == mood {
            counts[normalized(e.strain), default: 0] += 1
        }
        guard let key = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return entries.first { normalized($0.strain) == key }?.strain
    }

    var insights: [StrainInsight] {
        let groups = Dictionary(grouping: entries, by: { normalized($0.strain) })
        return groups.compactMap { _, items -> StrainInsight? in
            guard let first = items.first else { return nil }
            return StrainInsight(
                name: first.strain,
                sessions: items.count,
                averageRating: items.map(\.rating).reduce(0, +) / Double(items.count)
            )
        }
        .sorted { $0.sessions > $1.sessions }
    }

    /// All entries for a given strain name (case-insensitive), newest first.
    func entries(forStrain name: String) -> [JournalEntry] {
        let key = normalized(name)
        return entries.filter { normalized($0.strain) == key }
    }

    // MARK: Trends (time series)

    /// Ratings of the last `count` sessions, oldest→newest (for a sparkline).
    func recentRatings(count: Int = 12) -> [Double] {
        entries.sorted { $0.date < $1.date }.suffix(count).map(\.rating)
    }

    /// Sessions logged per week for the last `weeks` weeks, oldest→newest.
    func sessionsPerWeek(weeks: Int = 8) -> [(label: String, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        var result: [(String, Int)] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -w, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: weekStart) else { continue }
            let count = entries.count(where: { interval.contains($0.date) })
            let label = "\(cal.component(.month, from: interval.start))/\(cal.component(.day, from: interval.start))"
            result.append((label, count))
        }
        return result
    }

    /// Average rating this week vs last week (for a trend arrow).
    var ratingTrend: (thisWeek: Double, lastWeek: Double) {
        let cal = Calendar.current
        func avg(weeksAgo: Int) -> Double {
            guard let anchor = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()),
                  let interval = cal.dateInterval(of: .weekOfYear, for: anchor) else { return 0 }
            let r = entries.filter { interval.contains($0.date) }.map(\.rating)
            return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
        }
        return (avg(weeksAgo: 0), avg(weeksAgo: 1))
    }

    /// Days since the last logged session (nil if none).
    var daysSinceLastSesh: Int? {
        guard let last = entries.map(\.date).max() else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    /// The longest tracking streak ever achieved (for permanent milestones),
    /// computed from the set of distinct calendar days that have entries.
    var bestStreakEver: Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) }).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1, run = 1
        for i in 1..<max(1, days.count) {
            if let gap = cal.dateComponents([.day], from: days[i-1], to: days[i]).day, gap == 1 {
                run += 1; best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    // Cyph participation counters (incremented from the social flow; the Worker
    // doesn't report these historically, so they accrue from first use). #Journey
    private let cyphJoinedKey = DefaultsKey.cyphJoined
    private let cyphHostedKey = DefaultsKey.cyphHosted
    var cyphsJoinedCount: Int {
        get { UserDefaults.standard.integer(forKey: cyphJoinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: cyphJoinedKey) }
    }
    var cyphsHostedCount: Int {
        get { UserDefaults.standard.integer(forKey: cyphHostedKey) }
        set { UserDefaults.standard.set(newValue, forKey: cyphHostedKey) }
    }
    func recordCyphJoined() { cyphsJoinedCount += 1 }
    func recordCyphHosted() { cyphsHostedCount += 1; cyphsJoinedCount += 1 }

    // Roll-time records (Fastest Blunt / Joint Rolled, in seconds). #PersonalRecords
    private let fastestJointKey = DefaultsKey.fastestJoint
    private let fastestBluntKey = DefaultsKey.fastestBlunt
    /// Fastest joint roll in seconds, or nil if never set.
    var fastestJointRoll: Int? {
        let v = UserDefaults.standard.integer(forKey: fastestJointKey); return v > 0 ? v : nil
    }
    var fastestBluntRoll: Int? {
        let v = UserDefaults.standard.integer(forKey: fastestBluntKey); return v > 0 ? v : nil
    }
    /// Submit a completed roll time; keeps it only if it beats the current best.
    /// Returns true if a new record was set.
    @discardableResult
    func submitRollTime(seconds: Int, method: String) -> Bool {
        guard seconds > 0 else { return false }
        let isBlunt = method.lowercased().contains("blunt")
        let key = isBlunt ? fastestBluntKey : fastestJointKey
        let current = UserDefaults.standard.integer(forKey: key)
        if current == 0 || seconds < current {
            UserDefaults.standard.set(seconds, forKey: key)
            return true
        }
        return false
    }

    // MARK: Tolerance & T-break (#2)

    private let tBreakKey = DefaultsKey.tBreakStart
    private let tBreakGoalKey = DefaultsKey.tBreakGoal

    /// When the current tolerance break started, or nil if not on one.
    var tBreakStart: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: tBreakKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: tBreakKey)
        }
    }

    /// Optional goal length for the break, in days (default 7).
    var tBreakGoalDays: Int {
        get { let g = UserDefaults.standard.integer(forKey: tBreakGoalKey); return g > 0 ? g : 7 }
        set { UserDefaults.standard.set(newValue, forKey: tBreakGoalKey) }
    }

    var isOnTBreak: Bool { tBreakStart != nil }

    /// Whole days elapsed on the current break.
    var tBreakDays: Int {
        guard let start = tBreakStart else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
    }

    /// Progress toward the break goal, 0...1.
    var tBreakProgress: Double {
        guard tBreakGoalDays > 0 else { return 0 }
        return min(1, Double(tBreakDays) / Double(tBreakGoalDays))
    }

    func startTBreak(goalDays: Int = 7) {
        tBreakGoalDays = goalDays
        tBreakStart = Date()
    }
    func endTBreak() { tBreakStart = nil }

    /// A rough tolerance estimate (0...1) from how frequently you've logged in the
    /// last 14 days. Heavier recent use → higher tolerance. Not medical advice —
    /// just a directional gauge that resets as you take breaks.
    var toleranceEstimate: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = entries.filter { $0.date >= cutoff }
        // ~2+ sessions/day over 14 days reads as high (28 sessions → 1.0).
        return min(1, Double(recent.count) / 28.0)
    }

    var toleranceLabel: String {
        switch toleranceEstimate {
        case ..<0.2:  return "Low"
        case ..<0.45: return "Moderate"
        case ..<0.7:  return "Elevated"
        default:       return "High"
        }
    }

    /// Most recent date a strain was logged.
    func lastUsed(forStrain name: String) -> Date? {
        entries(forStrain: name).map(\.date).max()
    }

    /// The mood most often felt with a strain.
    func bestMood(forStrain name: String) -> Mood? {
        let moods = entries(forStrain: name).compactMap(\.mood)
        let counts = Dictionary(grouping: moods, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// Recent ratings (oldest→newest) for a strain, for sparklines.
    func recentRatings(forStrain name: String, limit: Int = 8) -> [Double] {
        let sorted = entries(forStrain: name).sorted { $0.date < $1.date }
        return sorted.suffix(limit).map(\.rating)
    }

    // MARK: Personal records (#PersonalRecords)

    /// Longest single sesh by recorded duration.
    var longestSesh: (minutes: Int, strain: String)? {
        guard let e = entries.filter({ ($0.durationMinutes ?? 0) > 0 }).max(by: { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }),
              let m = e.durationMinutes else { return nil }
        return (m, e.strain)
    }
    /// Shortest single sesh by recorded duration.
    var shortestSesh: (minutes: Int, strain: String)? {
        guard let e = entries.filter({ ($0.durationMinutes ?? 0) > 0 }).min(by: { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }),
              let m = e.durationMinutes else { return nil }
        return (m, e.strain)
    }
    /// Strain logged the most times.
    var mostLoggedStrain: (name: String, count: Int)? {
        let counts = Dictionary(grouping: entries, by: { $0.strain.lowercased() })
        guard let top = counts.max(by: { $0.value.count < $1.value.count }), let first = top.value.first else { return nil }
        return (first.strain, top.value.count)
    }
    /// Strain whose opinion improved the most (first vs latest rating, ≥3 logs).
    var mostImprovedStrain: (name: String, from: Double, to: Double)? {
        var best: (String, Double, Double, Double)? = nil   // name, from, to, delta
        for (_, group) in Dictionary(grouping: entries, by: { $0.strain.lowercased() }) {
            guard group.count >= 3 else { continue }
            let sorted = group.sorted { $0.date < $1.date }
            guard let firstEntry = sorted.first, let lastEntry = sorted.last else { continue }
            let from = firstEntry.rating, to = lastEntry.rating
            let delta = to - from
            if delta > (best?.3 ?? 0) { best = (firstEntry.strain, from, to, delta) }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2)
    }
    /// Most journal entries logged on a single calendar day.
    var mostEntriesInADay: Int {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: entries, by: { cal.startOfDay(for: $0.date) })
        return byDay.values.map(\.count).max() ?? 0
    }
    /// Longest thought by word count.
    var longestThought: Int {
        thoughts.map { $0.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count }.max() ?? 0
    }
    /// Spending records.
    var highestPurchase: Double? { entries.compactMap(\.price).filter { $0 > 0 }.max() }
    var cheapestPurchase: Double? { entries.compactMap(\.price).filter { $0 > 0 }.min() }
    /// Spend grouped by calendar month → (highest, lowest) among months with spend.
    var monthlySpendExtremes: (high: Double, low: Double)? {
        let cal = Calendar.current
        var byMonth: [DateComponents: Double] = [:]
        for e in entries {
            guard let p = e.price, p > 0 else { continue }
            let key = cal.dateComponents([.year, .month], from: e.date)
            byMonth[key, default: 0] += p
        }
        let totals = byMonth.values.filter { $0 > 0 }
        guard let hi = totals.max(), let lo = totals.min() else { return nil }
        return (hi, lo)
    }

    // MARK: Yearly recap (#YearlyRecap)

    /// Years (descending) that have at least one entry — for the recap picker.
    var yearsWithData: [Int] {
        let cal = Calendar.current
        let years = Set(entries.map { cal.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    /// A full "Your sesh Year" summary for the given calendar year.
    func yearRecap(_ year: Int) -> YearRecap {
        let cal = Calendar.current
        let yEntries = entries.filter { cal.component(.year, from: $0.date) == year }
        let yThoughts = thoughts.filter { cal.component(.year, from: $0.date) == year }

        // Favorite strain (most logged this year)
        let strainCounts = Dictionary(grouping: yEntries, by: { $0.strain.lowercased() })
        let favStrain = strainCounts.max(by: { $0.value.count < $1.value.count })?.value.first?.strain

        // Favorite effect (most tagged this year)
        let effectList = yEntries.flatMap { $0.effects ?? [] }
        let effectCounts = Dictionary(grouping: effectList, by: { $0 }).mapValues(\.count)
        let favEffect = effectCounts.max(by: { $0.value < $1.value })?.key

        // Most active month
        var byMonth: [Int: Int] = [:]
        for e in yEntries { byMonth[cal.component(.month, from: e.date), default: 0] += 1 }
        let topMonth = byMonth.max(by: { $0.value < $1.value })?.key
        let monthName = topMonth.flatMap { m -> String? in
            var c = DateComponents(); c.year = year; c.month = m
            guard let d = cal.date(from: c) else { return nil }
            return Fmt.monthName(d)
        }

        // Thought of the year: the longest one (proxy for most substantial)
        let thoughtOfYear = yThoughts.max(by: {
            $0.text.split(whereSeparator: { $0 == " " }).count < $1.text.split(whereSeparator: { $0 == " " }).count
        })?.text

        let spent = yEntries.compactMap(\.price).reduce(0, +)
        let unique = Set(yEntries.map { $0.strain.lowercased() }).count

        return YearRecap(
            year: year,
            sessions: yEntries.count,
            favoriteStrain: favStrain,
            favoriteEffect: favEffect,
            mostActiveMonth: monthName,
            thoughtOfYear: thoughtOfYear,
            moneySpent: spent,
            uniqueStrains: unique)
    }

    // MARK: This-week stats (Home)

    private var weekStart: Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
    }
    var sessionsThisWeek: Int { entries.count(where: { $0.date >= weekStart }) }
    var avgRatingThisWeek: Double {
        let r = entries.filter { $0.date >= weekStart }.map(\.rating)
        return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }
    var spentThisWeek: Double {
        entries.filter { $0.date >= weekStart }.compactMap(\.price).reduce(0, +)
    }

    /// Next streak milestone (3 / 7 / 14 / 30 / 60 / 90) above the current streak.
    var nextStreakMilestone: Int {
        let s = currentStreak
        return [3, 7, 14, 30, 60, 90, 180, 365].first { $0 > s } ?? (s + 1)
    }

    /// Spending grouped into weekly buckets for the current month chart.
    var weeklySpend: [(label: String, amount: Double)] {
        let cal = Calendar.current
        let labels = ["May 1", "May 8", "May 15", "May 22", "May 29"]
        // Bucket by day-of-month into 5 weekly windows.
        var buckets = [Double](repeating: 0, count: 5)
        for e in entries {
            guard let price = e.price else { continue }
            let day = cal.component(.day, from: e.date)
            let idx = min(4, max(0, (day - 1) / 7))
            buckets[idx] += price
        }
        return zip(labels, buckets).map { ($0, $1) }
    }

    var recentTransactions: [JournalEntry] {
        Array(entries.lazy.filter { $0.price != nil }.prefix(6))
    }

    private func normalized(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: Persistence

    /// Persist the full working set. SwiftData (local, durable) is written
    /// immediately — it's the source of truth on this device and the write is
    /// cheap. The iCloud KVS mirror is DEBOUNCED (#1): a burst of edits (e.g.
    /// typing, multi-select taps) coalesces into a single cloud push ~0.8s after
    /// the last change, instead of re-encoding and uploading the entire dataset
    /// on every keystroke. KVS is rate-limited, so this matters as data grows.
    func save() {
        // (#9) Record-level sync — no longer wipes and rewrites the whole
        // SwiftData database on every save.
        store.sync(entries: entries, thoughts: thoughts)
        scheduleCloudPush()
    }

    private var cloudPushTask: Task<Void, Never>?

    private func scheduleCloudPush() {
        cloudPushTask?.cancel()
        cloudPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.pushToCloud()
        }
    }

    /// Mirror the current set into iCloud key-value storage for other devices.
    /// Encode failures are logged (#2) rather than silently dropped — a silent
    /// failure here is exactly what "my sessions vanished" looks like.
    private func pushToCloud() {
        if let data = Persist.encode(entries, label: "entries")  { CloudSync.set(data, forKey: entriesKey) }
        if let data = Persist.encode(thoughts, label: "thoughts") { CloudSync.set(data, forKey: thoughtsKey) }
        CloudSync.set(userName, forKey: nameKey)
        lastSyncedAt = Date()
    }

    private func load() {
        entries = store.fetchEntries()
        thoughts = store.fetchThoughts()
        if let n = UserDefaults.standard.string(forKey: nameKey) { userName = n }
    }

    // MARK: Sample data (first launch only, to mirror the mockup)

    private func seedIfNeeded() {
        // The app ships with NO sample journal data — users start with a clean
        // slate. (Kept as a no-op so the one-time flag still settles.)
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}
