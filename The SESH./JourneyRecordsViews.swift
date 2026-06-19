//
//  JourneyRecordsViews.swift
//  The SESH
//
//  Two distinct systems (plus more, built in stages):
//   • JOURNEY  — permanent, one-time milestones (Xbox-achievement style).
//   • PERSONAL RECORDS — beatable personal bests (Apple-Fitness style).
//   • YEARLY RECAP, SECRET BADGES, PERSONALITY PROFILE — added in later stages.
//
//  Journey lives here first. All conditions are driven by real logged data.
//

import SwiftUI

// MARK: - Journey model

struct Milestone: Identifiable {
    let id: String
    let group: String
    let title: String
    let symbol: String
    let earned: Bool
    /// Progress detail, e.g. "Earned", "3 / 5", or a target hint.
    let detail: String
    var tint: Color = Palette.gold
}

enum JourneyGroupStyle {
    static let order = ["Firsts", "Explorer", "Journaler", "Thought Collector", "Cyph Milestones", "Consistency"]
    static func icon(_ g: String) -> String {
        switch g {
        case "Firsts":            return "sparkles"
        case "Explorer":          return "map.fill"
        case "Journaler":         return "book.pages.fill"
        case "Thought Collector": return "bubble.left.and.bubble.right.fill"
        case "Cyph Milestones":   return "person.3.fill"
        case "Consistency":       return "flame.fill"
        default:                   return "star.fill"
        }
    }
    static func color(_ g: String) -> Color {
        switch g {
        case "Firsts":            return Palette.gold
        case "Explorer":          return Palette.greenBright
        case "Journaler":         return Palette.green
        case "Thought Collector": return Palette.goldDeep
        case "Cyph Milestones":   return Palette.greenBright
        case "Consistency":       return Palette.moodAngry
        default:                   return Palette.gold
        }
    }
}

enum JourneyBuilder {
    static func build(_ s: AppSession, social: SocialStore?) -> [Milestone] {
        let sessions = s.sessionsLogged
        let strains = s.uniqueStrains
        let thoughts = s.thoughts.count
        let streak = s.bestStreakEver
        let withPhoto = s.entries.contains { $0.photoName != nil }
        let friendCount = social?.friends.count ?? 0
        let cyphsJoined = s.cyphsJoinedCount
        let cyphsHosted = s.cyphsHostedCount

        func g(_ group: String) -> Color { JourneyGroupStyle.color(group) }
        func tier(_ group: String, _ id: String, _ title: String, _ symbol: String,
                  have: Int, need: Int) -> Milestone {
            Milestone(id: id, group: group, title: title, symbol: symbol,
                      earned: have >= need,
                      detail: have >= need ? "Earned" : "\(min(have, need)) / \(need)", tint: g(group))
        }
        func first(_ id: String, _ title: String, _ symbol: String, done: Bool, hint: String) -> Milestone {
            Milestone(id: id, group: "Firsts", title: title, symbol: symbol,
                      earned: done, detail: done ? "Earned" : hint, tint: g("Firsts"))
        }

        return [
            // Firsts
            first("first_sesh", "First sesh", "leaf.fill", done: sessions >= 1, hint: "Log a sesh"),
            first("first_thought", "First Thought", "bubble.left.fill", done: thoughts >= 1, hint: "Capture a thought"),
            first("first_friend", "First Friend Added", "person.badge.plus", done: friendCount >= 1, hint: "Add a friend"),
            first("first_cyph", "First Cyph", "dot.radiowaves.left.and.right", done: cyphsJoined >= 1, hint: "Join a Cyph"),
            first("first_strain", "First Strain Logged", "leaf.circle.fill", done: strains >= 1, hint: "Log a strain"),
            first("first_photo", "First Photo Added", "camera.fill", done: withPhoto, hint: "Add a photo"),

            // Explorer
            tier("Explorer", "explorer_5", "5 Unique Strains", "square.grid.2x2.fill", have: strains, need: 5),
            tier("Explorer", "explorer_25", "25 Unique Strains", "leaf.circle", have: strains, need: 25),
            tier("Explorer", "explorer_50", "50 Unique Strains", "leaf.circle.fill", have: strains, need: 50),
            tier("Explorer", "explorer_100", "100 Unique Strains", "books.vertical.fill", have: strains, need: 100),

            // Journaler
            tier("Journaler", "journaler_10", "10 Entries", "square.and.pencil", have: sessions, need: 10),
            tier("Journaler", "journaler_50", "50 Entries", "doc.text.fill", have: sessions, need: 50),
            tier("Journaler", "journaler_100", "100 Entries", "100.square.fill", have: sessions, need: 100),
            tier("Journaler", "journaler_500", "500 Entries", "infinity.circle.fill", have: sessions, need: 500),

            // Thought Collector
            tier("Thought Collector", "thoughts_10", "10 Thoughts", "bubble.left.fill", have: thoughts, need: 10),
            tier("Thought Collector", "thoughts_50", "50 Thoughts", "brain.head.profile", have: thoughts, need: 50),
            tier("Thought Collector", "thoughts_100", "100 Thoughts", "text.book.closed.fill", have: thoughts, need: 100),

            // Cyph Milestones
            Milestone(id: "cyph_joined", group: "Cyph Milestones", title: "Joined First Cyph", symbol: "person.2.fill",
                      earned: cyphsJoined >= 1, detail: cyphsJoined >= 1 ? "Earned" : "Join a Cyph", tint: g("Cyph Milestones")),
            Milestone(id: "cyph_hosted", group: "Cyph Milestones", title: "Hosted First Cyph", symbol: "dot.radiowaves.left.and.right",
                      earned: cyphsHosted >= 1, detail: cyphsHosted >= 1 ? "Earned" : "Host a Cyph", tint: g("Cyph Milestones")),
            tier("Cyph Milestones", "cyph_host_10", "10 Cyphs Hosted", "person.3.sequence.fill", have: cyphsHosted, need: 10),
            tier("Cyph Milestones", "friends_100", "100 Friends Met", "person.3.fill", have: friendCount, need: 100),

            // Consistency
            tier("Consistency", "streak_7", "7 Day Tracking Streak", "flame", have: streak, need: 7),
            tier("Consistency", "streak_30", "30 Day Tracking Streak", "flame.fill", have: streak, need: 30),
            tier("Consistency", "streak_100", "100 Day Tracking Streak", "flame.circle.fill", have: streak, need: 100),
        ]
    }
}

