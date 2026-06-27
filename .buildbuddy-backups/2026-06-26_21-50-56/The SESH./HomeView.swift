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
    var onOpenInbox: () -> Void = {}
    /// Routes a tapped Home Quick Action to its destination (handled by RootView).
    var onQuickAction: (HomeQuickAction) -> Void = { _ in }

    @State private var friendPeek: SeshUser?
    @State private var showSessionScreen = false
    @State private var feedCollapsed = false
    @State private var quickAction: SessionQuickAction = .none
    @State private var showToolsEditor = false

    // Button color pairs (soft fill + deep tint), built from the existing palette.
    private let rollFill = Palette.gold.opacity(0.16)
    private let rollTint = Palette.goldDeep
    private let smokeFill = Palette.green.opacity(0.16)
    private let smokeTint = Palette.greenDeep
    private let thoughtFill = Palette.purple.opacity(0.16)
    private let thoughtTint = Palette.purple
    private let endFill = Palette.moodAngry.opacity(0.14)
    private let endTint = Palette.moodAngry
    private let bongFill = Palette.greenBright.opacity(0.14)
    private let bongTint = Palette.greenBright

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
                        Button { showSessionScreen = true } label: {
                            CurrentStatusCard()
                                .padding(.horizontal, 18)
                                .padding(.bottom, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    buttonGrid
                    if !isLive {
                        HomeQuickActionsRow(onAction: { onQuickAction($0) })
                            .padding(.bottom, 18)
                    }
                    feedSection
                }
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $friendPeek) { f in
            FriendSheet(user: f).presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showSessionScreen, onDismiss: { quickAction = .none }) {
            SessionActiveView(onEnd: { onEndSesh() }, initialAction: quickAction)
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

            HStack(spacing: 10) {
                StatusPill()
                NotificationBell(tint: Palette.textSecondary, action: onOpenInbox)
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: Four primary buttons

    @ViewBuilder private var buttonGrid: some View {
        if isLive {
            liveQuickActions
        } else {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    illustratedTile(title: "Roll Up", subtitle: "Spark something special",
                                    icon: .rollUp, fill: rollFill, tint: rollTint) {
                        Haptics.tap(); onStartSesh(.rollingUp)
                    }
                    illustratedTile(title: "Smoking", subtitle: "Blunt or joint",
                                    icon: .smoking, fill: smokeFill, tint: smokeTint,
                                    highlighted: isLive, badge: isLive ? "active now" : nil) {
                        Haptics.tap(); onStartSesh(.smoking)
                    }
                }
                HStack(spacing: 14) {
                    illustratedTile(title: "High Thoughts", subtitle: "Let it flow",
                                    icon: .highThoughts, fill: thoughtFill, tint: thoughtTint) {
                        Haptics.tap(); onHighThought()
                    }
                    bongOrEndTile
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
    }

    /// While a sesh is active, the start tiles are replaced by quick actions for
    /// the live sesh: Add Song, Update Mood, and End Session (End lives only here
    /// and on the active screen). Tapping these opens the active screen, which
    /// hosts the song search, mood chips, and the end-and-summary flow.
    /// While a sesh is active, the start tiles are replaced by Session Tools —
    /// a separate, personalizable set of in-sesh actions (titled "Session Tools"
    /// vs the idle "Quick Actions"). Tapping a tool opens the active screen routed
    /// to that action.
    @ViewBuilder private var liveQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Tools")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                Button { showToolsEditor = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                        Text("Edit").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Palette.greenBright)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(session.sessionTools) { tool in
                    sessionToolTile(tool)
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
        .sheet(isPresented: $showToolsEditor) { SessionToolsEditor() }
    }

    private func sessionToolTile(_ tool: SessionTool) -> some View {
        Button {
            Haptics.tap()
            quickAction = tool.route
            showSessionScreen = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tool.symbol).font(.system(size: 22)).foregroundStyle(tool.tint).frame(height: 28)
                Text(tool.title)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(tool.tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Fourth tile: a Bong Rip start action when idle. While a sesh is live it
    /// becomes a View Session tile that opens the active screen — which is the
    /// only place a sesh can be ended.
    @ViewBuilder private var bongOrEndTile: some View {
        if isLive {
            illustratedTile(
                title: "View Session",
                subtitle: "Tap to manage your sesh",
                icon: .bongRip,
                fill: endFill,
                tint: endTint
            ) {
                Haptics.tap(); showSessionScreen = true
            }
            .accessibilityLabel("View Session")
            .accessibilityHint("Opens your active sesh, where you can end it")
        } else {
            illustratedTile(
                title: "Bong Rip",
                subtitle: "Take a rip",
                icon: .bongRip,
                fill: bongFill,
                tint: bongTint
            ) {
                Haptics.tap(); onStartSesh(.hittingBong)
            }
            .accessibilityLabel("Bong Rip")
            .accessibilityHint("Starts a bong rip sesh")
        }
    }

    /// Shared illustrated-tile builder. Renders the icon through SeshIconView so
    /// it follows the user's icon style (vintage / midnight / SF Symbols).
    private func illustratedTile(title: String, subtitle: String?, icon: SeshIcon,
                                 fill: Color, tint: Color,
                                 highlighted: Bool = false, badge: String? = nil,
                                 dashed: Bool = false, dimmed: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SeshIconView(icon: icon, size: 96, symbolColor: tint)
                    .opacity(dimmed ? 0.5 : 1)
                    .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
                Text(title)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(dimmed ? Palette.textTertiary : Palette.text)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                } else if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(dimmed ? Palette.textTertiary : Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .background(tileBackground(fill: fill, dashed: dashed))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Palette.greenBright, lineWidth: highlighted ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func tileBackground(fill: Color, dashed: Bool) -> some View {
        if dashed {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .foregroundStyle(Palette.stroke)
                )
        } else {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(Palette.stroke.opacity(0.5), lineWidth: 1)
                )
        }
    }

    // MARK: Social feed

    @ViewBuilder private var feedSection: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { feedCollapsed.toggle() } } label: {
            HStack {
                Text("Around you")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Image(systemName: feedCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                    Text("\(session.currentStreak)-day streak")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18).padding(.bottom, 10)

        if !feedCollapsed {
            VStack(spacing: 14) {
                NowPlayingCard()
                PresenceRow(onTapFriend: { friendPeek = $0 })
                ActivityFeedCard()
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Footer tiles

    @ViewBuilder private var footerTiles: some View {
        HStack(spacing: 10) {
            footerTile("Stash", "shippingbox.fill",
                       subtitle: session.stashRemaining.isEmpty ? nil : "\(session.stashRemaining.count)",
                       action: onOpenStash)
            footerTile("Lounge", "globe.americas.fill", subtitle: nil, action: onOpenLounge)
            footerTile("Strains", "leaf.fill", subtitle: nil, action: onOpenStrains)
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
