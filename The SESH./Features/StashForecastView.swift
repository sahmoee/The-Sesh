//
//  StashForecastView.swift
//  The SESH
//
//  (Feature 11) Stash depletion forecasts. Estimates days remaining per
//  purchase from the last 30 days of logged consumption, clearly labelled as
//  an estimate — the stash itself is always manually correctable.
//

import SwiftUI

struct StashForecastView: View {
    @Environment(AppSession.self) private var session

    /// Average daily draw-down over the last 30 days, per unit-compatible use.
    private var dailyBurn: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let used = session.entries
            .filter { $0.date >= cutoff }
            .compactMap(\.amount)
            .reduce(0, +)
        return used / 30
    }

    private struct Forecast: Identifiable {
        let id: UUID
        let purchase: Purchase
        let daysLeft: Int?     // nil = not enough data
    }

    private var forecasts: [Forecast] {
        let burn = dailyBurn
        return session.stashRemaining.map { p in
            let days = burn > 0.01 ? Int((p.remaining / burn).rounded(.down)) : nil
            return Forecast(id: p.id, purchase: p, daysLeft: days)
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Forecast")
                    if forecasts.isEmpty {
                        EmptyHint(symbol: "archivebox",
                                  text: "Nothing in your stash yet. Add a purchase and log sessions with amounts to see forecasts.")
                    } else {
                        if dailyBurn > 0.01 {
                            Text(String(format: "You average %.2fg per day over the last 30 days.", dailyBurn))
                                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        } else {
                            Text("Log session amounts to unlock day estimates.")
                                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        }
                        ForEach(forecasts) { f in
                            forecastRow(f)
                        }
                        Text("Estimates from your logged use — the jar knows best. Adjust amounts in Stash any time.")
                            .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Stash Forecast")
    }

    private func forecastRow(_ f: Forecast) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f.purchase.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(f.purchase.amountLine).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if let days = f.daysLeft {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(days <= 0 ? "Running out" : "≈ \(days)d left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(days <= 5 ? Palette.moodAngry : Palette.greenBright)
                    if days > 0 {
                        Text(runOutDate(days)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                }
            } else {
                Text("—").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func runOutDate(_ days: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Small shared empty-state hint used by the Lab screens.
struct EmptyHint: View {
    var symbol: String
    var text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Palette.textTertiary)
            Text(text).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