// MARK: - Journey screen

struct JourneyMilestonesView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Journey", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                let all = JourneyBuilder.build(session, social: social)
                let earned = all.filter { $0.earned }.count
                Text("\(earned) of \(all.count) milestones")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(JourneyGroupStyle.order, id: \.self) { group in
                            let items = all.filter { $0.group == group }
                            if !items.isEmpty {
                                let got = items.filter { $0.earned }.count
                                HStack(spacing: 8) {
                                    Image(systemName: JourneyGroupStyle.icon(group))
                                        .font(.system(size: 15)).foregroundStyle(JourneyGroupStyle.color(group))
                                        .accessibilityHidden(true)
                                    Text(group).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text("\(got)/\(items.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textTertiary)
                                }
                                LazyVGrid(columns: cols, spacing: 18) {
                                    ForEach(items) { MilestoneMedallion(item: $0) }
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

struct MilestoneMedallion: View {
    let item: Milestone
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(item.earned ? item.tint.opacity(0.18) : Palette.field).frame(width: 70, height: 70)
                Circle().stroke(item.earned ? item.tint : Palette.stroke, lineWidth: 2).frame(width: 70, height: 70)
                Image(systemName: item.earned ? item.symbol : "lock.fill")
                    .font(.system(size: 25)).foregroundStyle(item.earned ? item.tint : Palette.textTertiary)
            }
            .accessibilityLabel(item.earned ? "\(item.title), earned" : "\(item.title), locked")
            Text(item.title).font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(item.earned ? Palette.text : Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2)
            Text(item.detail).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Personal Records (#PersonalRecords)
//
// Beatable personal bests, Apple-Fitness style. Records that derive from logged
// data show a live value; records that need capture the app doesn't have yet
// (rolling times, per-Cyph message counts, thought likes) show "Not set yet"
// with a short note on what unlocks them — honest, not faked.

struct RecordRow: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String?       // nil → "Not set yet"
    var sub: String? = nil   // secondary line (strain name, "from → now", hint)
    var tint: Color = Palette.gold
}

struct PersonalRecordsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private func fmtDuration(_ minutes: Int) -> String {
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Personal Records", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)
                Text("Beat your own bests.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("Rolling Records", "hand.raised.fingers.spread", rollingRecords)
                        section("Session Records", "timer", sessionRecords)
                        section("Thought Records", "bubble.left.and.bubble.right.fill", thoughtRecords)
                        section("Journal Records", "book.pages.fill", journalRecords)
                        section("Strain Records", "leaf.fill", strainRecords)
                        section("Spending Records", "dollarsign.circle.fill", spendingRecords)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    // MARK: Record groups

    private var rollingRecords: [RecordRow] {
        func fmt(_ s: Int) -> String { s >= 60 ? String(format: "%dm %02ds", s / 60, s % 60) : "\(s)s" }
        var rows: [RecordRow] = []
        if let b = session.fastestBluntRoll {
            rows.append(RecordRow(icon: "bolt.fill", title: "Fastest Blunt Rolled", value: fmt(b), tint: Palette.gold))
        } else {
            rows.append(RecordRow(icon: "bolt.fill", title: "Fastest Blunt Rolled", value: nil,
                                  sub: "Time a blunt roll from the live sesh screen"))
        }
        if let j = session.fastestJointRoll {
            rows.append(RecordRow(icon: "bolt.fill", title: "Fastest Joint Rolled", value: fmt(j), tint: Palette.gold))
        } else {
            rows.append(RecordRow(icon: "bolt.fill", title: "Fastest Joint Rolled", value: nil,
                                  sub: "Time a joint roll from the live sesh screen"))
        }
        return rows
    }

    private var sessionRecords: [RecordRow] {
        var rows: [RecordRow] = []
        if let l = session.longestSesh {
            rows.append(RecordRow(icon: "arrow.up.right", title: "Longest sesh", value: fmtDuration(l.minutes), sub: l.strain, tint: Palette.greenBright))
        } else {
            rows.append(RecordRow(icon: "arrow.up.right", title: "Longest sesh", value: nil, sub: "Use the live Start sesh timer to set this"))
        }
        if let s = session.shortestSesh {
            rows.append(RecordRow(icon: "arrow.down.right", title: "Shortest sesh", value: fmtDuration(s.minutes), sub: s.strain, tint: Palette.green))
        } else {
            rows.append(RecordRow(icon: "arrow.down.right", title: "Shortest sesh", value: nil, sub: "Use the live Start sesh timer to set this"))
        }
        // Needs Worker support (per-Cyph membership/message counts) — placeholders.
        rows.append(RecordRow(icon: "person.3.fill", title: "Most Friends In One Cyph", value: nil, sub: "Coming with live Cyphs"))
        rows.append(RecordRow(icon: "message.fill", title: "Most Active Cyph", value: nil, sub: "Coming with live Cyphs"))
        return rows
    }

    private var thoughtRecords: [RecordRow] {
        var rows: [RecordRow] = []
        // Thoughts attach 1:1 to a sesh today, so "most in one sesh" needs capture.
        rows.append(RecordRow(icon: "square.stack.3d.up.fill", title: "Most thoughts in one sesh", value: nil, sub: "Coming soon"))
        let words = session.longestThought
        rows.append(RecordRow(icon: "text.alignleft", title: "Longest Thought",
                              value: words > 0 ? "\(words) words" : nil, sub: words > 0 ? nil : "Write a thought to set this", tint: Palette.greenBright))
        rows.append(RecordRow(icon: "heart.fill", title: "Most Liked Thought", value: nil, sub: "Coming with thought likes"))
        return rows
    }

    private var journalRecords: [RecordRow] {
        var rows: [RecordRow] = []
        let day = session.mostEntriesInADay
        rows.append(RecordRow(icon: "calendar", title: "Most Journal Entries In One Day",
                              value: day > 0 ? "\(day)" : nil, sub: day > 0 ? nil : "Log a sesh to set this", tint: Palette.green))
        // Photos attach 1:1 to an entry today → needs capture for per-sesh count.
        rows.append(RecordRow(icon: "photo.stack.fill", title: "Most photos in one sesh", value: nil, sub: "Coming soon"))
        return rows
    }

    private var strainRecords: [RecordRow] {
        var rows: [RecordRow] = []
        if let h = session.highestRatedStrain {
            rows.append(RecordRow(icon: "star.fill", title: "Highest Rated Strain",
                                  value: String(format: "%.1f", session.highestRating), sub: h, tint: Palette.gold))
        } else {
            rows.append(RecordRow(icon: "star.fill", title: "Highest Rated Strain", value: nil, sub: "Rate a sesh to set this"))
        }
        if let m = session.mostLoggedStrain {
            rows.append(RecordRow(icon: "chart.bar.fill", title: "Most Logged Strain",
                                  value: "\(m.count) sessions", sub: m.name, tint: Palette.greenBright))
        } else {
            rows.append(RecordRow(icon: "chart.bar.fill", title: "Most Logged Strain", value: nil, sub: "Log a strain to set this"))
        }
        if let imp = session.mostImprovedStrain {
            rows.append(RecordRow(icon: "arrow.up.forward", title: "Most Improved Opinion",
                                  value: imp.name, sub: String(format: "Started %.1f → Now %.1f", imp.from, imp.to), tint: Palette.green))
        } else {
            rows.append(RecordRow(icon: "arrow.up.forward", title: "Most Improved Opinion", value: nil, sub: "Log a strain 3+ times to set this"))
        }
        return rows
    }

    private var spendingRecords: [RecordRow] {
        var rows: [RecordRow] = []
        if let h = session.highestPurchase {
            rows.append(RecordRow(icon: "arrow.up", title: "Highest Purchase", value: String(format: "$%.0f", h), tint: Palette.gold))
        } else {
            rows.append(RecordRow(icon: "arrow.up", title: "Highest Purchase", value: nil, sub: "Add a price to a sesh to set this"))
        }
        if let c = session.cheapestPurchase {
            rows.append(RecordRow(icon: "arrow.down", title: "Cheapest Purchase", value: String(format: "$%.0f", c), tint: Palette.green))
        } else {
            rows.append(RecordRow(icon: "arrow.down", title: "Cheapest Purchase", value: nil, sub: "Add a price to a sesh to set this"))
        }
        if let m = session.monthlySpendExtremes {
            rows.append(RecordRow(icon: "calendar.badge.plus", title: "Biggest Monthly Spend", value: String(format: "$%.0f", m.high), tint: Palette.gold))
            rows.append(RecordRow(icon: "calendar.badge.minus", title: "Lowest Monthly Spend", value: String(format: "$%.0f", m.low), tint: Palette.green))
        } else {
            rows.append(RecordRow(icon: "calendar.badge.plus", title: "Biggest Monthly Spend", value: nil, sub: "Add prices to set this"))
            rows.append(RecordRow(icon: "calendar.badge.minus", title: "Lowest Monthly Spend", value: nil, sub: "Add prices to set this"))
        }
        return rows
    }

    // MARK: UI

    private func section(_ title: String, _ icon: String, _ rows: [RecordRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Palette.gold).accessibilityHidden(true)
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            }
            VStack(spacing: 10) {
                ForEach(rows) { recordCard($0) }
            }
        }
    }

    private func recordCard(_ r: RecordRow) -> some View {
        let isSet = r.value != nil
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill((isSet ? r.tint : Palette.textTertiary).opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: r.icon).font(.system(size: 18)).foregroundStyle(isSet ? r.tint : Palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                if let sub = r.sub {
                    Text(sub).font(.system(size: 12)).foregroundStyle(isSet ? Palette.greenBright : Palette.textTertiary)
                }
            }
            Spacer()
            Text(r.value ?? "Not set yet")
                .font(.system(size: isSet ? 18 : 13, weight: isSet ? .bold : .regular, design: isSet ? .rounded : .default))
                .foregroundStyle(isSet ? Palette.text : Palette.textTertiary)
                .monospacedDigit()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.title): \(r.value ?? "not set yet")\(r.sub.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Yearly Recap (#YearlyRecap)
//
// "Your sesh Year" — a shareable summary card, meant to become a December
// tradition. Renders the card to an image via ImageRenderer and shares it.

struct YearlyRecapView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var shareItem: [Any]? = nil

    private var availableYears: [Int] {
        let ys = session.yearsWithData
        return ys.isEmpty ? [year] : ys
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Yearly Recap", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)

                // Year switcher
                if availableYears.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableYears, id: \.self) { y in
                                Button { withAnimation { year = y }; Haptics.selection() } label: {
                                    Text(String(y)).font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(y == year ? Palette.onGreen : Palette.text)
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(Capsule().fill(y == year ? Palette.green : Palette.field))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 18)
                    }
                    .padding(.bottom, 12)
                }

                ScrollView {
                    let recap = session.yearRecap(year)
                    VStack(spacing: 16) {
                        RecapCard(recap: recap, name: session.userName)
                            .padding(.horizontal, 18)

                        Button {
                            let card = RecapCard(recap: recap, name: session.userName)
                                .frame(width: 360)
                                .environment(\.colorScheme, .dark)
                            let renderer = ImageRenderer(content: card)
                            renderer.scale = 3
                            if let img = renderer.uiImage {
                                shareItem = [img]
                            }
                            Haptics.tap()
                        } label: {
                            Label("Share your \(String(year))", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.onGreen)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)

                        if recap.sessions == 0 {
                            Text("No seshes logged in \(String(year)) yet.")
                                .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareItem != nil }, set: { if !$0 { shareItem = nil } })) {
            if let items = shareItem { ShareSheet(items: items) }
        }
    }
}

/// The shareable card itself — kept self-contained so ImageRenderer can snapshot it.
struct RecapCard: View {
    let recap: YearRecap
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("The").font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(Palette.gold)
                    Text("Sesh").font(.system(size: 24, weight: .heavy)).foregroundStyle(Palette.text)
                    Spacer()
                    Text(String(recap.year)).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Palette.greenBright)
                }
                Text("\(name)'s Year in Review").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }

            // Big stat
            VStack(alignment: .leading, spacing: 2) {
                Text("\(recap.sessions)").font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(Palette.text)
                Text("sessions logged").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }

            Divider().overlay(Palette.stroke)

            // Grid of highlights
            VStack(spacing: 12) {
                recapRow("leaf.fill", "Favorite Strain", recap.favoriteStrain ?? "—", Palette.green)
                recapRow("sparkles", "Favorite Effect", recap.favoriteEffect ?? "—", Palette.gold)
                recapRow("calendar", "Most Active Month", recap.mostActiveMonth ?? "—", Palette.greenBright)
                recapRow("square.grid.2x2.fill", "Unique Strains", "\(recap.uniqueStrains)", Palette.green)
                recapRow("dollarsign.circle.fill", "Money Spent", String(format: "$%.0f", recap.moneySpent), Palette.gold)
                recapRow("person.2.fill", "Top Cyph Friend", recap.topCyphFriend ?? "Coming soon", Palette.textTertiary)
            }

            if let thought = recap.thoughtOfYear, !thought.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THOUGHT OF THE YEAR").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                    Text("\u{201C}\(thought.prefix(140))\(thought.count > 140 ? "\u{2026}" : "")\u{201D}")
                        .font(.system(size: 14, weight: .medium, design: .serif)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Tracked with The Sesh").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(colors: [Palette.card, Palette.field], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private func recapRow(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
            Text(label).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                .lineLimit(1).truncationMode(.tail)
        }
    }
}

