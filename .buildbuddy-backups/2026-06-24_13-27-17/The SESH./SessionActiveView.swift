//
//  SessionActiveView.swift
//  The SESH
//
//  The redesigned "Session Active" screen (matching the new mockup): a focused,
//  visual view of the live sesh — strain name, a circular elapsed-time ring over
//  the strain image, mood chips, a Now Playing card with Add / Change Song, and
//  End Session. It reflects and controls the real live-sesh state in AppSession,
//  and reuses the scrobbler's now-playing.
//
//  This is a presentation layer over the existing session model; it doesn't
//  replace the step-by-step flow logic in StartSeshView — it's the at-a-glance
//  "session is happening" surface.
//

import SwiftUI
import Combine

struct SessionActiveView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(ScrobbleStore.self) private var scrobbler
    @Environment(\.dismiss) private var dismiss

    /// Called when the user ends the session (parent handles save flow).
    var onEnd: () -> Void = {}

    @State private var now = Date()
    @State private var showSongSearch = false
    @State private var selectedType: SessionType?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: LiveSeshState? { session.liveSesh }

    var body: some View {
        ZStack {
            AppBackground()
            if let live {
                content(live)
            } else {
                noSessionState
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear { selectedType = live?.sessionType }
        .sheet(isPresented: $showSongSearch) { songSearchSheet }
    }

    // MARK: Content

    private func content(_ live: LiveSeshState) -> some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 22) {
                    statusLabel
                    strainTitle(live)
                    timerRing(live)
                    feelingPicker
                    nowPlayingSection
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            endButton
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Menu {
                Button("End Session", role: .destructive) { endSession() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.greenBright).frame(width: 7, height: 7)
            Text("SESSION ACTIVE")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.greenBright)
        }
    }

    private func strainTitle(_ live: LiveSeshState) -> some View {
        VStack(spacing: 4) {
            Text(live.strainName.isEmpty ? "Your Sesh" : live.strainName)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            if let strain = matchedStrain(live) {
                Text(strain.type.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.greenBright)
            }
        }
    }

    // MARK: Timer ring over strain image

    private func timerRing(_ live: LiveSeshState) -> some View {
        let elapsed = now.timeIntervalSince(live.startedAt)
        // The ring sweeps once per 10 minutes as a gentle progress motif.
        let progress = (elapsed.truncatingRemainder(dividingBy: 600)) / 600
        return ZStack {
            Circle()
                .stroke(Palette.stroke.opacity(0.5), lineWidth: 6)
                .frame(width: 240, height: 240)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.greenBright, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 240, height: 240)
                .animation(.linear(duration: 1), value: progress)
            strainImageCircle(live)
            VStack(spacing: 2) {
                Spacer()
                Text(timeString(elapsed))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .padding(.bottom, 18)
            }
            .frame(width: 220, height: 220)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func strainImageCircle(_ live: LiveSeshState) -> some View {
        // Use the matched strain's user photo if present; otherwise a gradient.
        let photoName = matchedStrain(live)?.photoName
        let art = StrainImageStore.load(photoName)
        ZStack {
            if let art {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Palette.green.opacity(0.5), Palette.greenDeep],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "leaf.fill").font(.system(size: 48)).foregroundStyle(Palette.greenBright.opacity(0.6))
            }
        }
        .frame(width: 218, height: 218)
        .clipShape(Circle())
    }

    // MARK: Feeling / session-type chips

    private var feelingPicker: some View {
        VStack(spacing: 10) {
            Text("How are you feeling?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(featuredTypes) { type in
                        let isOn = selectedType == type
                        Button {
                            selectedType = type
                            updateSessionType(type)
                            Haptics.selection()
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(isOn ? Palette.onGreen : Palette.text)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(
                                    Capsule().fill(isOn ? Palette.greenBright : Palette.card)
                                )
                                .overlay(Capsule().stroke(Palette.stroke, lineWidth: isOn ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    /// A short, friendly subset of session types for the chip row.
    private var featuredTypes: [SessionType] {
        [.relaxing, .creative, .funny, .productive, .social, .sleep]
    }

    // MARK: Now Playing

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Now Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Image(systemName: "music.note")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.greenBright)
            }
            // Reuse the scrobbler's card when a track is playing; otherwise a
            // prompt to add one.
            if scrobbler.current?.isCurrent() == true {
                NowPlayingCard()
            } else {
                emptyNowPlaying
            }
            Button { showSongSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                    Text("Add / Change Song").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyNowPlaying: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.field).frame(width: 46, height: 46)
                Image(systemName: "music.note").foregroundStyle(Palette.textTertiary)
            }
            Text("Nothing playing yet")
                .font(.system(size: 14))
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    // MARK: End

    private var endButton: some View {
        Button { endSession() } label: {
            Text("End Session")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.moodAngry)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Palette.moodAngry.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var noSessionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
            Text("No active session").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
        }
    }

    private var songSearchSheet: some View {
        // Reuse the playlist track search as a song picker; adding here simply
        // surfaces the song (the scrobbler still tracks real now-playing). The
        // search view needs a playlist target, so we route to a transient
        // "session songs" playlist the user can later export.
        SessionSongSearch()
    }

    // MARK: Actions / helpers

    private func endSession() {
        Haptics.warning()
        onEnd()
        dismiss()
    }

    private func updateSessionType(_ type: SessionType) {
        guard var state = session.liveSesh else { return }
        state.sessionTypeRaw = type.rawValue
        session.saveLiveSesh(state)
    }

    private func matchedStrain(_ live: LiveSeshState) -> StrainProfile? {
        strains.strains.first { $0.name.caseInsensitiveCompare(live.strainName) == .orderedSame }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }
}

/// A lightweight song search used from the Session Active screen. Lets the user
/// search Apple Music / Spotify and pick a track; selection is informational here
/// (the scrobbler tracks the real now-playing), but it also offers to add the
/// track to a playlist so a session soundtrack can be built.
struct SessionSongSearch: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Ensure a "Session Soundtrack" playlist exists to receive picks.
        let target = ensureSessionPlaylist()
        TrackSearchView(playlistID: target)
    }

    private func ensureSessionPlaylist() -> String {
        if let existing = playlists.playlists.first(where: { $0.name == "Session Soundtrack" }) {
            return existing.id
        }
        return playlists.createPlaylist(name: "Session Soundtrack", autoCollect: true).id
    }
}
