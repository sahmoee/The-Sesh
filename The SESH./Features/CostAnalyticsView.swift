//
//  CostAnalyticsView.swift
//  The SESH
//
//  (Feature 12) Cost-per-session analytics: cost per sesh, per method, per
//  strain, per month, and average session duration — all from the journal.
//

import SwiftUI

struct CostAnalyticsView: View {
    @Environment(AppSession.self) private var session

    private var priced: [JournalEntry] { session.entries.filter { $0.price != nil } }
    private var totalSpend: Double { priced.compactMap(\.price).reduce(0, +) }
    private var costPerSession: Double {
        // Average over the sessions that actually have a price — dividing by
        // ALL entries silently deflated the number as unpriced logs piled up.
        priced.isEmpty ? 0 : totalSpend / Double(priced.count)
    }
    private var avgDuration: Int {
        let ds = session.entries.compactMap(\.durationMinutes)
        return ds.isEmpty ? 0 : ds.reduce(0, +) / ds.count
    }

    private func grouped(_ key: (JournalEntry) -> String) -> [(String, Double)] {
        var out: [String: Double] = [:]
        for e in priced { out[key(e), default: 0] += e.price ?? 0 }
        return out.sorted { $0.value > $1.value }
    }

    private var byMethod: [(String, Double)] { grouped { $0.method } }
    private var byStrain: [(String, Double)] { Array(grouped { $0.strain }.prefix(8)) }
    private var byMonth: [(String, Double)] {
        let fmt = Date.FormatStyle().month(.abbreviated).year(.twoDigits)
        var out: [(Date, Double)] = []
        var bucket: [Date: Double] = [:]
        let cal = Calendar.current
        for e in priced {
            let m = cal.date(from: cal.dateComponents([.year, .month], from: e.date))!
            bucket[m, default: 0] += e.price ?? 0
        }
        out = bucket.sorted { $0.key > $1.key }
        return out.prefix(6).map { ($0.0.formatted(fmt), $0.1) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if session.entries.isEmpty {
                        EmptyHint(symbol: "chart.pie",
                                  text: "Log sessions with prices to see where the money goes.")
                    } else {
                        HStack(spacing: 10) {
                            statCard("Per sesh", costPerSession.formatted(.currency(code: "USD")))
                            statCard("Total tracked", totalSpend.formatted(.currency(code: "USD")))
                            statCard("Avg length", avgDuration > 0 ? "\(avgDuration)m" : "—")
                        }
                        section("By month", byMonth)
                        section("By method", byMethod)
                        section("Top strains", byStrain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Cost per Sesh")
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func section(_ title: String, _ rows: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            if rows.isEmpty {
                Text("No priced sessions yet.").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
            } else {
                let maxV = rows.map(\.1).max() ?? 1
                ForEach(rows, id: \.0) { name, value in
                    HStack(spacing: 10) {
                        Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            .frame(width: 92, alignment: .leading).lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.green.opacity(0.75))
                                .frame(width: max(4, geo.size.width * (value / maxV)))
                        }
                        .frame(height: 10)
                        Text(value.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name): \(value.formatted(.currency(code: "USD")))")
                }
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}
