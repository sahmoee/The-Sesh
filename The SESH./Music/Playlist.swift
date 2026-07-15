//
//  Playlist.swift
//  The SESH
//
//  User-built playlists. A SeshPlaylist is a named, ordered collection of tracks
//  the user assembles in the app — auto-collected from now-playing (Apple Music
//  or Spotify) and/or added manually via search — then exported to Spotify and/or
//  Apple Music.
//
//  Tracks are stored in a source-neutral form (title/artist/album plus optional
//  per-service identifiers) so the same playlist can export to either service:
//  an Apple track exports directly to Apple Music and is matched by search on
//  Spotify, and vice-versa. ISRC, when known, makes cross-service matching exact.
//

import Foundation

/// A single track in a user playlist, normalized across services.
struct PlaylistTrack: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var artist: String
    var album: String?
    var artworkURL: String?
    /// The service this track was captured from.
    var source: MusicSource
    /// International Standard Recording Code, if known — enables exact matching
    /// across services.
    var isrc: String?
    /// Spotify track URI (e.g. "spotify:track:...") if known.
    var spotifyURI: String?
    /// Apple Music catalog ID (the "store" persistent ID as a string) if known.
    var appleID: String?
    var addedAt: Date = Date()

    var line: String { "\(title) — \(artist)" }

    /// Build a track from a NowPlaying snapshot (auto-collect path).
    init(from np: NowPlaying) {
        self.title = np.title
        self.artist = np.artist
        self.album = np.album
        self.artworkURL = np.artworkURL
        self.source = np.source
    }

    /// Direct initializer (manual add / search results).
    init(title: String, artist: String, album: String? = nil, artworkURL: String? = nil,
         source: MusicSource, isrc: String? = nil, spotifyURI: String? = nil, appleID: String? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.artworkURL = artworkURL; self.source = source
        self.isrc = isrc; self.spotifyURI = spotifyURI; self.appleID = appleID
    }

    /// Two tracks are "the same song" for de-dup purposes when ISRC matches, or
    /// failing that when title+artist match case-insensitively.
    func isSameSong(as other: PlaylistTrack) -> Bool {
        if let a = isrc, let b = other.isrc, !a.isEmpty, !b.isEmpty { return a == b }
        return title.lowercased() == other.title.lowercased()
            && artist.lowercased() == other.artist.lowercased()
    }
}

/// A named, ordered, user-built playlist.
struct SeshPlaylist: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var tracks: [PlaylistTrack] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// True if this playlist auto-collects now-playing songs.
    var autoCollect: Bool = false
    /// Remembered export ids so re-export updates rather than duplicates.
    var spotifyPlaylistID: String?
    var applePlaylistID: String?

    var trackCount: Int { tracks.count }
    var subtitle: String {
        let n = tracks.count
        return n == 0 ? "Empty" : (n == 1 ? "1 song" : "\(n) songs")
    }
}
