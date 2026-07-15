//
//  PlaylistStore.swift
//  The SESH
//
//  Owns the user's playlists: create / rename / delete, add tracks (manual or
//  auto-collected from now-playing), persistence, search, and export to Spotify
//  and Apple Music.
//
//  EXPORT PATHS:
//   - Apple Music: on-device via MusicKit (MusicLibrary). Tracks are matched in
//     the Apple catalog by ISRC or text search, then added to a new (or existing)
//     library playlist. No Worker needed.
//   - Spotify: via the Worker, which holds the user's token. The app sends the
//     track list; the Worker searches Spotify for each (ISRC first), creates the
//     playlist, and adds the matches. The client never holds the Spotify secret.
//

import Foundation
import Observation

enum ExportTarget: String { case spotify, appleMusic }

enum ExportResult {
    case success(addedCount: Int, total: Int, url: String?)
    case failure(String)
}

@Observable
@MainActor
final class PlaylistStore {
    private(set) var playlists: [SeshPlaylist] = []

    /// Status string surfaced by the UI during/after an export.
    var exportStatus: String?
    var isExporting = false

    weak var spotify: SpotifyAuth?
    private let api = SeshAPI()
    private var identity: SeshIdentity?

    init() { load() }

    func configure(identity: SeshIdentity?) { self.identity = identity }

    // MARK: CRUD

    @discardableResult
    func createPlaylist(name: String, autoCollect: Bool = false) -> SeshPlaylist {
        let pl = SeshPlaylist(name: name.isEmpty ? "New Playlist" : name, autoCollect: autoCollect)
        playlists.insert(pl, at: 0)
        save()
        return pl
    }

    func rename(_ id: String, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[i].name = name
        playlists[i].updatedAt = Date()
        save()
    }

    func delete(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func setAutoCollect(_ id: String, _ on: Bool) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].autoCollect = on
        save()
    }

    func playlist(_ id: String) -> SeshPlaylist? { playlists.first { $0.id == id } }

    // MARK: Tracks

    /// Add a track to a playlist, skipping exact duplicates.
    func addTrack(_ track: PlaylistTrack, to playlistID: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if playlists[i].tracks.contains(where: { $0.isSameSong(as: track) }) { return }
        playlists[i].tracks.append(track)
        playlists[i].updatedAt = Date()
        save()
    }

    func removeTrack(_ trackID: String, from playlistID: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].tracks.removeAll { $0.id == trackID }
        playlists[i].updatedAt = Date()
        save()
    }

    func moveTrack(in playlistID: String, from source: IndexSet, to destination: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        // Foundation-only move (the move(fromOffsets:toOffset:) helper requires
        // SwiftUI; PlaylistStore stays UI-framework-free).
        var tracks = playlists[i].tracks
        let moving = source.sorted().map { tracks[$0] }
        for index in source.sorted(by: >) { tracks.remove(at: index) }
        let insertAt = min(max(0, destination - source.filter { $0 < destination }.count), tracks.count)
        tracks.insert(contentsOf: moving, at: insertAt)
        playlists[i].tracks = tracks
        save()
    }

    /// Called by the scrobbler whenever a new now-playing track is detected; adds
    /// it to every auto-collecting playlist.
    func autoCollect(_ np: NowPlaying) {
        let track = PlaylistTrack(from: np)
        var changed = false
        for idx in playlists.indices where playlists[idx].autoCollect {
            if !playlists[idx].tracks.contains(where: { $0.isSameSong(as: track) }) {
                playlists[idx].tracks.append(track)
                playlists[idx].updatedAt = Date()
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: Search (manual add)

    /// Search Spotify (via Worker) and/or Apple Music for tracks to add.
    func search(_ query: String, on target: ExportTarget) async -> [PlaylistTrack] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        switch target {
        case .spotify:
            return await api.spotifySearch(query: query, identity: identity)
        case .appleMusic:
            return await AppleMusicExporter.search(query)
        }
    }

    // MARK: Export

    func export(_ playlistID: String, to target: ExportTarget) async -> ExportResult {
        guard let pl = playlist(playlistID) else { return .failure("Playlist not found.") }
        guard !pl.tracks.isEmpty else { return .failure("This playlist is empty.") }
        isExporting = true
        defer { isExporting = false }

        switch target {
        case .appleMusic:
            exportStatus = "Adding to Apple Music…"
            let result = await AppleMusicExporter.export(playlist: pl)
            if case .success(_, _, _) = result { exportStatus = "Added to Apple Music." }
            return result

        case .spotify:
            guard let spotify, spotify.isConnected else {
                return .failure("Connect Spotify first.")
            }
            exportStatus = "Creating Spotify playlist…"
            let result = await api.spotifyExportPlaylist(
                name: pl.name,
                tracks: pl.tracks,
                existingID: pl.spotifyPlaylistID,
                identity: identity)
            switch result {
            case .success(_, _, let url):
                exportStatus = "Exported to Spotify."
                // remember the created playlist id for future re-export, if returned
                if let url, let id = Self.spotifyID(from: url),
                   let i = playlists.firstIndex(where: { $0.id == playlistID }) {
                    playlists[i].spotifyPlaylistID = id
                    save()
                }
            case .failure(let msg):
                exportStatus = msg
            }
            return result
        }
    }

    private static func spotifyID(from url: String) -> String? {
        // https://open.spotify.com/playlist/{id}?si=...
        // Split into explicit steps so the type-checker doesn't churn on a long
        // optional-chained expression.
        let parts = url.split(separator: "/")
        guard let last = parts.last else { return nil }
        let beforeQuery = last.split(separator: "?").first
        guard let id = beforeQuery else { return nil }
        return String(id)
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.playlists),
              let saved = try? JSONDecoder().decode([SeshPlaylist].self, from: data) else { return }
        playlists = saved
    }
    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.playlists)
        }
    }
}
