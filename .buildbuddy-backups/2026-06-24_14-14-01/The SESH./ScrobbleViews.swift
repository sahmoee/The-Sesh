//
//  ScrobbleViews.swift
//  The SESH
//
//  UI for the now-playing scrobbler: a card for your own Home/status, a compact
//  line for friends in the feed and on profiles, and the Settings section with
//  source toggles, broadcast-mode toggles, and Spotify connect.
//

import SwiftUI
import MediaPlayer

// MARK: - Now Playing card (your own, on Home)

struct NowPlayingCard: View {
    @Environment(ScrobbleStore.self) private var scrobbler
    var body: some View {
        if let np = scrobbler.current, np.isCurrent() {
            HStack(spacing: 12) {
                artwork(for: np)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.greenBright)
                        Text("Now playing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                        Text("· \(np.source.label)")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(np.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(np.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    @ViewBuilder private func artwork(for np: NowPlaying) -> some View {
        if np.source == .appleMusic, let img = scrobbler.appleArtwork(size: CGSize(width: 92, height: 92)) {
            Image(uiImage: img).resizable().scaledToFill()
        } else if let urlStr = np.artworkURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                artworkPlaceholder
            }
        } else {
            artworkPlaceholder
        }
    }
    private var artworkPlaceholder: some View {
        ZStack {
            Palette.field
            Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(Palette.textTertiary)
        }
    }
}

// MARK: - Compact now-playing line (friends, in feed / profile)

struct NowPlayingLine: View {
    let np: NowPlaying
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.greenBright)
            Text(np.line)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Settings section

struct ScrobbleSettingsSection: View {
    @Environment(ScrobbleStore.self) private var scrobbler
    @Environment(SpotifyAuth.self) private var spotify

    @AppStorage(DefaultsKey.scrobbleApple) private var appleOn = false
    @AppStorage(DefaultsKey.scrobbleSpotify) private var spotifyOn = false
    @AppStorage(DefaultsKey.scrobbleAlways) private var always = false
    @AppStorage(DefaultsKey.scrobbleDuringSesh) private var duringSesh = true
    @AppStorage(DefaultsKey.scrobbleManualOnly) private var manualOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Now Playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            // --- Sources ---
            VStack(spacing: 0) {
                toggleRow("Apple Music", subtitle: "Share what's playing in Apple Music",
                          symbol: "applelogo", isOn: $appleOn) { restart() }
                rowDivider
                HStack {
                    toggleRow("Spotify", subtitle: spotify.isConnected ? "Connected" : "Share your Spotify track",
                              symbol: "music.note", isOn: $spotifyOn) {
                        if spotifyOn && !spotify.isConnected { spotify.connect() }
                        restart()
                    }
                }
                if spotifyOn {
                    rowDivider
                    HStack {
                        Text(spotify.isConnected ? "Spotify account linked" : "Link your Spotify account")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Button(spotify.isConnected ? "Unlink" : "Connect") {
                            spotify.isConnected ? spotify.disconnect() : spotify.connect()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.greenBright)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if let err = spotify.lastError {
                        Text(err).font(.system(size: 12)).foregroundStyle(Palette.moodAngry)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))

            // --- When to share ---
            if appleOn || spotifyOn {
                Text("When to share")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                VStack(spacing: 0) {
                    toggleRow("Always while playing", subtitle: "Share any time music is playing",
                              symbol: "infinity", isOn: $always) { syncModes(changed: .always) }
                    rowDivider
                    toggleRow("Only during a sesh", subtitle: "Share only while you're in a sesh",
                              symbol: "flame", isOn: $duringSesh) { syncModes(changed: .duringSesh) }
                    rowDivider
                    toggleRow("Manual only", subtitle: "Never auto-share; you tap to share",
                              symbol: "hand.tap", isOn: $manualOnly) { syncModes(changed: .manual) }
                }
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
            // --- Listen (music hub: vibes + playlists) ---
            NavigationLink {
                ListenView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list").font(.system(size: 16)).frame(width: 22)
                        .foregroundStyle(Palette.greenBright)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Listen").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                        Text("Vibes and playlists — export to Spotify or Apple Music")
                            .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private enum Mode { case always, duringSesh, manual }
    /// Keep the three when-to-share toggles sensible: manual is exclusive; always
    /// and duringSesh can't both be the sole truth in a contradictory way.
    private func syncModes(changed: Mode) {
        switch changed {
        case .manual:
            if manualOnly { always = false; duringSesh = false }
        case .always:
            if always { manualOnly = false }
        case .duringSesh:
            if duringSesh { manualOnly = false }
        }
        restart()
    }

    private func restart() {
        Haptics.selection()
        scrobbler.start()
    }

    @ViewBuilder private var rowDivider: some View {
        Rectangle().fill(Palette.stroke.opacity(0.5)).frame(height: 1).padding(.leading, 48)
    }

    private func toggleRow(_ title: String, subtitle: String, symbol: String,
                           isOn: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16)).frame(width: 22)
                    .foregroundStyle(Palette.greenBright)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .tint(Palette.greenBright)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .onChange(of: isOn.wrappedValue) { _, _ in onChange() }
    }
}
