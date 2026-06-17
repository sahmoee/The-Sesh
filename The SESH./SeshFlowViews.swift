//
//  SeshFlowViews.swift
//  The SESH
//
//  The "What are you doing?" activity chooser (Start sesh entry point) and the
//  big color-coded CURRENT STATUS card shown on Home while a sesh/status is
//  live. Designed to match the product mockup.
//

import SwiftUI

// MARK: - Activity chooser ("What are you doing?")

/// The three sesh-start activities offered on the chooser sheet.
enum StartActivity: String, CaseIterable, Identifiable {
    case smoking, hittingBong, rollingUp
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smoking:     return "Smoking"
        case .hittingBong: return "Hitting the bong"
        case .rollingUp:   return "Rolling up"
        }
    }
    var subtitle: String {
        switch self {
        case .smoking:     return "Light it up and enjoy."
        case .hittingBong: return "Take a rip."
        case .rollingUp:   return "Roll one up. We'll time it."
        }
    }
    var emoji: String {
        switch self {
        case .smoking:     return "💨"
        case .hittingBong: return "🌬️"
        case .rollingUp:   return "🌿"
        }
    }
    /// Maps to the presence activity broadcast to friends.
    var activity: SeshActivity {
        switch self {
        case .smoking:     return .smoking
        case .hittingBong: return .hittingBong
        case .rollingUp:   return .rollingUp
        }
    }
    /// Which live-sesh stage to open in.
    var stage: SeshStage {
        switch self {
        case .rollingUp: return .rollingUp
        default:         return .smoking
        }
    }
    var tint: Color {
        switch self {
        case .smoking:     return Palette.green
        case .hittingBong: return Palette.purpleStroke
        case .rollingUp:   return Palette.greenBright
        }
    }
}

/// Bottom-sheet chooser: "What are you doing? Choose your vibe. We'll track it."
struct StartSeshChooser: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (StartActivity) -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What are you doing?")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(Palette.text)
                        Text("Choose your vibe. We'll track it for you.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 4)

                    VStack(spacing: 12) {
                        ForEach(StartActivity.allCases) { act in
                            Button {
                                Haptics.tap()
                                onPick(act)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Text(act.emoji).font(.system(size: 26))
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(act.title)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Palette.text)
                                        Text(act.subtitle)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .stroke(act.tint.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .fill(Palette.cardElevated)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }
}

// MARK: - CURRENT STATUS card (Home)

/// The big, color-coded status hero shown on Home while an activity is live.
/// Label + activity name + "Started at HH:MM" + a self-updating elapsed timer.
struct CurrentStatusCard: View {
    @Environment(SocialStore.self) private var social

    private var act: SeshActivity { social.me.activity }

    /// Card tint per activity (green smoking, purple bong, olive rolling).
    private var tint: Color {
        switch act {
        case .hittingBong: return Palette.purple
        case .rollingUp:   return Palette.greenDeep
        default:           return Palette.green
        }
    }
    private var accent: Color {
        switch act {
        case .hittingBong: return Palette.purpleStroke
        default:           return Palette.greenBright
        }
    }

    private func titleText(_ a: SeshActivity) -> String {
        // Sentence case, e.g. "Smoking", "Hitting the bong", "Rolling up".
        a.phrase.replacingOccurrences(of: "is ", with: "").capitalized
    }

    private func startedAtText() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "Started at \(f.string(from: social.activityStartedAt))"
    }

    private func elapsed(_ since: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(since)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT STATUS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.onGreen.opacity(0.7))
                    Text(titleText(act))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.onGreen)
                    Text(startedAtText())
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.onGreen.opacity(0.7))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(act.emoji).font(.system(size: 26))
                    Text(elapsed(social.activityStartedAt))
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text("elapsed")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.onGreen.opacity(0.6))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(tint))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(accent.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - Roll Complete celebration

/// Full-screen celebration shown when a roll timer is stopped. Confetti, big
/// time, optional "New Personal Record!" badge, and next-step buttons.
struct RollCompleteView: View {
    let seconds: Int
    let isRecord: Bool
    let onStartSmoking: () -> Void
    let onLogSession: () -> Void

    private var timeText: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ConfettiView().allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 18) {
                    Text("🎉").font(.system(size: 44))
                    Text("Roll complete!")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.text)
                    Text("You rolled for")
                        .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    Text(timeText)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)

                    if isRecord {
                        HStack(spacing: 8) {
                            Text("🔥").font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("New Personal Record!")
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gold)
                                Text("Fastest roll: \(timeText)")
                                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.goldRing, lineWidth: 1))
                    }
                }
                Spacer()
                VStack(spacing: 12) {
                    Button(action: onStartSmoking) {
                        Label("Start smoking", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onGreen)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                    }.buttonStyle(.plain)
                    Button(action: onLogSession) {
                        Label("Log this session", systemImage: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onCream)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.cream))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
    }
}

/// Lightweight falling-confetti effect (no external deps, uses Canvas + Timeline).
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        var x: Double; var delay: Double; var hue: Double; var size: Double; var spin: Double
    }
    private let pieces: [Piece] = (0..<80).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...1.5),
              hue: .random(in: 0...1), size: .random(in: 4...9), spin: .random(in: 0...360))
    }
    private let palette: [Color] = [Palette.green, Palette.greenBright, Palette.gold, Palette.purpleStroke]

    var body: some View {
        GeometryFreeConfetti(pieces: pieces.map { ($0.x, $0.delay, $0.size, $0.spin) }, colors: palette)
    }
}

/// Canvas-based confetti that doesn't need GeometryReader (forbidden in this app).
private struct GeometryFreeConfetti: View {
    let pieces: [(x: Double, delay: Double, size: Double, spin: Double)]
    let colors: [Color]
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for (i, p) in pieces.enumerated() {
                    let local = max(0, t - p.delay)
                    let fall = (local * 220).truncatingRemainder(dividingBy: size.height + 40)
                    let x = p.x * size.width + sin(local * 3 + Double(i)) * 16
                    let rect = CGRect(x: x, y: fall - 20, width: p.size, height: p.size * 1.6)
                    var path = Path(roundedRect: rect, cornerRadius: 1.5)
                    let angle = Angle(degrees: p.spin + local * 200)
                    path = path.applying(.init(translationX: rect.midX, y: rect.midY)
                        .rotated(by: angle.radians)
                        .translatedBy(x: -rect.midX, y: -rect.midY))
                    ctx.fill(path, with: .color(colors[i % colors.count]))
                }
            }
        }
    }
}
