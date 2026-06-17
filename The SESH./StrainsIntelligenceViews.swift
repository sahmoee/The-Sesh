//
//  StrainsIntelligenceViews.swift
//  The SESH
//
//  The Strains tab's "intelligence center" surfaces: Compare Strains, Find My
//  Vibe, What Should I Buy, and the Wishlist. All powered by your logged history
//  via the AppSession intelligence engine.
//

import SwiftUI

// MARK: - Tools hub (entry card shown atop the Library)

struct StrainToolsBar: View {
    @State private var route: Tool?

    enum Tool: String, Identifiable { case compare, vibe, buy, wishlist; var id: String { rawValue } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolButton("Compare", "rectangle.split.3x1", .compare)
                toolButton("Find My Vibe", "sparkles", .vibe)
                toolButton("What to Buy", "cart", .buy)
                toolButton("Wishlist", "bookmark", .wishlist)
            }
            .padding(.horizontal, 18)
        }
        .sheet(item: $route) { tool in
            switch tool {
            case .compare:  CompareStrainsView()
            case .vibe:     FindMyVibeView()
            case .buy:      WhatShouldIBuyView()
            case .wishlist: WishlistView()
            }
        }
    }

    private func toolButton(_ title: String, _ icon: String, _ tool: Tool) -> some View {
        Button { route = tool; Haptics.tap() } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared strain multi-picker (used by Compare & What to Buy)

struct StrainMultiPicker: View {
    @Environment(StrainStore.self) private var strains
    @Binding var selected: [String]
    var max: Int = 4
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Selected chips
            if !selected.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(selected, id: \.self) { name in
                        Button { selected.removeAll { $0 == name }; Haptics.selection() } label: {
                            HStack(spacing: 5) {
                                Text(name).font(.system(size: 13, weight: .medium))
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Palette.onGreen)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Palette.green))
                        }.buttonStyle(.plain)
                    }
                }
            }

            InputField(label: "", placeholder: "Search strains to add…", value: $query)

            if !query.isEmpty {
                let matches = strains.strains
                    .filter { $0.name.lowercased().contains(query.lowercased()) && !selected.contains($0.name) }
                    .prefix(6)
                VStack(spacing: 0) {
                    ForEach(Array(matches)) { s in
                        Button {
                            guard selected.count < max else { return }
                            selected.append(s.name); query = ""; Haptics.selection()
                        } label: {
                            HStack {
                                Text(s.name).font(.system(size: 14)).foregroundStyle(Palette.text)
                                Spacer()
                                Text(s.type.rawValue).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.green)
                            }
                            .padding(.vertical, 9)
                        }.buttonStyle(.plain)
                        Divider().overlay(Palette.stroke)
                    }
                }
            }
            if selected.count >= max {
                Text("Up to \(max) strains.").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

// MARK: - Compare Strains

struct CompareStrainsView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss
    @State private var picks: [String] = []

    private let effectRows = ["Happy", "Relaxed", "Creative", "Energetic", "Sleepy", "Focused"]

    /// Look up the catalog profile for a picked strain (nil if somehow absent).
    private func profile(_ name: String) -> StrainProfile? {
        strains.strains.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Compare Strains", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Compare any strains — from the catalog or your own history. Add a few and see how they stack up.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 18)

                        DarkCard { StrainMultiPicker(selected: $picks, max: 4) }
                            .padding(.horizontal, 18)

                        if picks.count >= 2 {
                            comparisonGrid
                            recommendation
                        } else {
                            Text("Add at least 2 strains to compare.")
                                .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                                .frame(maxWidth: .infinity).padding(.top, 20)
                        }
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private var stats: [StrainPersonalStats] { picks.map { session.personalStats(forStrain: $0) } }

    private var comparisonGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                gridRow("", picks.map { $0 }, header: true)
                // Database attributes (work for ANY strain, logged or not)
                sectionLabel("STRAIN INFO")
                gridDataRow("Type", picks.map { profile($0)?.type.rawValue ?? "—" })
                gridDataRow("THC", picks.map { p in profile(p)?.thc.map { String(format: "%.0f%%", $0) } ?? "—" })
                gridDataRow("Top Effects", picks.map { p in
                    let effs = profile(p)?.effects.prefix(2).map(\.name).joined(separator: ", ")
                    return (effs?.isEmpty ?? true) ? "—" : (effs ?? "—")
                })
                // Your personal history
                sectionLabel("YOUR HISTORY")
                gridDataRow("Your Rating", stats.map { $0.hasHistory ? String(format: "%.1f", $0.averageRating) : "—" })
                gridDataRow("Sessions", stats.map { "\($0.sessions)" })
                gridDataRow("Favorite", stats.map { $0.isFavorite ? "Yes" : "No" })
                ForEach(effectRows, id: \.self) { eff in
                    gridEffectRow(eff)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
            Spacer()
        }
        .padding(.top, 12).padding(.bottom, 4)
    }

    private func gridRow(_ label: String, _ values: [String], header: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Text(v).font(.system(size: 13, weight: header ? .bold : .regular))
                    .foregroundStyle(Palette.text).frame(width: 92, alignment: .leading).lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Palette.stroke).frame(height: header ? 0 : 0.5), alignment: .bottom)
    }

    private func gridDataRow(_ label: String, _ values: [String]) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Text(v).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                    .frame(width: 92, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .bottom)
    }

    private func gridEffectRow(_ effect: String) -> some View {
        HStack(spacing: 0) {
            Text(effect).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            ForEach(picks, id: \.self) { name in
                let level = session.effectLevel(strain: name, effect: effect)
                Text(level.rawValue).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(level.tint).frame(width: 92, alignment: .leading)
            }
        }
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .bottom)
    }

    private var recommendation: some View {
        let ranked = stats.filter { $0.hasHistory }.sorted { $0.averageRating > $1.averageRating }
        return Group {
            if let best = ranked.first {
                DarkCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Best Match", systemImage: "trophy.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.gold)
                        Text(best.name).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
                        Text("Based on your history — highest rated of the strains you've logged here.")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                DarkCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No personal pick yet", systemImage: "info.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.gold)
                        Text("You haven't logged any of these, so there's no pick from your history — but you can still compare their type, THC, and effects above. Log a few sessions and the recommendation gets smarter.")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

// MARK: - Find My Vibe

struct FindMyVibeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var desired: Set<String> = []

    private let options = ["Relaxed", "Happy", "Creative", "Sleepy", "Focused", "Energetic", "Giggly", "Hungry", "Thoughtful"]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Find My Vibe", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How do you want to feel? We'll match it against the strains that have done it for you.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

                        FlowLayout(spacing: 10) {
                            ForEach(options, id: \.self) { eff in
                                Button {
                                    if desired.contains(eff) { desired.remove(eff) } else { desired.insert(eff) }
                                    Haptics.selection()
                                } label: {
                                    Text(eff).font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(desired.contains(eff) ? Palette.onGreen : Palette.text)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .background(Capsule().fill(desired.contains(eff) ? Palette.green : Palette.field))
                                        .overlay(Capsule().stroke(Palette.stroke, lineWidth: desired.contains(eff) ? 0 : 1))
                                }.buttonStyle(.plain)
                            }
                        }

                        if !desired.isEmpty {
                            let results = session.findMyVibe(effects: desired)
                            if results.isEmpty {
                                emptyResults
                            } else {
                                Text("Your matches").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 6)
                                ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                                    DarkCard(padding: 14) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(r.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                                Text("\(r.matches) matching \(r.matches == 1 ? "session" : "sessions") · avg \(String(format: "%.1f", r.rating))")
                                                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "leaf.fill").foregroundStyle(Palette.greenBright)
                                        }
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private var emptyResults: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No matches in your history yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Log sessions with effects tagged and Find My Vibe will surface the strains that match how you want to feel.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - What Should I Buy?

struct WhatShouldIBuyView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var available: [String] = []

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "What Should I Buy?", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enter what's available and SESH picks your best bet — with the reasons why.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

                        DarkCard { StrainMultiPicker(selected: $available, max: 8) }

                        if !available.isEmpty {
                            let picks = session.whatShouldIBuy(from: available)
                            if let best = picks.first {
                                DarkCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Best Match", systemImage: "checkmark.seal.fill")
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green)
                                        Text(best.name).font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.text)
                                        ForEach(best.reasons, id: \.self) { r in
                                            HStack(spacing: 8) {
                                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.greenBright)
                                                Text(r).font(.system(size: 13)).foregroundStyle(Palette.text)
                                            }
                                        }
                                    }
                                }
                            }
                            if picks.count > 1 {
                                Text("The rest").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary).padding(.top, 4)
                                ForEach(picks.dropFirst()) { pick in
                                    DarkCard(padding: 14) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pick.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                                Text(pick.stats.hasHistory
                                                     ? "\(pick.stats.sessions) sessions · \(String(format: "%.1f", pick.stats.averageRating))"
                                                     : "No history yet")
                                                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                            }
                                            Spacer()
                                            Text("\(Int(pick.score))").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.gold)
                                        }
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }
}