// MARK: - Secret Badges (#SecretBadges)
//
// Hidden achievements discovered by accident. Locked ones show as "???" with no
// hint — the surprise is the point. All conditions derive from real data.

struct SecretBadge: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let requirement: String   // revealed only once earned
    let earned: Bool
    var tint: Color = Palette.gold
}

enum SecretBadgeBuilder {
    static func build(_ s: AppSession) -> [SecretBadge] {
        let cal = Calendar.current
        func hour(_ e: JournalEntry) -> Int { cal.component(.hour, from: e.date) }

        let thoughts = s.thoughts.count
        // "Questions": thoughts tagged Questions or ending in "?"
        let questions = s.thoughts.filter { $0.tag == .questions || $0.text.trimmingCharacters(in: .whitespaces).hasSuffix("?") }.count
        let afterMidnight = s.entries.filter { hour($0) >= 0 && hour($0) < 4 }.count
        let wakeBake = s.entries.filter { hour($0) < 9 || $0.sessionType == "Wake & Bake" }.count
        let solo = s.entries.filter { ($0.companions?.isEmpty ?? true) }.count
        let cyphSessions = s.cyphsJoinedCount
        let uniqueStrains = s.uniqueStrains

        // Loyalist: a strain that has been the all-time most-logged AND used across
        // a span of at least ~1 year (first→last log ≥ 360 days).
        var loyalist = false
        if let top = Dictionary(grouping: s.entries, by: { $0.strain.lowercased() }).max(by: { $0.value.count < $1.value.count })?.value,
           top.count >= 5 {
            let dates = top.map(\.date)
            if let first = dates.min(), let last = dates.max(),
               (cal.dateComponents([.day], from: first, to: last).day ?? 0) >= 360 {
                loyalist = true
            }
        }

        return [
            SecretBadge(id: "deep_thinker", title: "Deep Thinker", symbol: "brain.head.profile",
                        requirement: "Log 100 thoughts", earned: thoughts >= 100, tint: Palette.greenBright),
            SecretBadge(id: "philosopher", title: "Philosopher", symbol: "questionmark.bubble.fill",
                        requirement: "Ask 50 questions", earned: questions >= 50, tint: Palette.gold),
            SecretBadge(id: "night_owl", title: "Night Owl", symbol: "moon.stars.fill",
                        requirement: "50 sessions after midnight", earned: afterMidnight >= 50, tint: Palette.greenBright),
            SecretBadge(id: "early_bird", title: "Early Bird", symbol: "sunrise.fill",
                        requirement: "50 wake & bake sessions", earned: wakeBake >= 50, tint: Palette.gold),
            SecretBadge(id: "solo_traveler", title: "Solo Traveler", symbol: "figure.walk",
                        requirement: "100 solo sessions", earned: solo >= 100, tint: Palette.green),
            SecretBadge(id: "social_butterfly", title: "Social Butterfly", symbol: "person.3.fill",
                        requirement: "50 Cyph sessions", earned: cyphSessions >= 50, tint: Palette.greenBright),
            SecretBadge(id: "loyalist", title: "Loyalist", symbol: "heart.circle.fill",
                        requirement: "Same favorite strain for 1 year", earned: loyalist, tint: Palette.moodAngry),
            SecretBadge(id: "adventurer", title: "Adventurer", symbol: "map.fill",
                        requirement: "50 different strains tried", earned: uniqueStrains >= 50, tint: Palette.gold),
        ]
    }
}

