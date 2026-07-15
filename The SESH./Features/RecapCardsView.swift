//
//  RecapCardsView.swift
//  The SESH
//
//  (Feature 20) Shareable recap cards. Weekly or monthly summaries rendered
//  as a card image via ImageRenderer + ShareLink. Privacy-safe by design:
//  every field is a toggle, everything defaults to aggregate numbers only,
//  and nothing is shared until YOU hit the share button.
//

import SwiftUI

struct RecapCardsView: View {
    @Environment(AppSession.self) private var session

    enum Period: String, CaseIterable, Identifiable {
        case week = "This week", month = "This month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var period: Period = .week
    @State private var showSessions = true
    @State private var showTopStrain = true
    @State private var showSpend = false
    @State private var showThoughts = false

    private var entries: [JournalEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period.days, to: Date())!
        return session.entries.filter { $0.date >= cutoff }
    }

    private var topStrain: String? {
        var counts: [String: Int] = [:]
        for e in entries where !e.strain.isEmpty { counts[e.strain, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
    private var spend: Double { entries.compactMap(\.price).reduce(0, +) }
    private var thoughtCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period.days, to: Date())!
        return session.thoughts.filter { $0.date >= cutoff }.count
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)

                    card
                        .frame(maxWidth: .infinity)

                    FieldLabel(text: "What's on the card")
                    Toggle("Session count", isOn: $showSessions).tint(Palette.green)
                    Toggle("Top strain", isOn: $showTopStrain).tint(Palette.green)
                    Toggle("Spend", isOn: $showSpend).tint(Palette.green)
                    Toggle("Thoughts captured", isOn: $showThoughts).tint(Palette.green)

                    ShareLink(item: renderCard(),
                              preview: SharePreview("My SESH recap", image: renderCard())) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share recap").font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                        .foregroundStyle(.white)
                    }
                }
                .padding(16)
                .foregroundStyle(Palette.text)
            }
        }
        .navigationTitle("Recap Cards")
    }

    /// The card itself — also what gets rendered to an image.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("The SESH").font(.system(size: 15, weight: .bold, design: .serif))
                Spacer()
                Text(period.rawValue).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))

            if showSessions {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(entries.count)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("sesh\(entries.count == 1 ? "" : "es")")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if showTopStrain, let top = topStrain {
                    recapLine("crown.fill", "Top strain: \(top)")
                }
                if showSpend, spend > 0 {
                    recapLine("dollarsign.circle.fill", "Spend: \(spend.formatted(.currency(code: "USD")))")
                }
                if showThoughts, thoughtCount > 0 {
                    recapLine("bubble.left.fill", "\(thoughtCount) high thought\(thoughtCount == 1 ? "" : "s")")
                }
            }
            Text("sesh responsibly 🌿")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(22)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.18),
                                              Color(red: 0.04, green: 0.12, blue: 0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private func recapLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.92))
    }

    @MainActor
    private func renderCard() -> Image {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "photo")
    }
}
