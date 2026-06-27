//
//  MusicMemory.swift
//  The SESH
//
//  The data backbone for Music's three layers:
//   - Action (Home): when a sesh starts, the currently-playing song is captured
//     and saved with the strain (a StrainSongPlay).
//   - Memory (Track): song history, and playlists/stations built from what you
//     played during sessions.
//   - Identity (Me): your taste profile — which songs pair with which strains,
//     and which vibes (energize vs. calm) you reach for.
//
//  This file defines the record and the read-side helpers (aggregations). The
//  storage lives on AppSession; the capture point is the sesh-start flow.
//

import SwiftUI

/// One song captured during a sesh, tied to the strain being smoked.
struct StrainSongPlay: Identifiable, Codable, Hashable {
    var id = UUID()
    var strainName: String
    var title: String
    var artist: String
    var album: String?
    var artworkURL: String?
    var sourceRaw: String          // MusicSource.rawValue
    var sessionTypeRaw: String     // the vibe/mood at capture (SessionType.rawValue)
    var date = Date()

    var source: MusicSource { MusicSource(rawValue: sourceRaw) ?? .appleMusic }
    var sessionType: SessionType { SessionType(rawValue: sessionTypeRaw) ?? .relaxing }

    /// "Title — Artist"
    var line: String { "\(title) — \(artist)" }
}

// MARK: - Aggregations (read side for Track + Me)

/// A song grouped with how often it's been played, for history/top lists.
struct SongTally: Identifiable {
    var id: String { "\(title)|\(artist)" }
    let title: String
    let artist: String
    let artworkURL: String?
    let count: Int
    let lastPlayed: Date
}

/// A strain paired with the songs most played while smoking it.
struct StrainMusicPairing: Identifiable {
    var id: String { strainName }
    let strainName: String
    let topSongs: [SongTally]
    let playCount: Int
}

enum MusicMemory {
    /// Most-played songs across all sessions, newest-weighted by recency tie-break.
    static func topSongs(_ plays: [StrainSongPlay], limit: Int = 25) -> [SongTally] {
        let grouped = Dictionary(grouping: plays) { "\($0.title)|\($0.artist)" }
        let tallies = grouped.values.compactMap { group -> SongTally? in
            guard let first = group.first else { return nil }
            let last = group.map(\.date).max() ?? first.date
            return SongTally(title: first.title, artist: first.artist,
                             artworkURL: first.artworkURL, count: group.count, lastPlayed: last)
        }
        return tallies.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.lastPlayed > $1.lastPlayed
        }.prefix(limit).map { $0 }
    }

    /// Full play history, newest first.
    static func history(_ plays: [StrainSongPlay]) -> [StrainSongPlay] {
        plays.sorted { $0.date > $1.date }
    }

    /// Songs most played while smoking a given strain.
    static func songs(for strain: String, in plays: [StrainSongPlay], limit: Int = 10) -> [SongTally] {
        topSongs(plays.filter { $0.strainName.caseInsensitiveCompare(strain) == .orderedSame }, limit: limit)
    }

    /// Strain -> top songs pairings, for the identity view, sorted by play volume.
    static func pairings(_ plays: [StrainSongPlay], limit: Int = 20) -> [StrainMusicPairing] {
        let byStrain = Dictionary(grouping: plays) { $0.strainName }
        return byStrain.map { name, group in
            StrainMusicPairing(strainName: name,
                               topSongs: topSongs(group, limit: 3),
                               playCount: group.count)
        }
        .sorted { $0.playCount > $1.playCount }
        .prefix(limit).map { $0 }
    }

    /// Group play counts by the vibe (SessionType) they were captured in, so the
    /// identity view can say what music pairs with energizing vs. calming seshes.
    static func vibeBreakdown(_ plays: [StrainSongPlay]) -> [(vibe: SessionType, count: Int)] {
        let byVibe = Dictionary(grouping: plays) { $0.sessionType }
        return byVibe.map { (vibe: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}
