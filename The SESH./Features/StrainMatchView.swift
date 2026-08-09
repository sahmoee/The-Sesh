//
//  StrainMatchView.swift
//  The SESH
//
//  Compare Strain quick-action destination.
//

import SwiftUI

struct StrainMatchView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains

    struct Match: Identifiable, Hashable {
        let id: String
        let profile: StrainProfile
        let score: Int
        let sessions: Int
        let avgRating: Double
        let moodLift: Double?
    }

    @State private var leftIndex = 0
    @State private var rightIndex = 1

    private var matches: [Match] {
        let personal = personalMatches
        if personal.count >= 2 { return personal }
        return Array(strains.strains.prefix(12)).enumerated().map { offset, profile in
            Match(id: profile.id,
                  profile: profile,
                  score: 72 - min(offset, 18),
                  sessions: 0,
                  avgRating: 0,
                  moodLift: nil)
        }
    }

    private var personalMatches: [Match] {
        var byStrain: [String: [JournalEntry]] = [:]
        for entry in session.entries where !entry.strain.isEmpty {
            byStrain[entry.strain, default: []].append(entry)
        }

        let now = Date()
        return byStrain.compactMap { strainName, entries in
            guard let profile = profile(named: strainName) else {
                return nil
            }
            let count = Double(entries.count)
            guard count > 0 else { return nil }
            let avgRating = entries.map(\.rating).reduce(0, +) / count
            let repeatScore = min(1, log2(count + 1) / 4)
            let newestDays = entries.map { now.timeIntervalSince($0.date) / 86_400 }.min() ?? 999
            let recency = max(0, min(1, (180 - newestDays) / 150))
            let lifts = entries.compactMap { entry -> Double? in
                guard let before = entry.moodBefore, let after = entry.moodAfter else { return nil }
                return Double(after - before)
            }
            let moodLift = lifts.isEmpty ? nil : lifts.reduce(0, +) / Double(lifts.count)
            let moodScore = moodLift.map { max(0, min(1, ($0 + 1) / 3)) } ?? 0.5
            let verdicts = entries.compactMap(\.smokeAgain)
            let againScore = verdicts.isEmpty ? 0.5
                : Double(verdicts.filter { $0.rawValue.lowercased().contains("yes") }.count) / Double(verdicts.count)
            let score = 100 * (0.40 * (avgRating / 5) + 0.20 * repeatScore + 0.15 * recency + 0.15 * moodScore + 0.10 * againScore)
            return Match(id: profile.id,
                         profile: profile,
                         score: Int(score.rounded()),
                         sessions: entries.count,
                         avgRating: avgRating,
                         moodLift: moodLift)
        }
        .sorted { $0.score > $1.score }
    }

    private var left: Match? { matches.indices.contains(leftIndex) ? matches[leftIndex] : matches.first }
    private var right: Match? {
        let fallback = matches.count > 1 ? matches[1] : matches.first
        return matches.indices.contains(rightIndex) ? matches[rightIndex] : fallback
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            LoungeLampGlow().padding(.top, -18)
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let left, let right {
                        matchup(left, right)
                        swapButton
                        comparisonRows(left, right)
                        adviceCard(left, right)
                    } else {
                        EmptyHint(symbol: "leaf.fill",
                                  text: "Add or log two strains to compare their effects, vibe, and best use.")
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("Compare Strain")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 5) {
            LoungeLamp()
            Text("Strain Matchup")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(Palette.text)
                .shadow(color: Palette.gold.opacity(0.35), radius: 14, y: 2)
            Text("Compare two strains. Find your vibe.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private func matchup(_ left: Match, _ right: Match) -> some View {
        HStack(spacing: 10) {
            strainCard(left, side: .leading)
            vsBadge
            strainCard(right, side: .trailing)
        }
    }

    private enum CardSide { case leading, trailing }

    private func strainCard(_ match: Match, side: CardSide) -> some View {
        Button {
            advance(side)
        } label: {
            VStack(spacing: 10) {
                HStack {
                    typePill(match.profile.type)
                    Spacer()
                }
                BudThumb(size: 96, seed: abs(match.profile.id.hashValue))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.goldRing.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                Text(match.profile.name)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(summary(match))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                stars(match)
                FlowLayout(spacing: 6) {
                    ForEach(effectTags(match.profile).prefix(3), id: \.self) { tag in
                        LoungeChip(text: tag)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.cardElevated, Palette.card],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.goldRing.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(match.profile.name), tap to change")
    }

    private var vsBadge: some View {
        Text("VS")
            .font(.system(size: 17, weight: .bold, design: .serif))
            .foregroundStyle(Palette.text)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Palette.field))
            .overlay(Circle().stroke(Palette.goldRing.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            .zIndex(1)
            .accessibilityHidden(true)
            .padding(.horizontal, -22)
    }

    private var swapButton: some View {
        Button {
            Haptics.selection()
            swap(&leftIndex, &rightIndex)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Swap Strains")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.goldSoft)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(Palette.goldRing.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func comparisonRows(_ left: Match, _ right: Match) -> some View {
        VStack(spacing: 9) {
            compareRow(title: "Effects", icon: "sun.max.fill",
                       left: effectTags(left.profile).prefix(3).joined(separator: ", "),
                       right: effectTags(right.profile).prefix(3).joined(separator: ", "))
            compareRow(title: "Vibe", icon: "sofa.fill",
                       left: vibe(left.profile),
                       right: vibe(right.profile))
            compareRow(title: "Best Time", icon: "moon.stars.fill",
                       left: bestTime(left.profile),
                       right: bestTime(right.profile))
            compareRow(title: "Best With", icon: "smoke.fill",
                       left: bestMethod(left.profile),
                       right: bestMethod(right.profile))
            compareRow(title: "Your Data", icon: "chart.bar.fill",
                       left: dataLine(left),
                       right: dataLine(right))
        }
    }

    private func compareRow(title: String, icon: String, left: String, right: String) -> some View {
        HStack(spacing: 0) {
            Text(left)
                .frame(maxWidth: .infinity)
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
            }
            .frame(width: 126)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.cardElevated))
            Text(right)
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field.opacity(0.84)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private func adviceCard(_ left: Match, _ right: Match) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("Can't decide?")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.text)
                Text(advice(left, right))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(Palette.gold)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.goldRing.opacity(0.35), lineWidth: 1))
    }

    private func typePill(_ type: StrainType) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill")
            Text(type.rawValue)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(type.tint.opacity(0.28)))
        .overlay(Capsule().stroke(type.tint.opacity(0.45), lineWidth: 1))
    }

    private func stars(_ match: Match) -> some View {
        HStack(spacing: 3) {
            let rating = match.sessions > 0 ? match.avgRating : Double(match.score) / 20
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: Double(index) + 0.5 < rating ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.gold)
            }
            Text(match.sessions > 0 ? String(format: "%.1f", match.avgRating) : "\(match.score)%")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func advance(_ side: CardSide) {
        guard matches.count > 1 else { return }
        Haptics.selection()
        switch side {
        case .leading:
            repeat { leftIndex = (leftIndex + 1) % matches.count } while leftIndex == rightIndex
        case .trailing:
            repeat { rightIndex = (rightIndex + 1) % matches.count } while rightIndex == leftIndex
        }
    }

    private func summary(_ match: Match) -> String {
        if match.sessions > 0 { return "\(match.score)% match from \(match.sessions) logged sesh\(match.sessions == 1 ? "" : "es")" }
        return match.profile.summary ?? "Tap to cycle strains"
    }

    private func profile(named name: String) -> StrainProfile? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return strains.strains.first { profile in
            profile.matchKeys.contains(key)
        } ?? strains.suggestions(for: name, limit: 1).first
    }

    private func effectTags(_ profile: StrainProfile) -> [String] {
        let names = profile.effects.map(\.name)
        return names.isEmpty ? [profile.type.rawValue, "Balanced"] : names
    }

    private func vibe(_ profile: StrainProfile) -> String {
        let effects = Set(effectTags(profile).map { $0.lowercased() })
        if effects.contains(where: { $0.contains("creative") || $0.contains("euphor") }) { return "Creative lift" }
        if effects.contains(where: { $0.contains("sleep") || $0.contains("relax") }) { return "Chill lounge energy" }
        if profile.type == .sativa { return "Daytime vibe" }
        return "Smooth and cozy"
    }

    private func bestTime(_ profile: StrainProfile) -> String {
        switch profile.type {
        case .sativa: return "Daytime"
        case .indica: return "Evening"
        case .hybrid: return "Afternoon or night"
        case .unknown: return "Anytime"
        }
    }

    private func bestMethod(_ profile: StrainProfile) -> String {
        switch profile.type {
        case .sativa: return "Vaping or edibles"
        case .indica: return "Smoking or bong"
        default: return "Smoking or vaping"
        }
    }

    private func dataLine(_ match: Match) -> String {
        if match.sessions == 0 { return "Catalog preview" }
        if let lift = match.moodLift { return String(format: "%d seshes, mood %+.1f", match.sessions, lift) }
        return "\(match.sessions) logged sesh\(match.sessions == 1 ? "" : "es")"
    }

    private func advice(_ left: Match, _ right: Match) -> String {
        if left.score == right.score { return "Both fit the moment. Pick based on whether you want the left vibe or the right vibe." }
        let winner = left.score > right.score ? left.profile.name : right.profile.name
        return "\(winner) has the stronger personal match right now. Compare again after a few more logs."
    }
}
