//
//  MusicMemoryViews.swift
//  The SESH
//
//  The visible Memory and Identity layers of Music:
//   - MusicMemoryView (Track): song history + the strains they paired with,
//     built from songs captured during sessions.
//   - MusicIdentityView (Me): the taste profile — which songs pair with which
//     strains, and which vibes you reach for.
//

import SwiftUI

// MARK: - Memory (Track)

struct MusicMemoryView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "History"
    private let tabs = ["History", "Top Songs", "By Strain"]

    // Aggregations hoisted out of the ForEach loops (they group/sort the whole
    // play history) and refreshed only when the play list changes.
    @State private var historyItems: [StrainSongPlay] = []
    @State private var topSongItems: [SongTally] = []
    @State private var pairingItems: [StrainMusicPairing] = []

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Music Memory", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                UnderlineTabs(items: tabs, selection: $tab)
                    .padding(.horizontal, 18).padding(.bottom, 8)

                if session.songPlays.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            switch tab {
                            case "Top Songs": topSongs
                            case "By Strain": byStrain
                            default:          history
                            }
                            Color.clear.frame(height: 24)
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
        .task(id: session.songPlays.count) {
            let plays = session.songPlays
            historyItems = MusicMemory.history(plays)
            topSongItems = MusicMemory.topSongs(plays)
            pairingItems = MusicMemory.pairings(plays)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list").font(.system(size: 44)).foregroundStyle(Palette.greenBright)
            Text("No music yet").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text("Play music during a sesh and it'll show up here, tied to the strain you were smoking.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer(); Spacer()
        }
    }

    private var history: some View {
        ForEach(historyItems) { play in
            HStack(spacing: 12) {
                artwork(play.artworkURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(play.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(play.artist).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill").font(.system(size: 9)).foregroundStyle(Palette.green)
                        Text(play.strainName).font(.system(size: 11)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text(Fmt.relative(play.date)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    private var topSongs: some View {
        ForEach(Array(topSongItems.enumerated()), id: \.element.id) { idx, song in
            HStack(spacing: 12) {
                Text("\(idx + 1)").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gold).frame(width: 22)
                artwork(song.artworkURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(song.artist).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer()
                Text("\(song.count)×").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.greenBright)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    private var byStrain: some View {
        ForEach(pairingItems) { pairing in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pairing.strainName).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                    Spacer()
                    Text("\(pairing.playCount) play\(pairing.playCount == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                ForEach(pairing.topSongs) { song in
                    HStack(spacing: 8) {
                        Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Palette.greenBright)
                        Text(song.title).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        Text("· \(song.artist)").font(.system(size: 12)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    @ViewBuilder private func artwork(_ url: String?) -> some View {
        if let url, let u = URL(string: url) {
            AsyncImage(url: u) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Palette.field)
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Palette.field)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(Palette.textTertiary))
        }
    }

}

// MARK: - Identity (Me)

struct MusicIdentityView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    // Hoisted aggregations, refreshed only when the play list changes.
    @State private var breakdown: [(vibe: SessionType, count: Int)] = []
    @State private var pairingItems: [StrainMusicPairing] = []

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Your Music Identity", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                if session.songPlays.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            vibeSection
                            pairingSection
                            Color.clear.frame(height: 24)
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
        .task(id: session.songPlays.count) {
            let plays = session.songPlays
            breakdown = MusicMemory.vibeBreakdown(plays)
            pairingItems = MusicMemory.pairings(plays, limit: 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 44)).foregroundStyle(Palette.purple)
            Text("Building your profile").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text("As you sesh with music on, Sesh learns which songs and vibes pair with each strain.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer(); Spacer()
        }
    }

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your sesh vibes").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            Text("The moods you reach for most when the music's on.")
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            let total = max(1, breakdown.map(\.count).reduce(0, +))
            ForEach(breakdown, id: \.vibe) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.vibe.rawValue).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(Int(Double(item.count) / Double(total) * 100))%")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.purple)
                    }
                    GeometryFreeBar(fraction: Double(item.count) / Double(total))
                }
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Strain pairings").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            Text("What you play with each strain.")
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            ForEach(pairingItems) { pairing in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pairing.strainName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.greenBright)
                    ForEach(pairing.topSongs) { song in
                        Text("\(song.title) · \(song.artist)")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
        }
    }
}
