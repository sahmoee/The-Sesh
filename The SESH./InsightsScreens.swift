//
//  InsightsScreens.swift
//  HighThoughts
//
//  Badges, Stats (Overview/Mood/Strains/Spending), Strain Insights list +
//  detail. All pushed from Journey.
//

import SwiftUI

// MARK: - Badge model

struct BadgeItem: Identifiable {
    let id: String
    let group: String
    let title: String
    let symbol: String
    let earned: Bool
    let subtitle: String   // date earned or "X / Y"
    var tint: Color = Palette.gold
}

/// Per-category visual identity — each badge group gets its own icon + color.
enum BadgeGroupStyle {
    static let order = ["Explorer", "Strains", "Journal", "Session", "Social", "Spending", "Dedication", "Misc"]

    static func icon(_ group: String) -> String {
        switch group {
        case "Explorer":   return "map.fill"
        case "Strains":    return "leaf.fill"
        case "Journal":    return "book.pages.fill"
        case "Session":    return "flame.fill"
        case "Social":     return "person.2.fill"
        case "Spending":   return "dollarsign.circle.fill"
        case "Dedication": return "star.circle.fill"
        default:            return "sparkles"
        }
    }

    static func color(_ group: String) -> Color {
        switch group {
        case "Explorer":   return Palette.greenBright
        case "Strains":    return Palette.green
        case "Journal":    return Palette.gold
        case "Session":    return Palette.moodAngry
        case "Social":     return Palette.greenBright
        case "Spending":   return Palette.gold
        case "Dedication": return Palette.goldDeep
        default:            return Palette.green
        }
    }
}

