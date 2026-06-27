//
//  JournalView.swift
//  HighThoughts
//

import SwiftUI

enum JournalSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case rating = "Highest rated"
    case price  = "Price"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .newest: return "clock"
        case .rating: return "star"
        case .price:  return "dollarsign"
        }
    }
}

/// A single item in the unified Log feed: either a logged sesh or a standalone
/// thought. (#combine Log) Sorted together by date.
enum LogItem: Identifiable {
    case entry(JournalEntry)
    case thought(HighThought)

    var id: String {
        switch self {
        case .entry(let e):   return "e_\(e.id.uuidString)"
        case .thought(let t): return "t_\(t.id.uuidString)"
        }
    }
    var date: Date {
        switch self {
        case .entry(let e):   return e.date
        case .thought(let t): return t.date
        }
    }
}

struct JournalView: View {
    @Environment(AppSession.self) private var session
    @State private var query = ""
    @State private var filter = "All"
    @State private var sort: JournalSort = .newest
    @State private var editing: JournalEntry?
    @State private var editingThought: HighThought?
    @State private var effectFilter: String?     // filter by an effect
    @State private var minRating = 0              // 0 = any
    @State private var showFilters = false
    @State private var showNewLog = false
    @State private var showNewThought = false
    @State private var showLogChooser = false
    @State private var showManageCategories = false

    private var filters: [String] {
        ["All", "Thoughts", "Favorites", "Reliable", "Situational", "Never Again"] + session.customCategories
    }

    /// Effects that actually appear in the user's entries (for the filter sheet).
    private var availableEffects: [String] {
        let all = session.entries.flatMap { $0.effects ?? [] }
        return Array(Set(all)).sorted()
    }

    private var activeRefinements: Int {
        (effectFilter != nil ? 1 : 0) + (minRating > 0 ? 1 : 0)
    }

    private var filtered: [JournalEntry] {
        let base = session.entries.filter { matches($0) }
        switch sort {
        case .newest: return base.sorted { $0.date > $1.date }
        case .rating: return base.sorted { $0.rating > $1.rating }
        case .price:  return base.sorted { ($0.price ?? 0) > ($1.price ?? 0) }
        }
    }

    private func matches(_ e: JournalEntry) -> Bool {
        matchesQuery(e) && matchesFilter(e) && matchesEffect(e) && matchesRating(e)
    }

    private func matchesQuery(_ e: JournalEntry) -> Bool {
        guard !query.isEmpty else { return true }
        return e.strain.localizedCaseInsensitiveContains(query)
            || e.notes.localizedCaseInsensitiveContains(query)
            || e.method.localizedCaseInsensitiveContains(query)
    }

    private func matchesFilter(_ e: JournalEntry) -> Bool {
        switch filter {
        case "All":         return true
        case "Favorites":    return e.category == .personalFaves
        case "Reliable":     return e.category == .goodEnough
        case "Situational":  return e.category == .lastResort
        case "Never Again":  return e.category == .neverAgain
        default:            return e.customCategory == filter   // custom category name
        }
    }

    private func matchesEffect(_ e: JournalEntry) -> Bool {
        guard let effectFilter else { return true }
        return e.effects?.contains(effectFilter) ?? false
    }

    private func matchesRating(_ e: JournalEntry) -> Bool {
        e.rating >= Double(minRating)
    }

