//
//  HomeView.swift
//  HighThoughts
//
//  Redesigned home: four primary session buttons (Roll Up, Smoking,
//  High Thoughts, End Session) over a live social feed. End Session is only
//  enabled while a sesh is in progress; otherwise it's greyed out.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains

    // Callbacks wired by RootView.
    var onStartSesh: (StartActivity) -> Void = { _ in }
    var onEndSesh: () -> Void = {}
    var onHighThought: () -> Void = {}
    var onOpenStash: () -> Void = {}
    var onOpenLounge: () -> Void = {}
    var onOpenStrains: () -> Void = {}
    var onMenu: () -> Void = {}

    @State private var friendPeek: SeshUser?

    // Button color pairs (soft fill + deep tint), built from the existing palette.
    private let rollFill = Palette.gold.opacity(0.16)
    private let rollTint = Palette.goldDeep
    private let smokeFill = Palette.green.opacity(0.16)
    private let smokeTint = Palette.greenDeep
    private let thoughtFill = Palette.purple.opacity(0.16)
    private let thoughtTint = Palette.purple
    private let endFill = Palette.moodAngry.opacity(0.14)
    private let endTint = Palette.moodAngry

    /// A sesh is in progress when there's a live sesh state.
    private var isLive: Bool { session.hasActiveSesh }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if isLive {
                        CurrentStatusCard()
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                    }
                    buttonGrid
                    feedSection
                    footerTiles
                }
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $friendPeek) { f in
            FriendSheet(user: f).presentationDetents([.medium])
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(alignment: .top) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menu")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(session.userName)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                Text(isLive ? "You're seshing" : "What's the move?")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
            }
            .padding(.leading, 10)

            Spacer()

            Image(systemName: "bell")
                .font(.system(size: 20))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityLabel("Notifications")
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: Four primary buttons

    @ViewBuilder private var buttonGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                primaryButton(title: "Roll Up", icon: "flame.fill",
                              fill: rollFill, tint: rollTint) {
                    Haptics.tap(); onStartSesh(.rollingUp)
                }
                primaryButton(title: "Smoking", icon: "smoke.fill",
                              fill: smokeFill, tint: smokeTint,
                              highlighted: isLive, badge: isLive ? "active now" : nil) {
                    Haptics.tap(); onStartSesh(.smoking)
                }
            }
            HStack(spacing: 14) {
                primaryButton(title: "High Thoughts", icon: "brain",
                              fill: thoughtFill, tint: thoughtTint) {
                    Haptics.tap(); onHighThought()
                }
                endSessionButton
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }

    @ViewBuilder private var endSessionButton: some View {
        Button {
            guard isLive else { return }
            Haptics.warning(); onEndSesh()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isLive ? endTint : Palette.textTertiary)
                Text("End Session")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isLive ? endTint : Palette.textTertiary)
                if !isLive {
                    Text("no active sesh")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24).padding(.horizontal, 14)
            .background(endSessionBackground)
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityLabel("End Session")
        .accessibilityHint(isLive ? "Ends and saves your current sesh" : "No active sesh to end")
    }

    @ViewBuilder private var endSessionBackground: some View {
        if isLive {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(endFill)
        } else {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Palette.stroke)
                .opacity(0.6)
        }
    }

    private func primaryButton(title: String, icon: String,
                               fill: Color, tint: Color,
                               highlighted: Bool = false,
                               badge: String? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 32)).foregroundStyle(tint)
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
                if let badge {
                    Text(badge).font(.system(size: 11)).foregroundStyle(tint.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Palette.green, lineWidth: highlighted ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Social feed

    @ViewBuilder private var feedSection: some View {
        HStack {
            Text("Around you")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                Text("\(session.currentStreak)-day streak")
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 10)

        VStack(spacing: 14) {
            PresenceRow(onTapFriend: { friendPeek = $0 })
            BroadcastStrip()
            ActivityFeedCard()
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }

    // MARK: Footer tiles

    @ViewBuilder private var footerTiles: some View {
        HStack(spacing: 10) {
            footerTile("Stash", "shippingbox.fill",
                       subtitle: session.stashRemaining.isEmpty ? nil : "\(session.stashRemaining.count)",
                       action: onOpenStash)
            footerTile("Lounge", "globe.americas.fill", subtitle: nil, action: onOpenLounge)
        }
        .padding(.horizontal, 18)
    }

    private func footerTile(_ title: String, _ icon: String,
                            subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Palette.textSecondary)
                Text(subtitle == nil ? title : "\(title) · \(subtitle!)")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak ring (kept; used elsewhere)

struct StreakRing: View {
    let streak: Int
    let goal: Int
    private var progress: Double { goal > 0 ? min(1, Double(streak) / Double(goal)) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.creamStroke, lineWidth: 5).frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(streak)").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.onCream)
                Text("day").font(.system(size: 9)).foregroundStyle(Palette.onCreamSoft)
            }
        }
        .accessibilityLabel("Streak \(streak) of \(goal) days")
    }
}

// MARK: - Date helpers (shared)

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    return Fmt.shortDate(date)
}

func timeString(_ date: Date) -> String {
    Fmt.time(date)
}
