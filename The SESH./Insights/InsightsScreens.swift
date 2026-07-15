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
                let earnedCount = all.count(where: { $0.earned })
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
                                let got = items.count(where: { $0.earned })
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