enum BadgeBuilder {
    static func build(_ s: AppSession) -> [BadgeItem] {
        let sessions = s.sessionsLogged
        let strains = s.uniqueStrains
        let thoughts = s.thoughts.count
        let entries = s.entries

        func g(_ group: String) -> Color { BadgeGroupStyle.color(group) }
        func count(_ p: (JournalEntry) -> Bool) -> Int { entries.filter(p).count }
        func has(_ p: (JournalEntry) -> Bool) -> Bool { entries.contains(where: p) }

        // distinct values helpers
        let distinctMethods = Set(entries.map { $0.method.lowercased() }.filter { !$0.isEmpty }).count
        let distinctMoods = Set(entries.compactMap { $0.mood }).count
        let distinctEffects = Set(entries.flatMap { $0.effects ?? [] }).count
        let distinctSessionTypes = Set(entries.compactMap { $0.sessionType }).count
        let withCompanions = count { ($0.companions?.isEmpty == false) }
        let withPhotos = count { $0.photoName != nil }
        let withNotes = count { !$0.notes.trimmingCharacters(in: .whitespaces).isEmpty }
        let perfectRatings = count { $0.rating >= 10 }
        let favorites = count { $0.category == .personalFaves }

        // time-of-day helpers
        func hour(_ e: JournalEntry) -> Int { Calendar.current.component(.hour, from: e.date) }
        let hasWakeBake = has { hour($0) < 9 } || has { $0.sessionType == "Wake & Bake" }
        let hasLateNight = has { hour($0) >= 22 || hour($0) < 4 }

        func earnedSub(_ done: Bool, _ have: Int, _ need: Int) -> String {
            done ? "Earned" : "\(min(have, need)) / \(need)"
        }

        return [
            // ───────── Explorer ─────────
            BadgeItem(id: "first_entry", group: "Explorer", title: "First sesh",
                      symbol: "leaf.fill", earned: sessions >= 1,
                      subtitle: sessions >= 1 ? "Earned" : "Log 1 session", tint: g("Explorer")),
            BadgeItem(id: "sessions_10", group: "Explorer", title: "Getting Started",
                      symbol: "figure.walk", earned: sessions >= 10,
                      subtitle: earnedSub(sessions >= 10, sessions, 10), tint: g("Explorer")),
            BadgeItem(id: "sessions_50", group: "Explorer", title: "Regular",
                      symbol: "figure.walk.motion", earned: sessions >= 50,
                      subtitle: earnedSub(sessions >= 50, sessions, 50), tint: g("Explorer")),
            BadgeItem(id: "sessions_100", group: "Explorer", title: "Centurion",
                      symbol: "100.square.fill", earned: sessions >= 100,
                      subtitle: earnedSub(sessions >= 100, sessions, 100), tint: g("Explorer")),
            BadgeItem(id: "sessions_250", group: "Explorer", title: "Devotee",
                      symbol: "infinity.circle.fill", earned: sessions >= 250,
                      subtitle: earnedSub(sessions >= 250, sessions, 250), tint: g("Explorer")),

            // ───────── Strains ─────────
            BadgeItem(id: "strains_5", group: "Strains", title: "Variety Pack",
                      symbol: "square.grid.2x2.fill", earned: strains >= 5,
                      subtitle: earnedSub(strains >= 5, strains, 5), tint: g("Strains")),
            BadgeItem(id: "strains_10", group: "Strains", title: "Connoisseur",
                      symbol: "leaf.circle", earned: strains >= 10,
                      subtitle: earnedSub(strains >= 10, strains, 10), tint: g("Strains")),
            BadgeItem(id: "strains_25", group: "Strains", title: "Strain Hunter",
                      symbol: "leaf.circle.fill", earned: strains >= 25,
                      subtitle: earnedSub(strains >= 25, strains, 25), tint: g("Strains")),
            BadgeItem(id: "strains_50", group: "Strains", title: "Botanist",
                      symbol: "camera.macro", earned: strains >= 50,
                      subtitle: earnedSub(strains >= 50, strains, 50), tint: g("Strains")),
            BadgeItem(id: "strains_100", group: "Strains", title: "Living Library",
                      symbol: "books.vertical.fill", earned: strains >= 100,
                      subtitle: earnedSub(strains >= 100, strains, 100), tint: g("Strains")),
            BadgeItem(id: "methods_3", group: "Strains", title: "Switch Hitter",
                      symbol: "arrow.triangle.2.circlepath", earned: distinctMethods >= 3,
                      subtitle: earnedSub(distinctMethods >= 3, distinctMethods, 3), tint: g("Strains")),

            // ───────── Journal ─────────
            BadgeItem(id: "first_thought", group: "Journal", title: "First Thought",
                      symbol: "bubble.left.fill", earned: thoughts >= 1,
                      subtitle: thoughts >= 1 ? "Earned" : "Capture 1 thought", tint: g("Journal")),
            BadgeItem(id: "thoughts_25", group: "Journal", title: "Deep Thinker",
                      symbol: "brain.head.profile", earned: thoughts >= 25,
                      subtitle: earnedSub(thoughts >= 25, thoughts, 25), tint: g("Journal")),
            BadgeItem(id: "thoughts_100", group: "Journal", title: "Philosopher",
                      symbol: "text.book.closed.fill", earned: thoughts >= 100,
                      subtitle: earnedSub(thoughts >= 100, thoughts, 100), tint: g("Journal")),
            BadgeItem(id: "notes_25", group: "Journal", title: "Note Taker",
                      symbol: "note.text", earned: withNotes >= 25,
                      subtitle: earnedSub(withNotes >= 25, withNotes, 25), tint: g("Journal")),
            BadgeItem(id: "shutterbug", group: "Journal", title: "Shutterbug",
                      symbol: "camera.fill", earned: withPhotos >= 1,
                      subtitle: withPhotos >= 1 ? "Earned" : "Add a photo", tint: g("Journal")),
            BadgeItem(id: "photo_album", group: "Journal", title: "Photo Album",
                      symbol: "photo.stack.fill", earned: withPhotos >= 10,
                      subtitle: earnedSub(withPhotos >= 10, withPhotos, 10), tint: g("Journal")),

            // ───────── Session ─────────
            BadgeItem(id: "streak_3", group: "Session", title: "3 Day Streak",
                      symbol: "flame", earned: s.currentStreak >= 3,
                      subtitle: earnedSub(s.currentStreak >= 3, s.currentStreak, 3), tint: g("Session")),
            BadgeItem(id: "streak_7", group: "Session", title: "7 Day Streak",
                      symbol: "flame.fill", earned: s.currentStreak >= 7,
                      subtitle: earnedSub(s.currentStreak >= 7, s.currentStreak, 7), tint: g("Session")),
            BadgeItem(id: "streak_30", group: "Session", title: "30 Day Streak",
                      symbol: "flame.circle.fill", earned: s.currentStreak >= 30,
                      subtitle: earnedSub(s.currentStreak >= 30, s.currentStreak, 30), tint: g("Session")),
            BadgeItem(id: "wake_bake", group: "Session", title: "Wake & Bake",
                      symbol: "sunrise.fill", earned: hasWakeBake,
                      subtitle: hasWakeBake ? "Earned" : "Sesh before 9am", tint: g("Session")),
            BadgeItem(id: "night_owl", group: "Session", title: "Night Owl",
                      symbol: "moon.stars.fill", earned: hasLateNight,
                      subtitle: hasLateNight ? "Earned" : "Sesh after 10pm", tint: g("Session")),
            BadgeItem(id: "session_types_3", group: "Session", title: "Mood Setter",
                      symbol: "theatermasks.fill", earned: distinctSessionTypes >= 3,
                      subtitle: earnedSub(distinctSessionTypes >= 3, distinctSessionTypes, 3), tint: g("Session")),
            BadgeItem(id: "moods_all", group: "Session", title: "Full Spectrum",
                      symbol: "face.smiling.inverse", earned: distinctMoods >= 4,
                      subtitle: earnedSub(distinctMoods >= 4, distinctMoods, 4), tint: g("Session")),
            BadgeItem(id: "effects_8", group: "Session", title: "Effect Collector",
                      symbol: "wand.and.stars", earned: distinctEffects >= 8,
                      subtitle: earnedSub(distinctEffects >= 8, distinctEffects, 8), tint: g("Session")),

            // ───────── Social ─────────
            BadgeItem(id: "first_companion", group: "Social", title: "Sesh Buddy",
                      symbol: "person.2.fill", earned: withCompanions >= 1,
                      subtitle: withCompanions >= 1 ? "Earned" : "Sesh with a friend", tint: g("Social")),
            BadgeItem(id: "companions_10", group: "Social", title: "Social Smoker",
                      symbol: "person.3.fill", earned: withCompanions >= 10,
                      subtitle: earnedSub(withCompanions >= 10, withCompanions, 10), tint: g("Social")),
            BadgeItem(id: "cypher_host", group: "Social", title: "Cypher Starter",
                      symbol: "dot.radiowaves.left.and.right", earned: withCompanions >= 5,
                      subtitle: earnedSub(withCompanions >= 5, withCompanions, 5), tint: g("Social")),

            // ───────── Spending ─────────
            BadgeItem(id: "spend_50", group: "Spending", title: "First Fifty",
                      symbol: "banknote.fill", earned: s.totalSpent >= 50,
                      subtitle: s.totalSpent >= 50 ? "Earned" : String(format: "$%.0f / $50", s.totalSpent), tint: g("Spending")),
            BadgeItem(id: "spend_200", group: "Spending", title: "Big Spender",
                      symbol: "dollarsign.circle.fill", earned: s.totalSpent >= 200,
                      subtitle: s.totalSpent >= 200 ? "Earned" : String(format: "$%.0f / $200", s.totalSpent), tint: g("Spending")),
            BadgeItem(id: "spend_500", group: "Spending", title: "High Roller",
                      symbol: "creditcard.fill", earned: s.totalSpent >= 500,
                      subtitle: s.totalSpent >= 500 ? "Earned" : String(format: "$%.0f / $500", s.totalSpent), tint: g("Spending")),
            BadgeItem(id: "tracker", group: "Spending", title: "Budget Keeper",
                      symbol: "chart.pie.fill", earned: count { $0.price != nil } >= 20,
                      subtitle: earnedSub(count { $0.price != nil } >= 20, count { $0.price != nil }, 20), tint: g("Spending")),

            // ───────── Dedication ─────────
            BadgeItem(id: "critic", group: "Dedication", title: "Critic",
                      symbol: "star.fill", earned: has { $0.rating >= 9 },
                      subtitle: has { $0.rating >= 9 } ? "Earned" : "Rate a sesh 9+", tint: g("Dedication")),
            BadgeItem(id: "perfectionist", group: "Dedication", title: "Perfect Ten",
                      symbol: "star.circle.fill", earned: perfectRatings >= 1,
                      subtitle: perfectRatings >= 1 ? "Earned" : "Rate a sesh 10", tint: g("Dedication")),
            BadgeItem(id: "fave_collector", group: "Dedication", title: "Favorites Club",
                      symbol: "heart.fill", earned: favorites >= 5,
                      subtitle: earnedSub(favorites >= 5, favorites, 5), tint: g("Dedication")),
            BadgeItem(id: "completionist", group: "Dedication", title: "Completionist",
                      symbol: "checklist", earned: has { $0.mood != nil && ($0.effects?.isEmpty == false) && $0.photoName != nil && !$0.notes.isEmpty },
                      subtitle: has { $0.mood != nil && ($0.effects?.isEmpty == false) && $0.photoName != nil && !$0.notes.isEmpty } ? "Earned" : "Fill out every field", tint: g("Dedication")),

            // ───────── Misc ─────────
            BadgeItem(id: "early_adopter", group: "Misc", title: "Early Adopter",
                      symbol: "sparkles", earned: sessions >= 1,
                      subtitle: sessions >= 1 ? "Earned" : "Welcome!", tint: g("Misc")),
            BadgeItem(id: "weekend_warrior", group: "Misc", title: "Weekend Warrior",
                      symbol: "calendar.badge.clock", earned: count { let wd = Calendar.current.component(.weekday, from: $0.date); return wd == 1 || wd == 7 } >= 10,
                      subtitle: earnedSub(count { let wd = Calendar.current.component(.weekday, from: $0.date); return wd == 1 || wd == 7 } >= 10, count { let wd = Calendar.current.component(.weekday, from: $0.date); return wd == 1 || wd == 7 }, 10), tint: g("Misc")),
        ]
    }
}

