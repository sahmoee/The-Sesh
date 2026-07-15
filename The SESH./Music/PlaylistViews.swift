//
//  PlaylistViews.swift
//  The SESH
//
//  The playlist builder UI: a list of the user's playlists, a detail screen with
//  the tracks plus add/export, and a search sheet for manually adding songs from
//  Spotify or Apple Music.
//

import SwiftUI

// MARK: - Playlists list

struct PlaylistsView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var newName = ""
    @State private var newAuto = true

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Playlists", onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 12) {
                    Button { showNew = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 18))
                            Text("New playlist").font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Palette.greenBright)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if store.playlists.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.playlists) { pl in
                            NavigationLink {
                                PlaylistDetailView(playlistID: pl.id)
                            } label: {
                                PlaylistRow(playlist: pl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showNew) { newPlaylistSheet }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(Palette.textTertiary)
            Text("No playlists yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            Text("Create one and it can collect the songs you play, or add tracks by hand.")
                .font(.system(size: 13)).foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
        }
        .padding(.top, 40).padding(.horizontal, 20)
    }

    private var newPlaylistSheet: some View {
        VStack(spacing: 18) {
            Text("New Playlist").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text).padding(.top, 20)
            TextField("Playlist name", text: $newName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
                .padding(.horizontal, 18)
            Toggle(isOn: $newAuto) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-collect now playing").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                    Text("Add each song you play to this playlist").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
            }
            .tint(Palette.greenBright).padding(.horizontal, 18)
            Spacer()
            PrimaryButton(title: "Create", icon: "plus") {
                _ = store.createPlaylist(name: newName, autoCollect: newAuto)
                newName = ""; newAuto = true; showNew = false
                Haptics.success()
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .background(AppBackground())
        .presentationDetents([.medium])
    }
}

struct PlaylistRow: View {
    let playlist: SeshPlaylist
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.field).frame(width: 48, height: 48)
                Image(systemName: playlist.autoCollect ? "dot.radiowaves.left.and.right" : "music.note.list")
                    .font(.system(size: 18)).foregroundStyle(Palette.greenBright)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(playlist.subtitle + (playlist.autoCollect ? " · collecting" : ""))
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Playlist detail

struct PlaylistDetailView: View {
    let playlistID: String
    @Environment(PlaylistStore.self) private var store
    @Environment(SpotifyAuth.self) private var spotify
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false
    @State private var statusMessage: String?
    @State private var working = false
    /// Optional subtitle, e.g. "Based on your Blue Dream sessions".
    var subtitle: String? = nil

    private var playlist: SeshPlaylist? { store.playlist(playlistID) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let pl = playlist {
                ScrollView {
                    VStack(spacing: 18) {
                        cover(pl)
                        titleBlock(pl)
                        playButtons(pl)
                        trackList(pl)
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showSearch) { TrackSearchView(playlistID: playlistID) }
        .alert("Playlist", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
            Button("OK") { statusMessage = nil }
        } message: { Text(statusMessage ?? "") }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { showSearch = true } label: { Label("Add songs", systemImage: "plus") }
                if let pl = playlist {
                    Button(role: .destructive) { store.delete(pl.id); dismiss() } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private func cover(_ pl: SeshPlaylist) -> some View {
        ZStack {
            // Use the first track's artwork as the cover, else a gradient.
            if let art = pl.tracks.first?.artworkURL, let url = URL(string: art) {
                AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { coverGradient }
            } else {
                coverGradient
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            Text(pl.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .padding(12)
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.greenBright.opacity(0.5), lineWidth: 1))
    }
    private var coverGradient: some View {
        LinearGradient(colors: [Palette.greenDeep, Palette.purple.opacity(0.8), Palette.bgBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func titleBlock(_ pl: SeshPlaylist) -> some View {
        VStack(spacing: 6) {
            Text(pl.name).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.text)
            if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.textSecondary) }
            Text("\(pl.tracks.count) \(pl.tracks.count == 1 ? "song" : "songs") · \(estimatedMinutes(pl)) min")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        }
    }

    private func playButtons(_ pl: SeshPlaylist) -> some View {
        VStack(spacing: 12) {
            Button { playOn(.spotify, pl) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.tv.fill").font(.system(size: 16))
                    Text("Play on Spotify").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Palette.onGreen)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
            }
            Button { playOn(.appleMusic, pl) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note").font(.system(size: 16))
                    Text("Play on Apple Music").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
            if working { ProgressView().padding(.top, 2) }
        }
        .buttonStyle(.plain)
        .disabled(working || pl.tracks.isEmpty)
    }

    private func trackList(_ pl: SeshPlaylist) -> some View {
        VStack(spacing: 0) {
            if pl.tracks.isEmpty {
                Text("No songs yet. Add some with the menu above.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(pl.tracks) { t in
                HStack(spacing: 12) {
                    trackArt(t)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(t.artist).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button(role: .destructive) { store.removeTrack(t.id, from: pl.id) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Palette.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private func trackArt(_ t: PlaylistTrack) -> some View {
        if let s = t.artworkURL, let url = URL(string: s) {
            AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { trackPh }
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
        } else { trackPh.frame(width: 52, height: 52) }
    }
    private var trackPh: some View {
        ZStack { RoundedRectangle(cornerRadius: 8).fill(Palette.field)
            Image(systemName: "music.note").foregroundStyle(Palette.textTertiary) }
    }

    // Export to the target, then open that app.
    private func playOn(_ target: ExportTarget, _ pl: SeshPlaylist) {
        if target == .spotify && !spotify.isConnected { spotify.connect(); return }
        working = true
        Task {
            let result = await store.export(playlistID, to: target)
            working = false
            switch result {
            case .success(_, _, let url):
                if target == .spotify {
                    if let url, let u = URL(string: url) { openURL(u) }
                    else { statusMessage = "Exported to Spotify." }
                } else {
                    // Apple Music creates a library playlist; open the Music app.
                    if let u = URL(string: "music://") { openURL(u) }
                    else { statusMessage = "Added to your Apple Music library." }
                }
                Haptics.success()
            case .failure(let msg):
                statusMessage = msg; Haptics.warning()
            }
        }
    }

    private func estimatedMinutes(_ pl: SeshPlaylist) -> Int {
        // Rough estimate: average song ~3.5 min.
        max(1, Int((Double(pl.tracks.count) * 3.5).rounded()))
    }
}
struct TrackRow: View {
    let track: PlaylistTrack
    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                Text(track.artist).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: track.source == .spotify ? "music.note" : "applelogo")
                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
    }
    @ViewBuilder private var artwork: some View {
        if let s = track.artworkURL, let url = URL(string: s) {
            AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { ph }
                .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 6))
        } else { ph.frame(width: 38, height: 38) }
    }
    private var ph: some View {
        ZStack { RoundedRectangle(cornerRadius: 6).fill(Palette.field)
            Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(Palette.textTertiary) }
    }
}

// MARK: - Track search (manual add)

struct TrackSearchView: View {
    let playlistID: String
    @Environment(PlaylistStore.self) private var store
    @Environment(SpotifyAuth.self) private var spotify
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var source: ExportTarget = .appleMusic
    @State private var results: [PlaylistTrack] = []
    @State private var searching = false
    @State private var added: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Add Songs", onBack: { dismiss() })
            // Source picker
            Picker("Source", selection: $source) {
                Text("Apple Music").tag(ExportTarget.appleMusic)
                Text("Spotify").tag(ExportTarget.spotify)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18).padding(.bottom, 8)
            .onChange(of: source) { _, _ in if !query.isEmpty { runSearch() } }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
                TextField("Search songs", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
            .padding(.horizontal, 18).padding(.bottom, 8)

            if source == .spotify && !spotify.isConnected {
                VStack(spacing: 8) {
                    Text("Connect Spotify to search it.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    Button("Connect Spotify") { spotify.connect() }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
                }.padding(.top, 30)
            } else if searching {
                ProgressView().padding(.top, 30)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results) { t in
                            Button {
                                store.addTrack(t, to: playlistID)
                                added.insert(t.id); Haptics.tap()
                            } label: {
                                HStack {
                                    TrackRow(track: t)
                                    Image(systemName: added.contains(t.id) ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(added.contains(t.id) ? Palette.greenBright : Palette.textSecondary)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(18)
                }
            }
            Spacer()
        }
        .background(AppBackground())
    }

    private func runSearch() {
        searching = true
        Task {
            let r = await store.search(query, on: source)
            results = r
            searching = false
        }
    }
}