struct SecretBadgesView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Secret Badges", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)

                let all = SecretBadgeBuilder.build(session)
                let found = all.filter { $0.earned }.count
                Text("\(found) of \(all.count) discovered")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(all) { secretCard($0) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    private func secretCard(_ b: SecretBadge) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(b.earned ? b.tint.opacity(0.18) : Palette.field).frame(width: 64, height: 64)
                Circle().stroke(b.earned ? b.tint : Palette.stroke, lineWidth: 2).frame(width: 64, height: 64)
                Image(systemName: b.earned ? b.symbol : "questionmark")
                    .font(.system(size: 24, weight: b.earned ? .regular : .bold))
                    .foregroundStyle(b.earned ? b.tint : Palette.textTertiary)
            }
            Text(b.earned ? b.title : "???")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(b.earned ? Palette.text : Palette.textTertiary)
            Text(b.earned ? b.requirement : "Keep seshing to discover")
                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(b.earned ? b.tint.opacity(0.3) : Palette.stroke, lineWidth: 1))
        .accessibilityLabel(b.earned ? "\(b.title), discovered: \(b.requirement)" : "Undiscovered secret badge")
    }
}

// MARK: - Personality Profile (#PersonalityProfile)
//
// Generates the user's "smoking style" from their real logging patterns. Each
// trait is scored from the data; the strongest few become the user's profile.
// This is meant to feel like part of the user's identity.