// MARK: - Badges screen

struct BadgesView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "All"
    private var filters: [String] { ["All"] + BadgeGroupStyle.order }
    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Badges", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                let all = BadgeBuilder.build(session)
                let earnedCount = all.filter { $0.earned }.count
                Text("\(earnedCount) of \(all.count) earned")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, 10)

                FilterPills(items: filters, selection: $filter)
                    .padding(.horizontal, 18).padding(.bottom, 8)

                ScrollView {
                    let groups = BadgeGroupStyle.order.filter { filter == "All" || filter == $0 }
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(groups, id: \.self) { group in
                            let items = all.filter { $0.group == group }
                            if !items.isEmpty {
                                let got = items.filter { $0.earned }.count
                                HStack(spacing: 8) {
                                    Image(systemName: BadgeGroupStyle.icon(group))
                                        .font(.system(size: 15)).foregroundStyle(BadgeGroupStyle.color(group))
                                        .accessibilityHidden(true)
                                    Text(group)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Palette.text)
                                    Spacer()
                                    Text("\(got)/\(items.count)")
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textTertiary)
                                }
                                LazyVGrid(columns: cols, spacing: 18) {
                                    ForEach(items) { BadgeMedallion(item: $0) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }
}

struct BadgeMedallion: View {
    let item: BadgeItem
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(item.earned ? item.tint.opacity(0.18) : Palette.field)
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(item.earned ? item.tint : Palette.stroke, lineWidth: 2)
                    .frame(width: 70, height: 70)
                Image(systemName: item.earned ? item.symbol : "lock.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(item.earned ? item.tint : Palette.textTertiary)
            }
            .accessibilityLabel(item.earned ? "\(item.title), earned" : "\(item.title), locked")
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.earned ? Palette.text : Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2)
            Text(item.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Stats screen

struct StatsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var tab: String
    @State private var strainSort = "Sessions"
    private let tabs = ["Overview", "Trends", "Mood", "Strains", "Spending"]

    init(initialTab: String = "Spending") { _tab = State(initialValue: initialTab) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Stats", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                FilterPills(items: tabs, selection: $tab)
                    .padding(.horizontal, 18).padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        switch tab {
                        case "Spending": spending
                        case "Trends":   trends
                        case "Mood":     mood
                        case "Strains":  strains
                        default:         overview
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    // Trends tab — rating over time + sessions per week
    private var trends: some View {
        let ratings = session.recentRatings(count: 12)
        let perWeek = session.sessionsPerWeek(weeks: 8)
        let trend = session.ratingTrend
        let delta = trend.thisWeek - trend.lastWeek
        return VStack(spacing: 16) {
            if session.entries.count < 2 {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                               title: "Not enough data yet",
                               message: "Log a few sessions and your trends will show up here.")
            } else {
                // Rating trend
                DarkCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Rating over time").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            Spacer()
                            if trend.thisWeek > 0 && trend.lastWeek > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(String(format: "%.1f", abs(delta)))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(delta >= 0 ? Palette.greenBright : Palette.moodAngry)
                            }
                        }
                        Sparkline(values: ratings, height: 56)
                        Text("Your last \(ratings.count) sessions").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Sessions per week
                DarkCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sessions per week").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        let maxCount = max(perWeek.map(\.count).max() ?? 1, 1)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(perWeek.enumerated()), id: \.offset) { _, wk in
                                VStack(spacing: 6) {
                                    Text("\(wk.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 4).fill(Palette.field).frame(width: 18, height: 80)
                                        RoundedRectangle(cornerRadius: 4).fill(Palette.green)
                                            .frame(width: 18, height: max(4, 80 * CGFloat(wk.count) / CGFloat(maxCount)))
                                    }
                                    Text(wk.label).font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // Spending tab
    private var spending: some View {
        VStack(spacing: 16) {
            DarkCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("This Month").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    }
                    Text(String(format: "$%.2f", session.thisMonthSpent))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("Total Spent").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    SpendBarChart(data: session.weeklySpend)
                        .frame(height: 150).padding(.top, 4)
                }
            }
            DarkCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Transactions").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    if session.recentTransactions.isEmpty {
                        Text("No purchases logged yet.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(Array(session.recentTransactions.enumerated()), id: \.element.id) { idx, e in
                            HStack(spacing: 12) {
                                StoredImage(name: e.photoName, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.strain).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                                    Text(dateMedium(e.date)).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                Text(Fmt.currency(e.price ?? 0))
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                            if e.id != session.recentTransactions.last?.id {
                                Rectangle().fill(Palette.stroke).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // Overview tab
    private var overview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statBox("\(session.sessionsLogged)", "Sessions")
                statBox(session.entries.isEmpty ? "—" : String(format: "%.1f", session.averageRating), "Avg High")
            }
            HStack(spacing: 12) {
                statBox("\(session.uniqueStrains)", "Strains")
                statBox("\(session.currentStreak)", "Day Streak")
            }
            HStack(spacing: 12) {
                statBox(String(format: "$%.0f", session.totalSpent), "Total Spent")
                statBox("\(session.thoughts.count)", "Thoughts")
            }
            HStack(spacing: 12) {
                statBox(session.daysSinceLastSesh.map { $0 == 0 ? "Today" : "\($0)d" } ?? "—", "Since Last")
                statBox("\(session.currentStreak)", "Day Streak")
            }
            ToleranceCard()
            championsCard
        }
    }

    /// Your Current Champions — the reigning strain for each Favorites reason.
    @ViewBuilder private var championsCard: some View {
        let champs = session.championStrains()
        if !champs.isEmpty {
            DarkCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill").font(.system(size: 15)).foregroundStyle(Palette.gold)
                        Text("Your Current Champions").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    ForEach(champs, id: \.champion.id) { item in
                        HStack(spacing: 12) {
                            Text(item.champion.emoji).font(.system(size: 20)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.champion.rawValue).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                Text(item.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statBox(_ v: String, _ l: String) -> some View {
        DarkCard {
            VStack(spacing: 4) {
                Text(v).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.gold)
                Text(l).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // Mood tab — bar-visualized
    private var mood: some View {
        let counts = Mood.allCases.filter { $0 != .other }.map { m in
            (m, session.entries.filter { $0.mood == m }.count)
        }
        let maxCount = max(1, counts.map(\.1).max() ?? 1)
        return DarkCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mood breakdown").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                if session.entries.allSatisfy({ $0.mood == nil }) {
                    Text("Log a mood with a sesh to see this.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(counts, id: \.0) { m, count in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: m.symbol).font(.system(size: 13)).frame(width: 20).foregroundStyle(Palette.green)
                                Text(m.rawValue).font(.system(size: 13)).foregroundStyle(Palette.text)
                                Spacer()
                                Text("\(count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                            }
                            EffectBar(value: Double(count) / Double(maxCount) * 10)
                        }
                    }
                }
            }
        }
    }

    // Strains tab — sortable
    private var strains: some View {
        let list: [StrainInsight] = {
            switch strainSort {
            case "Rating": return session.insights.sorted { $0.averageRating > $1.averageRating }
            default:       return session.insights.sorted { $0.sessions > $1.sessions }
            }
        }()
        return DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Strains").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Picker("", selection: $strainSort) {
                        Text("Sessions").tag("Sessions")
                        Text("Rating").tag("Rating")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                if session.insights.isEmpty {
                    Text("Log sessions to see strain stats.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(list) { ins in
                        HStack {
                            Text(ins.name).font(.system(size: 14)).foregroundStyle(Palette.text)
                            Spacer()
                            Text("\(ins.sessions)×").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            RatingBadge(value: ins.averageRating)
                        }
                    }
                }
            }
        }
    }
}

struct SpendBarChart: View {
    let data: [(label: String, amount: Double)]
    private var maxVal: Double { max(60, (data.map(\.amount).max() ?? 0)) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                // y-axis labels
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach([60, 40, 20, 0], id: \.self) { v in
                        Text("$\(v)").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        if v != 0 { Spacer() }
                    }
                }
                .frame(width: 28)

                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Palette.greenBright.opacity(0.85))
                            .frame(height: max(2, CGFloat(d.amount / maxVal) * 120))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 10) {
                Spacer().frame(width: 28)
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    Text(d.label).font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Strain Insights list

struct InsightsListView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Strain Insights", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 14) {
                        if session.insights.isEmpty {
                            EmptyStateView(icon: "sparkles",
                                           title: "No insights yet",
                                           message: "Log a few sessions and your strain insights will appear here.")
                        }
                        ForEach(Array(session.insights.enumerated()), id: \.element.id) { idx, ins in
                            let photo = session.entries(forStrain: ins.name).compactMap(\.photoName).first
                            NavigationLink {
                                StrainDetailView(insight: ins, seed: idx).environment(session).navigationBarBackButtonHidden(true)
                            } label: {
                                DarkCard {
                                    HStack(spacing: 12) {
                                        StoredImage(name: photo, size: 56)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(ins.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                            Text("\(ins.sessions) sessions").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                        }
                                        Spacer()
                                        RatingBadge(value: ins.averageRating)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }
}

// MARK: - Strain detail

struct StrainDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss
    let insight: StrainInsight
    var seed: Int = 0

    private var profile: StrainProfile? { strains.strain(named: insight.name) }

    // Prefer catalog-ranked effects; otherwise derive from your own mood logs.
    private var effects: [(String, Double)] {
        if let p = profile, !p.effects.isEmpty {
            return p.effects.prefix(5).map { ($0.name, ($0.intensity ?? 0.6) * 10) }
        }
        let items = session.entries.filter { $0.strain.caseInsensitiveCompare(insight.name) == .orderedSame }
        func score(_ moods: [Mood]) -> Double {
            let n = items.filter { moods.contains($0.mood ?? .other) }.count
            return items.isEmpty ? 0 : min(10, 3 + Double(n) / Double(items.count) * 7)
        }
        return [
            ("Relaxed", score([.chill, .couchPotato])),
            ("Happy", score([.chill, .energetic])),
            ("Creative", score([.productive, .energetic])),
            ("Focused", score([.productive])),
            ("Energetic", score([.energetic, .errandReady]))
        ]
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Strain Insights", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        historyCard
                        effectsBlock
                        flavorsBlock
                        terpenesBlock
                        bestUsedBlock
                        notesBlock
                        sourcesBlock
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    @ViewBuilder private var headerCard: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BudThumb(size: 64, seed: seed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Total Sessions").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                Text("\(insight.sessions)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Average Rating").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                Text(String(format: "%.1f/10", insight.averageRating))
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "heart").font(.system(size: 18)).foregroundStyle(Palette.textSecondary)
                }

                if let p = profile {
                    Rectangle().fill(Palette.stroke).frame(height: 1)
                    HStack(spacing: 10) {
                        infoPill(p.type.rawValue, color: p.type.tint)
                        if let thc = p.thc { infoPill("THC \(Int(thc))%", color: Palette.gold) }
                        if let cbd = p.cbd, cbd >= 1 { infoPill("CBD \(Int(cbd))%", color: Palette.greenBright) }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder private var historyCard: some View {
        let myRatings = session.recentRatings(forStrain: insight.name)
        if !myRatings.isEmpty {
            DarkCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your history").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    HStack(spacing: 16) {
                        if let last = session.lastUsed(forStrain: insight.name) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Last used").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                Text(Fmt.shortDate(last)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                        }
                        if let mood = session.bestMood(forStrain: insight.name) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Usual mood").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                HStack(spacing: 4) {
                                    Image(systemName: mood.symbol).font(.system(size: 11)).foregroundStyle(Palette.green)
                                    Text(mood.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                                }
                            }
                        }
                        Spacer()
                    }
                    if myRatings.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recent ratings").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            Sparkline(values: myRatings)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var effectsBlock: some View {
        Text("What it does for you").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
        VStack(spacing: 12) {
            ForEach(effects, id: \.0) { name, val in
                HStack(spacing: 12) {
                    Text(name).font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 80, alignment: .leading)
                    EffectBar(value: val)
                    Text(String(format: "%.1f", val)).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary).frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder private var flavorsBlock: some View {
        if let p = profile, !p.flavors.isEmpty {
            Text("Flavors").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(p.flavors) { CategoryTag(text: $0.name) }
            }
        }
    }

    @ViewBuilder private var terpenesBlock: some View {
        if let p = profile, !p.terpenes.isEmpty {
            Text("Terpenes").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(p.terpenes) { CategoryTag(text: $0.name) }
            }
        }
    }

    @ViewBuilder private var bestUsedBlock: some View {
        Text("Best used for").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
        HStack(spacing: 12) {
            bestPill("leaf.fill", "Chill")
            bestPill("paintbrush.pointed", "Creative")
            bestPill("moon.stars", "Evening")
        }
    }

    @ViewBuilder private var notesBlock: some View {
        Text("Notes").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
        DarkCard {
            Text(noteText)
                .font(.system(size: 14)).foregroundStyle(Palette.text.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var sourcesBlock: some View {
        if let p = profile, !p.sources.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.system(size: 11))
                Text("Strain data via \(p.sources.joined(separator: ", "))")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Palette.textTertiary)
            .padding(.top, 2)
        }
    }

    private var noteText: String {
        let items = session.entries.filter { $0.strain.caseInsensitiveCompare(insight.name) == .orderedSame }
        if let mine = items.first(where: { !$0.notes.isEmpty })?.notes { return mine }
        if let summary = profile?.summary { return summary }
        return "Great for unwinding after a long day. Makes me hungry every time."
    }

    private func infoPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func bestPill(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Palette.gold)
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

struct EffectBar: View {
    let value: Double  // 0...10
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.field).frame(height: 8)
            Capsule().fill(Palette.greenBright).frame(height: 8)
                .scaleEffect(x: max(0.02, min(1, value / 10)), y: 1, anchor: .leading)
        }
    }
}

func dateMedium(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
}

// MARK: - Tolerance & T-Break card (#2)

struct ToleranceCard: View {
    @Environment(AppSession.self) private var session
    @State private var showGoalPicker = false

    var body: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                if session.isOnTBreak {
                    onBreakContent
                } else {
                    notOnBreakContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("How long?", isPresented: $showGoalPicker, titleVisibility: .visible) {
            ForEach([3, 7, 14, 21, 30], id: \.self) { days in
                Button("\(days) days") { session.startTBreak(goalDays: days); Haptics.success() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var onBreakContent: some View {
        HStack {
            Label("Tolerance Break", systemImage: "pause.circle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.greenBright)
            Spacer()
            Text("Day \(session.tBreakDays) of \(session.tBreakGoalDays)")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
        }
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.field).frame(height: 10)
            Capsule().fill(Palette.green).frame(height: 10)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: max(0.02, session.tBreakProgress), anchor: .leading)
        }
        .accessibilityLabel("Break progress, day \(session.tBreakDays) of \(session.tBreakGoalDays)")
        if session.tBreakDays >= session.tBreakGoalDays {
            Text("Goal reached — nice work! 🎉").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.greenBright)
        } else {
            Text("Stay strong. Your tolerance is resetting.").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
        }
        Button { session.endTBreak(); Haptics.tap() } label: {
            Text("End break").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var notOnBreakContent: some View {
        HStack {
            Label("Tolerance", systemImage: "gauge.medium")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer()
            Text(session.toleranceLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(toleranceColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(toleranceColor.opacity(0.15)))
        }
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.field).frame(height: 10)
            Capsule().fill(toleranceColor).frame(height: 10)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: max(0.02, session.toleranceEstimate), anchor: .leading)
        }
        .accessibilityLabel("Tolerance \(session.toleranceLabel)")
        Text("Based on your last 14 days. A break helps it reset.")
            .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
        Button { showGoalPicker = true } label: {
            Label("Start a tolerance break", systemImage: "pause.circle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onGreen)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
        }.buttonStyle(.plain)
    }

    private var toleranceColor: Color {
        switch session.toleranceEstimate {
        case ..<0.2:  return Palette.greenBright
        case ..<0.45: return Palette.green
        case ..<0.7:  return Palette.gold
        default:       return Palette.moodAngry
        }
    }
}