    /// Grouped by relative day (only when sorting by date).
    private var grouped: [(String, [JournalEntry])] {
        guard sort == .newest else { return [("", filtered)] }
        var order: [String] = []
        var map: [String: [JournalEntry]] = [:]
        for e in filtered {
            let key = relativeDay(e.date)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    // MARK: Unified Log feed (#combine Log)

    /// IDs of thoughts already attached to a sesh, so they aren't shown twice.
    private var attachedThoughtIDs: Set<UUID> {
        Set(session.entries.compactMap { $0.attachedThoughtID })
    }

    /// Standalone thoughts (not attached to a sesh), matched against the search.
    private var standaloneThoughts: [HighThought] {
        session.thoughts.filter { t in
            !attachedThoughtIDs.contains(t.id) &&
            (query.isEmpty || t.text.localizedCaseInsensitiveContains(query))
        }
    }

    /// The combined, date-sorted feed of sessions + standalone thoughts.
    /// Respects the current filter: category filters and rating/effect refinements
    /// only apply to sessions, so when any of those is active, thoughts are hidden.
    /// The dedicated "Thoughts" chip shows thoughts only.
    private var feed: [LogItem] {
        let refining = effectFilter != nil || minRating > 0
        let showThoughts = (filter == "All" || filter == "Thoughts") && !refining
        let showEntries = filter != "Thoughts"

        var items: [LogItem] = []
        if showEntries { items += filtered.map { LogItem.entry($0) } }
        if showThoughts { items += standaloneThoughts.map { LogItem.thought($0) } }
        return items.sorted { $0.date > $1.date }
    }

    /// The feed grouped by relative day (date sort only).
    private var groupedFeed: [(String, [LogItem])] {
        guard sort == .newest else { return [("", feed)] }
        var order: [String] = []
        var map: [String: [LogItem]] = [:]
        for item in feed {
            let key = relativeDay(item.date)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                headerBar
                searchBar
                UnderlineTabs(items: filters, selection: $filter)
                    .padding(.horizontal, 18).padding(.bottom, 6)
                resultSummaryBar
                feedContent
            }
        }
        .sheet(item: $editing) { entry in
            LogSeshView(editing: entry).environment(session)
        }
        .sheet(item: $editingThought) { t in
            ComposeThoughtView(editing: t).environment(session).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFilters) {
            JournalFilterSheet(effectFilter: $effectFilter, minRating: $minRating,
                               availableEffects: availableEffects)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNewLog) {
            LogSeshView().environment(session)
        }
        .sheet(isPresented: $showNewThought) {
            ComposeThoughtView().environment(session).presentationDetents([.medium, .large])
        }
        .confirmationDialog("What do you want to log?", isPresented: $showLogChooser, titleVisibility: .visible) {
            Button("Log a Session") { showNewLog = true }
            Button("Log a Thought") { showNewThought = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView().environment(session)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var headerBar: some View {
        ZStack {
            Text("Journal")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            HStack {
                Image(systemName: "line.3.horizontal").font(.system(size: 20)).foregroundStyle(Palette.text)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(JournalSort.allCases) { s in
                            Label(s.rawValue, systemImage: s.symbol).tag(s)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 16)).foregroundStyle(Palette.text)
                }
                Button {
                    Haptics.tap(); showLogChooser = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New log")
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 14)
    }

    @ViewBuilder private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
                TextField("", text: $query,
                          prompt: Text("Search your sessions...").foregroundStyle(Palette.textTertiary))
                    .foregroundStyle(Palette.text)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))

            Button { showFilters = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18))
                        .foregroundStyle(activeRefinements > 0 ? Palette.onGreen : Palette.text)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(activeRefinements > 0 ? Palette.green : Palette.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    if activeRefinements > 0 {
                        Text("\(activeRefinements)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(Palette.moodAngry)).offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters")
            .accessibilityValue(activeRefinements > 0 ? "\(activeRefinements) active" : "none active")
        }
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    @ViewBuilder private var resultSummaryBar: some View {
        HStack {
            Text("\(filtered.count) \(filtered.count == 1 ? "session" : "sessions")")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Button { showManageCategories = true; Haptics.tap() } label: {
                Label("Categories", systemImage: "tag")
                    .font(.system(size: 12)).foregroundStyle(Palette.green)
            }.buttonStyle(.plain)
            Text("·").font(.system(size: 12)).foregroundStyle(Palette.textTertiary).padding(.horizontal, 2)
            Label(sort.rawValue, systemImage: sort.symbol)
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
    }

    @ViewBuilder private var feedContent: some View {
        if session.entries.isEmpty {
            EmptyStateView(icon: "doc.text",
                           title: "Nothing logged yet",
                           message: "Record your first session or capture a thought to start your log.",
                           actionTitle: "Add to Log", actionIcon: "plus",
                           action: { showLogChooser = true })
            Spacer()
        } else if filtered.isEmpty {
            EmptyStateView(icon: "magnifyingglass",
                           title: "Nothing matches",
                           message: "Try a different search or filter.",
                           actionTitle: activeRefinements > 0 || !query.isEmpty ? "Clear filters" : nil,
                           actionIcon: "xmark",
                           action: { query = ""; filter = "All"; effectFilter = nil; minRating = 0 })
            Spacer()
        } else {
            feedList
        }
    }

    @ViewBuilder private var feedList: some View {
        List {
            ForEach(groupedFeed, id: \.0) { day, items in
                Section {
                    ForEach(items) { item in
                        LogItemRow(item: item,
                                   onEditEntry: { editing = $0 },
                                   onEditThought: { editingThought = $0 })
                    }
                } header: {
                    if !day.isEmpty {
                        Text(day).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Color.clear.frame(height: 70).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - One row in the unified Log feed (split out so the feed type-checks fast)

private struct LogItemRow: View {
    @Environment(AppSession.self) private var session
    let item: LogItem
    let onEditEntry: (JournalEntry) -> Void
    let onEditThought: (HighThought) -> Void

    var body: some View {
        switch item {
        case .entry(let e):
            SessionCard(entry: e, seed: abs(e.id.hashValue % 60))
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onEditEntry(e) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.warning(); session.delete(e)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        Haptics.selection(); session.toggleFavorite(e)
                    } label: { Label("Favorite", systemImage: "heart") }
                    .tint(Palette.green)
                }
                .contextMenu {
                    Button { onEditEntry(e) } label: { Label("Edit", systemImage: "pencil") }
                    Button { session.toggleFavorite(e) } label: {
                        Label(e.category == .personalFaves ? "Remove favorite" : "Add to favorites", systemImage: "heart")
                    }
                    Button(role: .destructive) { session.delete(e) } label: { Label("Delete", systemImage: "trash") }
                }
        case .thought(let t):
            ThoughtCard(thought: t)
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onEditThought(t) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.warning(); session.deleteThought(t)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        Haptics.selection(); session.toggleThoughtFavorite(t)
                    } label: { Label("Favorite", systemImage: "star") }
                    .tint(Palette.gold)
                }
        }
    }
}

struct JournalFilterSheet: View {
    @Binding var effectFilter: String?
    @Binding var minRating: Int
    let availableEffects: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Filters").font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    Spacer()
                    Button("Reset") { effectFilter = nil; minRating = 0; Haptics.tap() }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.gold)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MINIMUM RATING").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                            HStack {
                                Text(minRating == 0 ? "Any rating" : "\(minRating)+ / 10")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Spacer()
                            }
                            Slider(value: Binding(get: { Double(minRating) }, set: { minRating = Int($0) }), in: 0...10, step: 1)
                                .tint(Palette.green)
                                .accessibilityValue(minRating == 0 ? "Any" : "\(minRating) or higher")
                        }

                        if !availableEffects.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("EFFECT").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                                FlowLayout(spacing: 8) {
                                    ForEach(availableEffects, id: \.self) { eff in
                                        let on = effectFilter == eff
                                        Button { effectFilter = on ? nil : eff; Haptics.selection() } label: {
                                            Text(eff).font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(on ? Palette.onGreen : Palette.text)
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(Capsule().fill(on ? Palette.green : Palette.field))
                                                .overlay(Capsule().stroke(on ? Color.clear : Palette.stroke, lineWidth: 1))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }

                PrimaryButton(title: "Show Results", icon: "checkmark") { dismiss() }
                    .padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
    }
}

struct SessionCard: View {
    @Environment(AppSession.self) private var session
    let entry: JournalEntry
    var seed: Int = 0

    var body: some View {
        DarkCard(padding: 12, radius: Radius.lg) {
            HStack(alignment: .top, spacing: 12) {
                StoredImage(name: entry.photoName, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.strain)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Button {
                            Haptics.selection(); session.toggleFavorite(entry)
                        } label: {
                            Image(systemName: entry.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 15))
                                .foregroundStyle(entry.isFavorite ? Palette.moodAngry : Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        RatingBadge(value: entry.rating)
                    }
                    Text(timeString(entry.date) + (entry.method.isEmpty ? "" : " · \(entry.method)"))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)

                    // Session type · duration · companions (spec additions)
                    if entry.sessionType != nil || entry.durationMinutes != nil || entry.companionLine != nil {
                        HStack(spacing: 8) {
                            if let type = entry.sessionType,
                               let st = SessionType(rawValue: type) {
                                Text(st.emoji + " " + st.rawValue).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            }
                            if let mins = entry.durationMinutes {
                                Text("· \(mins) min").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                        if let line = entry.companionLine {
                            Label(line, systemImage: "person.2.fill").font(.system(size: 11)).foregroundStyle(Palette.greenBright)
                        }
                    }

                    if entry.attachedThoughtID != nil {
                        Label("1 thought attached", systemImage: "lightbulb.fill")
                            .font(.system(size: 11)).foregroundStyle(Palette.gold)
                    }

                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.text.opacity(0.85))
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                    HStack(spacing: 8) {
                        if let mood = entry.mood { CategoryTag(text: mood.rawValue) }
                        if let cat = entry.category { CategoryTag(text: cat.rawValue) }
                        if let custom = entry.customCategory { CategoryTag(text: custom) }
                        if let price = entry.price { CategoryTag(text: Fmt.currency(price)) }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Manage custom categories (#custom categories)

struct ManageCategoriesView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: String? = nil
    @State private var renameText = ""

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Categories", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Add a new one
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "New category")
                            HStack(spacing: 8) {
                                TextField("", text: $newName,
                                          prompt: Text("e.g. Daytime, Sleep, Social").foregroundStyle(Palette.textTertiary))
                                    .foregroundStyle(Palette.text).submitLabel(.done)
                                    .onSubmit { add() }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                Button { add() } label: {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Palette.green)
                                }
                                .buttonStyle(.plain)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                            }
                        }

                        // Built-in (read-only)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BUILT-IN").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                            ForEach(SeshCategory.allCases) { c in
                                HStack(spacing: 10) {
                                    Image(systemName: c.symbol).font(.system(size: 14)).foregroundStyle(Palette.gold).frame(width: 22)
                                    Text(c.rawValue).font(.system(size: 15)).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text("Default").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                            }
                        }

                        // Custom (editable)
                        if !session.customCategories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOUR CATEGORIES").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                                ForEach(session.customCategories, id: \.self) { name in
                                    if renaming == name {
                                        HStack(spacing: 8) {
                                            TextField("", text: $renameText).foregroundStyle(Palette.text).submitLabel(.done)
                                                .onSubmit { commitRename(name) }
                                                .padding(.horizontal, 12).padding(.vertical, 10)
                                                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                                            Button { commitRename(name) } label: {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                                            }.buttonStyle(.plain)
                                        }
                                    } else {
                                        HStack(spacing: 10) {
                                            Image(systemName: "tag.fill").font(.system(size: 14)).foregroundStyle(Palette.green).frame(width: 22)
                                            Text(name).font(.system(size: 15)).foregroundStyle(Palette.text)
                                            Spacer()
                                            Button { renaming = name; renameText = name } label: {
                                                Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                                            }.buttonStyle(.plain)
                                            Button { session.deleteCategory(name); Haptics.warning() } label: {
                                                Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(Palette.moodAngry)
                                            }.buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                                    }
                                }
                            }
                        } else {
                            Text("Your custom categories will appear here. Add one above, then assign it when logging a sesh.")
                                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    private func add() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        session.addCategory(trimmed)
        newName = ""
        Haptics.success()
    }
    private func commitRename(_ old: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { session.renameCategory(old, to: trimmed); Haptics.success() }
        renaming = nil
    }
}
