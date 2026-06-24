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
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false
    @State private var showExportSheet = false
    @State private var exportMessage: String?

    private var playlist: SeshPlaylist? { store.playlist(playlistID) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: playlist?.name ?? "Playlist", onBack: { dismiss() })
            if let pl = playlist {
                List {
                    Section {
                        Toggle(isOn: Binding(
                            get: { pl.autoCollect },
                            set: { store.setAutoCollect(pl.id, $0) })) {
                            Label("Auto-collect now playing", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 14))
                        }
                        .tint(Palette.greenBright)
                        .listRowBackground(Palette.card)
                    }
                    Section("Songs") {
                        if pl.tracks.isEmpty {
                            Text("No songs yet. Add some, or turn on auto-collect.")
                                .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                                .listRowBackground(Palette.card)
                        }
                        ForEach(pl.tracks) { t in
                            TrackRow(track: t)
                                .listRowBackground(Palette.card)
                        }
                        .onDelete { idx in
                            for i in idx { store.removeTrack(pl.tracks[i].id, from: pl.id) }
                        }
                        .onMove { from, to in store.moveTrack(in: pl.id, from: from, to: to) }
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))

                // Action bar
                HStack(spacing: 10) {
                    Button { showSearch = true } label: {
                        Label("Add songs", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                            .foregroundStyle(Palette.text)
                    }
                    Button { showExportSheet = true } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.greenBright))
                            .foregroundStyle(Palette.onGreen)
                    }
                    .disabled(pl.tracks.isEmpty)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showSearch) { TrackSearchView(playlistID: playlistID) }
        .confirmationDialog("Export playlist", isPresented: $showExportSheet, titleVisibility: .visible) {
            Button("Export to Apple Music") { runExport(.appleMusic) }
            Button(spotify.isConnected ? "Export to Spotify" : "Connect Spotify to export") {
                spotify.isConnected ? runExport(.spotify) : spotify.connect()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private func runExport(_ target: ExportTarget) {
        Task {
            let result = await store.export(playlistID, to: target)
            switch result {
            case .success(let added, let total, _):
                exportMessage = added == total
                    ? "Added all \(total) songs."
                    : "Added \(added) of \(total) songs (some weren't found)."
                Haptics.success()
            case .failure(let msg):
                exportMessage = msg
                Haptics.warning()
            }
        }
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