struct PersonalityTrait: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let blurb: String
    let score: Double    // 0...1 strength, for ordering + showing the top traits
}

enum PersonalityEngine {
    /// Returns traits sorted strongest-first. Needs a little data to be meaningful.
    static func traits(_ s: AppSession) -> [PersonalityTrait] {
        let entries = s.entries
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        let n = Double(entries.count)
        func hour(_ e: JournalEntry) -> Int { cal.component(.hour, from: e.date) }
        func frac(_ count: Int) -> Double { Double(count) / n }

        func has(_ e: JournalEntry, effect: String) -> Bool {
            (e.effects ?? []).contains { $0.caseInsensitiveCompare(effect) == .orderedSame }
        }
        func sessionFrac(_ type: String) -> Double {
            frac(entries.filter { $0.sessionType == type }.count)
        }

        var out: [PersonalityTrait] = []

        // Time of day
        let lateNight = frac(entries.filter { hour($0) >= 21 || hour($0) < 3 }.count)
        let morning = frac(entries.filter { hour($0) < 10 }.count)
        if lateNight >= 0.4 { out.append(.init(id: "night_owl", title: "Night Owl", emoji: "🦉",
            blurb: "Most of your seshes happen after dark.", score: lateNight)) }
        if morning >= 0.3 { out.append(.init(id: "wake_bake", title: "Wake & Bake", emoji: "🍳",
            blurb: "You like to start the day with a sesh.", score: morning)) }

        // Social vs solo
        let solo = frac(entries.filter { ($0.companions?.isEmpty ?? true) }.count)
        if solo >= 0.7 { out.append(.init(id: "solo", title: "Mostly Solo", emoji: "🧘",
            blurb: "You prefer your own company when you sesh.", score: solo)) }
        else if solo <= 0.4 { out.append(.init(id: "social", title: "Highly Social", emoji: "🎉",
            blurb: "You love seshing with friends.", score: 1 - solo)) }

        // Effects sought
        let creative = frac(entries.filter { has($0, effect: "Creative") }.count)
        let relaxed = frac(entries.filter { has($0, effect: "Relaxed") || has($0, effect: "Sleepy") }.count)
        let focused = frac(entries.filter { has($0, effect: "Focused") }.count)
        if creative >= 0.3 { out.append(.init(id: "creative", title: "Creative Smoker", emoji: "🎨",
            blurb: "You sesh to spark ideas.", score: creative)) }
        if relaxed >= 0.4 { out.append(.init(id: "relaxation", title: "Relaxation Seeker", emoji: "🌿",
            blurb: "Winding down is your main goal.", score: relaxed)) }
        if focused >= 0.3 { out.append(.init(id: "focused", title: "Focused Flow", emoji: "🎯",
            blurb: "You use it to lock in.", score: focused)) }

        // Session types
        let gaming = sessionFrac("Gaming")
        let movie = sessionFrac("Movie Night")
        if gaming >= 0.25 { out.append(.init(id: "gaming", title: "Gaming Sessions", emoji: "🎮",
            blurb: "Controller in hand, every time.", score: gaming)) }
        if movie >= 0.25 { out.append(.init(id: "movie", title: "Movie Session Fan", emoji: "🎬",
            blurb: "Nothing beats a film and a sesh.", score: movie)) }

        // Thought habit
        if s.thoughts.count >= 10 && Double(s.thoughts.count) / n >= 0.5 {
            out.append(.init(id: "deep_thinker", title: "Deep Thinker", emoji: "💭",
                blurb: "Your best ideas show up mid-sesh.", score: min(1, Double(s.thoughts.count) / n)))
        }

        return out.sorted { $0.score > $1.score }
    }

