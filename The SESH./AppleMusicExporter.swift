//
//  AppleMusicExporter.swift
//  The SESH
//
//  Apple Music side of search + playlist export, via MusicKit. Searches the
//  Apple Music catalog for tracks and creates a library playlist with them.
//
//  Requires the MusicKit capability and NSAppleMusicUsageDescription, plus the
//  user authorizing access. Catalog search needs an Apple Music subscription on
//  the device for full results; library playlist creation needs library access.
//

import Foundation
import MusicKit

enum AppleMusicExporter {

    /// Ensure we're authorized for Apple Music; returns true if usable.
    static func authorize() async -> Bool {
        switch MusicAuthorization.currentStatus {
        case .authorized: return true
        case .notDetermined:
            return await MusicAuthorization.request() == .authorized
        default:
            return false
        }
    }

    /// Search the Apple Music catalog for tracks matching a query.
    static func search(_ query: String) async -> [PlaylistTrack] {
        guard await authorize() else { return [] }
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 20
            let response = try await request.response()
            return response.songs.map { song in
                PlaylistTrack(
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle,
                    artworkURL: song.artwork?.url(width: 200, height: 200)?.absoluteString,
                    source: .appleMusic,
                    isrc: song.isrc,
                    appleID: song.id.rawValue)
            }
        } catch {
            return []
        }
    }

    /// Create a new Apple Music library playlist from the given SeshPlaylist,
    /// matching each track in the catalog (by ISRC when available, else by text).
    static func export(playlist: SeshPlaylist) async -> ExportResult {
        guard await authorize() else {
            return .failure("Allow Apple Music access to export.")
        }
        // Resolve each track to an Apple Music Song.
        var songs: [Song] = []
        for track in playlist.tracks {
            if let song = await resolve(track) { songs.append(song) }
        }
        guard !songs.isEmpty else {
            return .failure("Couldn't find any of these songs on Apple Music.")
        }
        do {
            // Create the library playlist with the resolved songs.
            let created = try await MusicLibrary.shared.createPlaylist(
                name: playlist.name,
                description: "Made in The Sesh",
                items: songs)
            _ = created
            return .success(addedCount: songs.count, total: playlist.tracks.count, url: nil)
        } catch {
            return .failure("Couldn't create the Apple Music playlist.")
        }
    }

    /// Resolve one normalized track to an Apple Music Song. Prefers an exact
    /// ISRC match via search filtering; falls back to a title+artist search.
    private static func resolve(_ track: PlaylistTrack) async -> Song? {
        // Try an ISRC-qualified search first when we have one.
        if let isrc = track.isrc, !isrc.isEmpty {
            if let song = await firstSong(term: track.title + " " + track.artist, isrc: isrc) {
                return song
            }
        }
        // Title + artist search fallback.
        return await firstSong(term: track.title + " " + track.artist, isrc: nil)
    }

    /// Run a catalog search and return the best match. If `isrc` is given, prefer
    /// a result whose ISRC matches exactly; otherwise return the top hit.
    private static func firstSong(term: String, isrc: String?) async -> Song? {
        do {
            var req = MusicCatalogSearchRequest(term: term, types: [Song.self])
            req.limit = 5
            let songs = try await req.response().songs
            if let isrc, let exact = songs.first(where: { $0.isrc == isrc }) {
                return exact
            }
            return songs.first
        } catch {
            return nil
        }
    }
}
