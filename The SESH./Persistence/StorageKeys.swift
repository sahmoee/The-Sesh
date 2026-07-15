//
//  StorageKeys.swift
//  The SESH
//
//  One home for every persistence key. Previously these were scattered as
//  `private let xKey = "ht.x.v1"` across AppSession, which made a typo silently
//  read/write the wrong slot. Centralizing them (#6) gives one place to see the
//  whole persistence surface and removes the duplicate-literal risk.
//
//  Naming convention: legacy app keys use the "ht." prefix (HighThoughts, the
//  original name) and are kept verbatim so existing installs keep their data.
//  Newer keys use "sesh.".
//

import Foundation
import os

/// Codable helpers that LOG failures instead of silently swallowing them (#2).
/// Previously the app used `try? JSONEncoder().encode(...)` / `try? decode(...)`
/// in ~60 places; when a decode failed (e.g. a schema change mid-development)
/// the data quietly vanished with no signal. These wrappers keep the same
/// "return nil on failure" ergonomics but surface the error to the log so it's
/// debuggable.
enum Persist {
    private static let log = Logger(subsystem: "com.sowens.The-sesh-", category: "persistence")

    static func encode<T: Encodable>(_ value: T, label: String) -> Data? {
        do { return try JSONEncoder().encode(value) }
        catch { log.error("Encode failed [\(label, privacy: .public)]: \(String(describing: error), privacy: .public)"); return nil }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, label: String) -> T? {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { log.error("Decode failed [\(label, privacy: .public)]: \(String(describing: error), privacy: .public)"); return nil }
    }
}

/// All UserDefaults / iCloud-KVS keys used by the app.
enum DefaultsKey {
    // Core journal (mirrored to iCloud KVS)
    static let entries   = "ht.entries.v2"
    static let thoughts  = "ht.thoughts.v2"
    static let name      = "ht.name.v2"

    // One-time flags
    static let seeded    = "ht.seeded.v2"
    static let migrated  = "ht.swiftdata.migrated.v1"

    // Stash / purchases
    static let purchases = "ht.purchases.v1"

    // Custom vault categories
    static let customCategories = "ht.customCategories.v1"

    // Resumable live sesh
    static let liveSesh  = "ht.liveSesh.v1"

    // Cyph counters
    static let cyphJoined = "ht.cyph.joined.v1"
    static let cyphHosted = "ht.cyph.hosted.v1"

    // Roll records
    static let fastestJoint = "ht.record.joint.v1"
    static let fastestBlunt = "ht.record.blunt.v1"

    // Tolerance break
    static let tBreakStart = "ht.tbreak.start.v1"
    static let tBreakGoal  = "ht.tbreak.goal.v1"

    // Notifications: persisted inbox + last-seen event ids + enabled flag
    static let notifInbox     = "sesh.notif.inbox.v1"
    static let notifSeenIDs   = "sesh.notif.seenIDs.v1"
    static let notifEnabled   = "sesh.notif.enabled.v1"

    // Strain images: user-attached photos keyed by strain id
    static let strainUserPhotos = "sesh.strain.userPhotos.v1"

    // Scrobbler (now-playing) settings + Spotify auth
    static let scrobbleApple       = "sesh.scrobble.apple.v1"        // Apple Music source on
    static let scrobbleSpotify     = "sesh.scrobble.spotify.v1"      // Spotify source on
    static let scrobbleAlways      = "sesh.scrobble.always.v1"       // broadcast whenever playing
    static let scrobbleDuringSesh  = "sesh.scrobble.duringSesh.v1"   // broadcast only during a sesh
    static let scrobbleManualOnly  = "sesh.scrobble.manualOnly.v1"   // never auto-broadcast
    static let spotifyRefreshToken = "sesh.spotify.refresh.v1"       // Spotify refresh token (Keychain-backed in prod)
    static let spotifyConnected    = "sesh.spotify.connected.v1"     // has the user linked Spotify

    // User-built playlists (persisted locally; exported to Spotify/Apple on demand)
    static let playlists           = "sesh.playlists.v1"
}

/// Shared contract between the app and the widget extension (#10).
///
/// IMPORTANT: this file is a member of BOTH the app target and the SeshWidget
/// target (tick both under Target Membership), exactly like
/// SeshActivityAttributes.swift. That way the App Group suite name and the
/// widget snapshot keys are defined ONCE — if they ever drift between the two
/// targets, the widget silently shows zeros, which is painful to debug.
enum WidgetContract {
    /// App Group suite shared by app + widget. Must match the App Groups
    /// capability added to BOTH targets in Xcode.
    static let appGroup = "group.com.sowens.The-sesh-"

    // Snapshot keys the app writes and the widget reads.
    static let streak      = "widget.streak"
    static let lastStrain  = "widget.lastStrain"
    static let stashCount  = "widget.stashCount"
    static let isLive      = "widget.isLive"
    static let liveStrain  = "widget.liveStrain"
}