    /// A one-line headline summarizing the top traits.
    static func headline(_ traits: [PersonalityTrait]) -> String {
        let top = traits.prefix(2).map(\.title)
        if top.isEmpty { return "Your Style Is Forming" }
        if top.count == 1 { return "The \(top[0])" }
        return "\(top[0]) · \(top[1])"
    }
}

struct PersonalityProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Smoking Style", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)

                let traits = PersonalityEngine.traits(session)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if traits.isEmpty {
                            EmptyStateView(icon: "person.fill.questionmark",
                                           title: "Your style is forming",
                                           message: "Log a few more seshes and we'll figure out your smoking style from your patterns.")
                        } else {
                            // Headline card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOUR SMOKING STYLE").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                                Text(PersonalityEngine.headline(traits))
                                    .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                                HStack(spacing: 6) {
                                    ForEach(traits.prefix(3)) { Text($0.emoji).font(.system(size: 22)) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.green.opacity(0.25), Palette.field], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))

                            // Trait breakdown
                            Text("What defines you").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                            VStack(spacing: 10) {
                                ForEach(traits) { traitCard($0) }
                            }

                            Text("Generated from your logged sessions. The more you log, the sharper it gets.")
                                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    private func traitCard(_ t: PersonalityTrait) -> some View {
        HStack(spacing: 14) {
            Text(t.emoji).font(.system(size: 28)).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(t.blurb).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                // Strength bar
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.field).frame(height: 6)
                    Capsule().fill(Palette.green).frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: max(0.05, min(1, t.score)), anchor: .leading)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}
