//
//  MusicScreens.swift
//  The SESH
//
//  Two screens from the new mockup:
//   - ConnectedAppsView: shows the user's music connections (Spotify, Apple
//     Music) with connect / status, mirroring the mockup's "Connected Apps".
//   - HowItWorksView: the five-step explainer ("Start a Session" → "Get Your
//     Mix"), using the generated step icons with SF Symbol fallbacks.
//

import SwiftUI
import MusicKit

// MARK: - Connected Apps

struct ConnectedAppsView: View {
    @Environment(SpotifyAuth.self) private var spotify
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var appleAuthorized = MusicAuthorization.currentStatus == .authorized

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Connected Apps", onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 16) {
                    Text("Connect your music apps to enhance your sessions.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.top, 8)

                    spotifyRow
                    appleMusicRow

                    Text("We'll never post to your accounts without permission.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12).padding(.horizontal, 24)
                }
                .padding(18)
            }
        }
        .background(AppBackground())
        // The initial snapshot goes stale if the user changes authorization in
        // Settings — re-read it on appear and whenever the app comes back.
        .task { appleAuthorized = MusicAuthorization.currentStatus == .authorized }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appleAuthorized = MusicAuthorization.currentStatus == .authorized
            }
        }
    }

    private var spotifyRow: some View {
        connectionRow(
            name: "Spotify",
            symbol: "music.note",
            accent: Color(red: 0.11, green: 0.84, blue: 0.38),
            connected: spotify.isConnected,
            action: { spotify.isConnected ? spotify.disconnect() : spotify.connect() })
    }

    private var appleMusicRow: some View {
        connectionRow(
            name: "Apple Music",
            symbol: "music.note",
            accent: Color(red: 0.98, green: 0.25, blue: 0.43),
            connected: appleAuthorized,
            action: {
                guard !appleAuthorized else { return }
                Task {
                    let ok = await AppleMusicExporter.authorize()
                    await MainActor.run { appleAuthorized = ok }
                }
            })
    }

    private func connectionRow(name: String, symbol: String, accent: Color,
                               connected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18)).frame(width: 46, height: 46)
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Text(connected ? "Connected" : "Not connected")
                    .font(.system(size: 12))
                    .foregroundStyle(connected ? Palette.greenBright : Palette.textTertiary)
            }
            Spacer()
            if connected {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(Palette.greenBright)
                    Button("Disconnect", action: action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Button(action: action) {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.onGreen)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.greenBright))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - How It Works

struct HowItWorksView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)? = nil

    private let steps: [Step] = [
        Step(n: 1, title: "Start a Session", detail: "Pick your strain, method, and how you're feeling.",
             asset: "how_cloud", symbol: "smoke.fill"),
        Step(n: 2, title: "Add a Song", detail: "Add the song you're listening to.",
             asset: "how_note", symbol: "music.note"),
        Step(n: 3, title: "Save & Reflect", detail: "Save your session with mood and notes.",
             asset: "how_leaf", symbol: "leaf.fill"),
        Step(n: 4, title: "We Learn You", detail: "The Sesh learns the music and vibes you love.",
             asset: "how_bars", symbol: "chart.bar.fill"),
        Step(n: 5, title: "Get Your Mix", detail: "Get personalized playlists for every vibe.",
             asset: "how_headphones", symbol: "headphones"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "How It Works", onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(steps) { step in
                        stepRow(step)
                    }
                    if let onDone {
                        Button { onDone() } label: {
                            Text("Get Started")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.onGreen)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    Color.clear.frame(height: 16)
                }
                .padding(20)
            }
        }
        .background(AppBackground())
    }

    private func stepRow(_ step: Step) -> some View {
        HStack(spacing: 16) {
            stepArt(step)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(step.n). \(step.title)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(step.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    /// Step art: generated icon when present (midnight-aware), else SF Symbol.
    @ViewBuilder private func stepArt(_ step: Step) -> some View {
        let midnightName = step.asset + "_midnight"
        let useMidnight = theme.iconStyle == .midnight && UIImage(named: midnightName) != nil
        let name = useMidnight ? midnightName : step.asset
        if UIImage(named: name) != nil {
            Image(name).resizable().scaledToFit()
        } else {
            Image(systemName: step.symbol)
                .font(.system(size: 26))
                .foregroundStyle(Palette.greenBright)
        }
    }
}

private struct Step: Identifiable {
    var id: Int { n }
    let n: Int
    let title: String
    let detail: String
    let asset: String
    let symbol: String
}
