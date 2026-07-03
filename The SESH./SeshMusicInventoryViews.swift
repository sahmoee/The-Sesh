//
//  SeshMusicInventoryViews.swift
//  The SESH
//
//  Two feature-pack screens that lean on captured data:
//   • MusicStationsView   — strain/vibe "stations" generated from your song
//                            history (AppSession.musicStations()).
//   • StashInventoryView  — grams-tracking inventory with low-stock flags,
//                            complementing the existing StashView purchase log.
//

import SwiftUI

// MARK: - Music Stations

struct MusicStationsView: View {
    @Environment(AppSession.self) private var session

    private var stations: [MusicStation] { session.musicStations() }

    var body: some View {
        ScrollView {
            if stations.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No stations yet",
                               message: "Play music during your seshes with a source connected, and stations built from what you played will show up here.")
            } else {
                VStack(spacing: 14) {
                    Text("Built from the songs you played during seshes.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(stations) { station in
                        NavigationLink { StationDetailView(station: station) } label: {
                            stationCard(station)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Music Stations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stationCard(_ station: MusicStation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(station.tint.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: station.symbol).font(.system(size: 22)).foregroundStyle(station.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(station.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(station.subtitle).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Text("\(station.songs.count) songs").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

private struct StationDetailView: View {
    let station: MusicStation

    var body: some View {
        List {
            Section {
                ForEach(Array(station.songs.enumerated()), id: \.element.id) { idx, song in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                            Text(song.artist).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("×\(song.count)").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    }
                }
            } header: {
                Text(station.subtitle)
            }
        }
        .navigationTitle(station.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Stash Inventory (grams + low-stock)

struct StashInventoryView: View {
    @Environment(AppSession.self) private var session

    private var inStock: [Purchase] { session.purchases.filter { !$0.isEmpty }.sorted { $0.remaining < $1.remaining } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if session.hasLowStock {
                    lowStockBanner
                }
                if inStock.isEmpty {
                    EmptyStateView(icon: "shippingbox", title: "Nothing in your stash",
                                   message: "Add purchases in Your Stash and they'll show here with remaining amounts and low-stock flags.")
                } else {
                    ForEach(inStock) { p in inventoryRow(p) }
                }
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lowStockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.gold)
            Text("\(session.lowStockPurchases.count) item\(session.lowStockPurchases.count == 1 ? "" : "s") running low")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.gold.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.gold.opacity(0.4), lineWidth: 1))
    }

    private func inventoryRow(_ p: Purchase) -> some View {
        let ratio = p.amount > 0 ? p.remaining / p.amount : 0
        let low = ratio <= 0.2
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                if low {
                    Text("LOW").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.gold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.gold.opacity(0.18)))
                }
                Spacer()
                Text(p.amountLine).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.field)
                    Capsule().fill(low ? Palette.gold : Palette.greenBright)
                        .frame(width: max(4, geo.size.width * CGFloat(ratio)))
                }
            }
            .frame(height: 8)
            Text("\(Fmt.currency(p.costPerUnit))/\(p.unit) · bought \(Fmt.shortDate(p.date))")
                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}
