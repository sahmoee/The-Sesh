//
//  ListenView.swift
//  The SESH
//
//  The "Listen" screen (from the new mockup): a music home that shows "Your
//  Vibes" — mood tiles that each open (or create) a playlist for that vibe — and
//  "Recent Playlists" from the PlaylistStore. The mood tiles use the generated
//  mood art when present (vintage or midnight, following the icon style), with a
//  graceful SF Symbol fallback.
//

import SwiftUI

struct ListenView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The four vibes shown as tiles, each tied to an asset + a playlist name.
    private let vibes: [Vibe] = [
        Vibe(name: "Relaxed",   asset: "mood_relaxed",   symbol: "leaf.fill",        tint: .green),
        Vibe(name: "Creative",  asset: "mood_creative",  symbol: "lightbulb.fill",   tint: .purple),
        Vibe(name: "Energetic", asset: "mood_energetic", symbol: "bolt.fill",        tint: .orange),
        Vibe(name: "Late Night", asset: "mood_latenight", symbol: "moon.stars.fill", tint: .indigo),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Listen", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    yourVibes
                    recentPlaylists
                    Color.clear.frame(height: 20)
                }
                .padding(18)
            }
        }
        .background(AppBackground())
    }

    // MARK: Your Vibes

    private var yourVibes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Vibes")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.text)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(vibes) { vibe in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlistID(for: vibe))
                    } label: {
                        vibeTile(vibe)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func vibeTile(_ vibe: Vibe) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(vibeFill(vibe))
                .frame(height: 120)
            vibeArt(vibe)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(10)
            Text(vibe.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(14)
        }
        .frame(height: 120)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .clipped()
    }

    /// Mood art if the asset exists (respecting the midnight suffix), else SF Symbol.
    @ViewBuilder private func vibeArt(_ vibe: Vibe) -> some View {
        let midnightName = vibe.asset + "_midnight"
        let useMidnight = theme.iconStyle == .midnight && UIImage(named: midnightName) != nil
        let name = useMidnight ? midnightName : vibe.asset
        if UIImage(named: name) != nil {
            Image(name).resizable().scaledToFit().frame(width: 56, height: 56)
        } else {
            Image(systemName: vibe.symbol)
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 56, height: 56)
        }
    }

    private func vibeFill(_ vibe: Vibe) -> LinearGradient {
        let base: Color
        switch vibe.tint {
        case .green:  base = Palette.greenDeep
        case .purple: base = Palette.purple
        case .orange: base = Palette.moodAngry
        case .indigo: base = Palette.purpleStroke
        }
        return LinearGradient(colors: [base.opacity(0.85), base.opacity(0.45)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Recent Playlists

    private var recentPlaylists: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Playlists")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.text)
                Spacer()
                NavigationLink {
                    PlaylistsView()
                } label: {
                    Text("See all").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.greenBright)
                }
                .buttonStyle(.plain)
            }
            if playlists.playlists.isEmpty {
                emptyPlaylists
            } else {
                ForEach(playlists.playlists.prefix(5)) { pl in
                    NavigationLink {
                        PlaylistDetailView(playlistID: pl.id)
                    } label: {
                        PlaylistRow(playlist: pl)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyPlaylists: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 32)).foregroundStyle(Palette.textTertiary)
            Text("No playlists yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            Text("Pick a vibe above to start one, or build your own.")
                .font(.system(size: 13)).foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    // MARK: Helpers

    /// Find or create the playlist for a vibe, returning its id.
    private func playlistID(for vibe: Vibe) -> String {
        let name = "\(vibe.name) Mix"
        if let existing = playlists.playlists.first(where: { $0.name == name }) {
            return existing.id
        }
        return playlists.createPlaylist(name: name, autoCollect: false).id
    }
}

/// A "vibe" entry for the Listen screen.
private struct Vibe: Identifiable {
    enum Tint { case green, purple, orange, indigo }
    var id: String { name }
    let name: String
    let asset: String     // base asset name (mood_*)
    let symbol: String    // SF Symbol fallback
    let tint: Tint
}
