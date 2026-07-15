//
//  StrainMatchView.swift
//  The SESH
//
//  (Feature 13) Personal strain match score. Ranks strains you've actually
//  logged using YOUR data only: your ratings, repeat use, recency, mood lift,
//  and smoke-again verdicts. No community data, no server.
//

import SwiftUI

struct StrainMatchView: View {
    @Environment(AppSession.self) private var session

    struct Match: Identifiable {
        let id = UUID()
        let strain: String
        let score: Int          // 0-100
        let sessions: Int
        let avgRating: Double
        let moodLift: Double?   // avg moodAfter - moodBefore
    }

    private var matches: [Match] {
        var byStrain: [String: [JournalEntry]] = [:]
        for e in session.entries where !e.strain.isEmpty {
            byStrain[e.strain, default: []].append(e)
        }
        let nowDate = Date()
        return byStrain.map { strain, entries in
            let n = Double(entries.count)
            let avgRating = entries.map(\.rating).reduce(0, +) / n          // 0-5
            // Repeat use: log-scaled so 10 sessions isn't 10x one session.
            let repeatScore = min(1.0, log2(n + 1) / 4)                     // 0-1
            // Recency: newest entry within 30d = 1, fades to 0 at 180d.
            let days = entries.map { nowDate.timeIntervalSince($0.date) / 86_400 }.min() ?? 999
            let recency = max(0.0, min(1.0, (180 - days) / 150))
            // Mood lift where recorded.
            let lifts = entries.compactMap { e -> Double? in
                guard let b = e.moodBefore, let a = e.moodAfter else { return nil }
                return Double(a - b)
            }
            let moodLift = lifts.isEmpty ? nil : lifts.reduce(0, +) / Double(lifts.count)
            let moodScore = moodLift.map { max(0.0, min(1.0, ($0 + 1) / 3)) } ?? 0.5
            // Smoke-again verdicts.
            let verdicts = entries.compactMap(\.smokeAgain)
            let againScore = verdicts.isEmpty ? 0.5
                : Double(verdicts.filter { $0.rawValue.lowercased().contains("yes") }.count) / Double(verdicts.count)

            let score = 100 * (0.40 * (avgRating / 5) + 0.20 * repeatScore
                             + 0.15 * recency + 0.15 * moodScore + 0.10 * againScore)
            return Match(strain: strain, score: Int(score.rounded()),
                         sessions: entries.count, avgRating: avgRating, moodLift: moodLift)
        }
        .sorted { $0.score > $1.score }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if matches.isEmpty {
                        EmptyHint(symbol: "sparkles",
                                  text: "Log a few sessions and your strains get personal match scores here.")
                    } else {
                        Text("Scored from your ratings, repeat use, recency, mood lift, and verdicts. 100 = your perfect strain.")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        ForEach(Array(matches.enumerated()), id: \.element.id) { rank, m in
                            matchRow(rank: rank + 1, m)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Strain Match")
    }

    private func matchRow(rank: Int, _ m: Match) -> some View {
        HStack(spacing: 12) {
            Text("#\(rank)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textTertiary)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    Text("\(m.sessions) sesh\(m.sessions == 1 ? "" : "es")")
                    Text(String(format: "★ %.1f", m.avgRating))
                    if let lift = m.moodLift {
                        Text(String(format: "mood %+.1f", lift))
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            ZStack {
                Circle().stroke(Palette.stroke, lineWidth: 4).frame(width: 44, height: 44)
                Circle().trim(from: 0, to: CGFloat(m.score) / 100)
                    .stroke(m.score >= 75 ? Palette.greenBright : Palette.gold,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                Text("\(m.score)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.strain), match score \(m.score) of 100, \(m.sessions) sessions")
    }
}