// MARK: - Wishlist

struct WishlistView: View {
    @Environment(WishlistStore.self) private var wishlist
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Wishlist", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Strains you want to try. Add from the catalog or jot any name.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

                        DarkCard {
                            VStack(alignment: .leading, spacing: 10) {
                                InputField(label: "Add to wishlist", placeholder: "Strain name…", value: $query)
                                if !query.isEmpty {
                                    let matches = strains.strains
                                        .filter { $0.name.lowercased().contains(query.lowercased()) && !wishlist.contains($0.name) }
                                        .prefix(5)
                                    ForEach(Array(matches)) { s in
                                        Button { wishlist.add(s.name); query = ""; Haptics.success() } label: {
                                            HStack {
                                                Text(s.name).font(.system(size: 14)).foregroundStyle(Palette.text)
                                                Spacer()
                                                Image(systemName: "plus.circle.fill").foregroundStyle(Palette.green)
                                            }.padding(.vertical, 7)
                                        }.buttonStyle(.plain)
                                    }
                                    if !query.isEmpty {
                                        Button { wishlist.add(query); query = ""; Haptics.success() } label: {
                                            Text("Add \"\(query)\"").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if wishlist.items.isEmpty {
                            EmptyStateView(icon: "bookmark", title: "Wishlist empty",
                                           message: "Add strains you're curious about and want to track down.")
                                .padding(.top, 30)
                        } else {
                            ForEach(wishlist.items) { item in
                                DarkCard(padding: 14) {
                                    HStack {
                                        Image(systemName: "bookmark.fill").foregroundStyle(Palette.gold)
                                        Text(item.strainName).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
                                        Spacer()
                                        Button { wishlist.remove(item); Haptics.warning() } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }
}
