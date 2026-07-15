//
//  StrainDetailViews.swift
//  The SESH
//
//  Split out of InsightsScreens.swift (#3 — file size). No code changes.
//

import SwiftUI

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
            let n = items.count(where: { moods.contains($0.mood ?? .other) })
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
                    StoredImage(name: profile?.photoName, size: 64, corner: Radius.md,
                                strainID: profile?.id ?? insight.name)
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
    Fmt.mediumDate(date)
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
