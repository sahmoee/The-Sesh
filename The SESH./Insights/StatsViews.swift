//
//  StatsViews.swift
//  The SESH
//
//  Split out of InsightsScreens.swift (#3 — file size). No code changes.
//

import SwiftUI

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
                statBox(averageDurationText, "Avg Duration")
            }
            ToleranceCard()
            championsCard
        }
    }

    /// Average logged session length (replaces the duplicated "Day Streak" box).
    private var averageDurationText: String {
        let durations = session.entries.compactMap(\.durationMinutes)
        guard !durations.isEmpty else { return "—" }
        let avg = Double(durations.reduce(0, +)) / Double(durations.count)
        return "\(Int(avg.rounded()))m"
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
            (m, session.entries.count(where: { $0.mood == m }))
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
    /// Evenly spaced y-axis labels derived from the actual bar scale.
    private var axisValues: [Int] {
        let top = Int(maxVal.rounded())
        return [top, top * 2 / 3, top / 3, 0]
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                // y-axis labels
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(axisValues, id: \.self) { v in
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

