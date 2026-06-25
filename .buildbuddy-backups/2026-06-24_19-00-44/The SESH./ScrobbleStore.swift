//
//  ScrobbleStore.swift
//  The SESH
//
//  Reads the user's currently-playing track from Apple Music (on-device, via
//  MediaPlayer) and/or Spotify (via the Spotify Web API, proxied through our
//  Worker so the client secret never ships in the app). Produces a single
//  `current` NowPlaying which SocialStore broadcasts to friends according to the
//  user's ScrobbleSettings.
//
//  APPLE MUSIC: MPMusicPlayerController.systemMusicPlayer exposes the track only
//  when playback is through Apple's own player. No OAuth, no network. We observe
//  the now-playing-item-changed notification.
//
//  SPOTIFY: each user links their account once (OAuth, see SpotifyAuth). We then
//  poll GET /api/spotify/now-playing on the Worker, which uses the user's stored
//  refresh token to call Spotify and returns a normalized track. Polling cadence
//  is gentle to respect rate limits and battery.
//

import Foundation
import Observation
import MediaPlayer

@Observable
@MainActor
final class ScrobbleStore {
    /// The track we currently consider "now playing" (from whichever enabled
    /// source most recently reported one). nil = nothing playing / not shared.
    private(set) var current: NowPlaying?

    /// Live settings (re-read when Settings change).
    var settings = ScrobbleSettings.load()

    /// Set by the app so we can post through the social layer.
    weak var social: SocialStore?

    /// Set by the app so new now-playing tracks feed auto-collecting playlists.
    weak var playlists: PlaylistStore?

    private let api = SeshAPI()
    private var identity: SeshIdentity?
    private var spotifyPoll: Task<Void, Never>?
    private var appleObserver: NSObjectProtocol?
    private let player = MPMusicPlayerController.systemMusicPlayer

    // MARK: Lifecycle

    func configure(identity: SeshIdentity?) {
        self.identity = identity
    }

    /// Start whichever sources are enabled. Safe to call repeatedly (e.g. after
    /// the user changes Settings).
    func start() {
        settings = ScrobbleSettings.load()
        stop()  // clear existing observers/tasks before re-arming

        if settings.appleEnabled { startAppleMusic() }
        if settings.spotifyEnabled { startSpotifyPolling() }
        // If nothing is enabled, clear any stale broadcast.
        if !settings.anySourceEnabled {
            clearNowPlaying()
        }
    }

    func stop() {
        if let obs = appleObserver {
            NotificationCenter.default.removeObserver(obs)
            player.endGeneratingPlaybackNotifications()
            appleObserver = nil
        }
        spotifyPoll?.cancel()
        spotifyPoll = nil
    }

    // MARK: Apple Music

    private func startAppleMusic() {
        player.beginGeneratingPlaybackNotifications()
        appleObserver = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.readAppleNowPlaying() }
        }
        // Authorization for the music library is requested lazily; reading the
        // system player's nowPlayingItem itself does not require library auth on
        // recent iOS, but metadata is richer with it.
        readAppleNowPlaying()
    }

    private func readAppleNowPlaying() {
        guard settings.appleEnabled else { return }
        guard player.playbackState == .playing, let item = player.nowPlayingItem else {
            // Apple isn't actively playing; don't clobber a Spotify track.
            if current?.source == .appleMusic { maybeClearIfStale() }
            return
        }
        let np = NowPlaying(
            title: item.title ?? "Unknown",
            artist: item.artist ?? "Unknown artist",
            album: item.albumTitle,
            artworkURL: nil,    // Apple artwork is a local MPMediaItemArtwork; UI loads it separately
            source: .appleMusic,
            isPlaying: true,
            updatedAt: Date())
        update(np)
    }

    /// Apple artwork is local-only; the UI can fetch it on demand for the
    /// currently playing item.
    func appleArtwork(size: CGSize) -> UIImage? {
        guard current?.source == .appleMusic,
              let art = player.nowPlayingItem?.artwork else { return nil }
        return art.image(at: size)
    }

    // MARK: Spotify

    private func startSpotifyPolling(every seconds: UInt64 = 20) {
        spotifyPoll?.cancel()
        spotifyPoll = Task { [weak self] in
            while !Task.isCancelled {
                // Re-acquire self each iteration; if it's gone, stop. Binding to a
                // fresh local avoids the Swift 6 captured-var-across-await warning.
                guard let store = self else { return }
                await store.pollSpotifyOnce()
                try? await Task.sleep(for: .seconds(Double(seconds)))
            }
        }
    }

    private func pollSpotifyOnce() async {
        guard settings.spotifyEnabled else { return }
        guard let track = await api.spotifyNowPlaying(identity: identity) else {
            if current?.source == .spotify { maybeClearIfStale() }
            return
        }
        update(track)
    }

    // MARK: Update + broadcast

    private func update(_ np: NowPlaying) {
        // If both sources report, prefer the most recent.
        if let cur = current, cur.source != np.source, cur.updatedAt > np.updatedAt {
            return
        }
        let isNewSong = current?.title != np.title || current?.artist != np.artist
        current = np
        broadcastIfAllowed(np)
        // Feed auto-collecting playlists, but only on an actual song change.
        if isNewSong { playlists?.autoCollect(np) }
    }

    /// Broadcast the track to friends according to the user's settings.
    private func broadcastIfAllowed(_ np: NowPlaying) {
        guard let social else { return }
        if settings.broadcastManualOnly { return }            // never auto-post
        if settings.broadcastDuringSesh && !settings.broadcastAlways {
            guard social.me.activity.isActive else { return }  // only while sesh active
        }
        // broadcastAlways (or duringSesh with an active sesh) -> post.
        social.setNowPlaying(np)
    }

    /// User-initiated share (for manual mode, or a "share this track" button).
    func shareCurrentManually() {
        guard let np = current, let social else { return }
        social.setNowPlaying(np)
    }

    private func clearNowPlaying() {
        current = nil
        social?.clearNowPlaying()
    }

    private func maybeClearIfStale() {
        guard let cur = current else { return }
        if !cur.isCurrent() {
            current = nil
            social?.clearNowPlaying()
        }
    }
}
