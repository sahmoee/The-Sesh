//
//  Scrobble.swift
//  The SESH
//
//  "Now playing" support — a Last.fm-style scrobbler. A NowPlaying value is a
//  lightweight snapshot of the track a user is currently listening to, from
//  either Apple Music (read on-device via MediaPlayer) or Spotify (via the
//  Spotify Web API through our Worker). It travels with presence: the client
//  posts its own now-playing, and friends' now-playing arrives in the snapshot,
//  so it shows in the feed and on profiles using the existing polling system.
//

import Foundation

/// Where a now-playing track was read from.
enum MusicSource: String, Codable, Hashable {
    case appleMusic = "apple"
    case spotify    = "spotify"

    var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify:    return "Spotify"
        }
    }
    /// SF Symbol used as a small source badge.
    var symbol: String {
        switch self {
        case .appleMusic: return "music.note"
        case .spotify:    return "music.note"
        }
    }
}

/// A snapshot of one currently-playing (or last-played) track.
struct NowPlaying: Codable, Hashable, Identifiable {
    var id: String { "\(source.rawValue):\(artist)-\(title)" }
    var title: String
    var artist: String
    var album: String?
    var artworkURL: String?     // remote art (Spotify) or nil (Apple art is local)
    var source: MusicSource
    var isPlaying: Bool         // true = playing now, false = recently played/paused
    var updatedAt: Date

    /// "Title — Artist"
    var line: String { "\(title) — \(artist)" }

    /// Consider a track "live" only if it was updated recently and is playing.
    func isCurrent(within seconds: TimeInterval = 360) -> Bool {
        isPlaying && Date().timeIntervalSince(updatedAt) < seconds
    }
}

/// User preference for which sources may broadcast, and when. Backed by
/// @AppStorage via the DefaultsKey entries; this struct is just a convenience
/// for reading them together.
struct ScrobbleSettings {
    var appleEnabled: Bool
    var spotifyEnabled: Bool
    /// When to broadcast: any of these may be true.
    var broadcastAlways: Bool      // post whenever music is playing
    var broadcastDuringSesh: Bool  // post only while a sesh is active
    var broadcastManualOnly: Bool  // never auto-post; user toggles per session

    static func load() -> ScrobbleSettings {
        let d = UserDefaults.standard
        func b(_ k: String, _ dflt: Bool) -> Bool {
            d.object(forKey: k) == nil ? dflt : d.bool(forKey: k)
        }
        return ScrobbleSettings(
            appleEnabled:       b(DefaultsKey.scrobbleApple, false),
            spotifyEnabled:     b(DefaultsKey.scrobbleSpotify, false),
            broadcastAlways:    b(DefaultsKey.scrobbleAlways, false),
            broadcastDuringSesh:b(DefaultsKey.scrobbleDuringSesh, true),
            broadcastManualOnly:b(DefaultsKey.scrobbleManualOnly, false))
    }

    /// Any source enabled at all?
    var anySourceEnabled: Bool { appleEnabled || spotifyEnabled }
}

/// Spotify Developer app configuration. Fill these in from your Spotify
/// dashboard (see the setup guide). The client ID is NOT a secret. The client
/// SECRET must NOT live in the app — it stays on the Worker.
enum SpotifyConfig {
    /// From your Spotify app's dashboard ("Client ID").
    static let clientID = ""   // e.g. "3a9b...". Leave empty to disable Spotify until set.

    /// A custom URL scheme you register in the Spotify dashboard AND in the app's
    /// Info.plist URL Types. Must match exactly in all three places.
    static let redirectURI = "thesesh://spotify-callback"
}
