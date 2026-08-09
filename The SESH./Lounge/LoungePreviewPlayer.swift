//
//  LoungePreviewPlayer.swift
//  The SESH
//
//  (SESH-RL-001-R2 §Table 3) The Lounge's music preview engine.
//
//  "Must remain a functional player, not decorative": this wraps a single
//  AVPlayer behind an @Observable singleton so every Pass-the-Aux card — feed
//  and detail — shares one source of truth. Starting one preview stops any
//  other, progress is driven by a real periodic time observer (never a faked
//  fraction), and the audio session is .ambient so the silent switch is
//  respected and the user's own music is never barged over (§9: playback is
//  always an explicit act, never a surprise).
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class LoungePreviewPlayer {

    static let shared = LoungePreviewPlayer()

    /// Post whose track is currently loaded (playing or paused).
    private(set) var activePostID: String?
    private(set) var isPlaying = false
    /// Real playback progress 0...1 from the periodic time observer.
    private(set) var fraction: Double = 0
    /// Elapsed seconds of the active preview.
    private(set) var elapsed: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    private init() {}

    // MARK: State queries

    func isActive(_ postID: String) -> Bool { activePostID == postID }

    func isPlaying(_ postID: String) -> Bool { activePostID == postID && isPlaying }

    /// A card only ever shows its own progress; everyone else reads zero.
    func progress(for postID: String) -> Double { activePostID == postID ? fraction : 0 }

    // MARK: Transport

    /// One tap on a card's transport: toggles its own preview, or takes over
    /// the aux from whichever card was playing before.
    func toggle(postID: String, track: LoungeTrack) {
        if activePostID == postID {
            if isPlaying { pause() } else { resume() }
            return
        }
        play(postID: postID, track: track)
    }

    func play(postID: String, track: LoungeTrack) {
        guard let raw = track.previewURL, let url = URL(string: raw) else { return }
        stop()   // only one preview at a time

        // .ambient honors the silent switch and mixes with the user's own
        // audio instead of ducking or interrupting it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let fresh = AVPlayer(playerItem: item)
        player = fresh
        activePostID = postID
        fraction = 0
        elapsed = 0
        isPlaying = true

        // Real progress: a periodic observer on the main queue drives the bar.
        timeObserver = fresh.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }

        fresh.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard player != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
    }

    /// Tear down the preview for one post (its card scrolled away), or — with
    /// no argument — whatever is playing (feed backgrounded / screen left).
    func stop(postID: String? = nil) {
        if let postID, postID != activePostID { return }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        activePostID = nil
        isPlaying = false
        fraction = 0
        elapsed = 0
    }

    // MARK: Internals

    private func tick(_ time: CMTime) {
        guard let item = player?.currentItem else { return }
        let seconds = time.seconds
        elapsed = seconds.isFinite ? max(0, seconds) : 0
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 {
            fraction = min(1, max(0, elapsed / duration))
        }
    }

    /// Preview ran out: show a full bar, rewind, and wait for another tap.
    private func finished() {
        fraction = 1
        isPlaying = false
        elapsed = 0
        player?.seek(to: .zero)
    }
}
