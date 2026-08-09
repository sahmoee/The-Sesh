//
//  LoungeFeedView.swift
//  The SESH
//
//  (SESH-RL-001-R2 §3, §5, §6) The Lounge.
//
//  A live digital smoke circle under a warm hanging lamp: the lamp is centered
//  at the top, its glow falls directionally on the title and upper feed and
//  fades downward, and the title is centered with no stars beside it.
//
//  Column splits use a custom Layout rather than GeometryReader (architecture
//  rule), which also gives us exactly the behaviour §6.2 asks for: paired posts
//  are top-aligned and free to end at different heights.
//

import SwiftUI

// MARK: - Proportional two-column layout

/// Splits the available width between exactly two subviews and top-aligns them.
/// Unequal heights are intentional — the shorter post simply ends earlier.
struct LoungeSplit: Layout {
    var leadingFraction: CGFloat
    var spacing: CGFloat = LoungeMetrics.gutter

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let (lead, trail) = widths(for: width)
        var height: CGFloat = 0
        if subviews.count > 0 {
            height = max(height, subviews[0].sizeThatFits(.init(width: lead, height: nil)).height)
        }
        if subviews.count > 1 {
            height = max(height, subviews[1].sizeThatFits(.init(width: trail, height: nil)).height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lead, trail) = widths(for: bounds.width)
        if subviews.count > 0 {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: .init(width: lead, height: nil))
        }
        if subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.minX + lead + spacing, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: .init(width: trail, height: nil))
        }
    }

    private func widths(for total: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, total - spacing)
        let lead = available * leadingFraction
        return (lead, available - lead)
    }
}

// MARK: - Hanging lamp

/// The centered hanging lamp and its directional glow. Purely decorative.
struct LoungeLamp: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.stroke)
                .frame(width: 1.5, height: 18)
            LampShade()
                .fill(LinearGradient(colors: [Palette.goldDeep, Palette.goldSoft],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 62, height: 22)
            Capsule()
                .fill(Palette.gold)
                .frame(width: 40, height: 3)
                .blur(radius: 2)
        }
        .accessibilityHidden(true)
    }
}

struct LampShade: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Light that is strongest at the title and fades down the screen, rather than
/// brightening the whole interface (§3).
struct LoungeLampGlow: View {
    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Palette.gold.opacity(0.26), Palette.gold.opacity(0.08), .clear],
                    center: .center, startRadius: 0, endRadius: 200
                )
            )
            .frame(width: 380, height: 300)
            .blur(radius: 30)
            .offset(y: -40)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Feed

struct LoungeFeedView: View {
    @Environment(LoungeFeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var detailPost: LoungePost?
    @State private var menuPost: LoungePost?
    @State private var reportPost: LoungePost?
    @State private var joinToast: String?
    @State private var liveRoomPost: LoungePost?
    /// Join staged from inside the detail sheet; presented from its onDismiss.
    @State private var pendingLiveRoom: LoungePost?
    @State private var showCompose = false

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            LoungeLampGlow().padding(.top, 30)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: LoungeMetrics.bandSpacing) {
                    headerBlock
                    segmentBar(store: store)
                    filterBar(store: store)
                    feedBody
                    footer
                }
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.immediately)

            closeButton
        }
        .overlay(alignment: .bottomTrailing) { composeButton }
        .task { await store.loadIfNeeded() }
        .refreshable { await store.refresh() }
        .onAppear { syncAccessibility() }
        .onChange(of: dynamicTypeSize) { _, _ in syncAccessibility() }
        // Previews are foreground-only: backgrounding or leaving the Lounge
        // silences the aux instead of letting audio wander off-screen.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { LoungePreviewPlayer.shared.stop() }
        }
        .onDisappear { LoungePreviewPlayer.shared.stop() }
        // A sheet keeps the feed alive underneath, so returning from an expanded
        // post restores the exact scroll position (§10).
        .toast($joinToast, systemImage: "dot.radiowaves.left.and.right")
        .sheet(item: $detailPost, onDismiss: {
            // Joining from inside the detail sheet: present the room only after
            // the sheet has fully dismissed — a same-frame dismiss+present on
            // one presenter can silently drop the second presentation.
            if let pending = pendingLiveRoom {
                pendingLiveRoom = nil
                liveRoomPost = pending
            }
        }) { post in
            LoungePostDetailView(post: post, onJoinLive: { joinLive($0) })
                .environment(store)
        }
        .confirmationDialog("Post options",
                            isPresented: Binding(get: { menuPost != nil },
                                                 set: { if !$0 { menuPost = nil } }),
                            titleVisibility: .visible) {
            if let post = menuPost {
                Button("Not interested", role: .destructive) {
                    Task { await store.hide(post) }
                }
                Button("Report…") { reportPost = post }
                Button("Cancel", role: .cancel) { }
            }
        }
        .sheet(item: $reportPost) { post in
            LoungeReportSheet(post: post)
                .environment(store)
                .presentationDetents([.medium])
        }
        // The live room takes the whole screen — it's a place, not a peek.
        .fullScreenCover(item: $liveRoomPost) { post in
            LoungeLiveRoomView(post: post)
                .environment(store)
        }
        .sheet(isPresented: $showCompose) {
            LoungeComposeView()
                .environment(store)
        }
    }

    private func syncAccessibility() {
        store.accessibilityFullWidth = dynamicTypeSize >= .accessibility1
    }

    // MARK: Header

    private var closeButton: some View {
        HStack {
            Button(action: { Haptics.tap(); dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private var headerBlock: some View {
        VStack(spacing: 6) {
            LoungeLamp()
            // Centered, serif, and deliberately without stars beside it (§16).
            Text("The Lounge")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
                .shadow(color: Palette.gold.opacity(0.35), radius: 12, y: 2)
            Text("Come hang for a minute.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The Lounge")
    }

    private func segmentBar(store: LoungeFeedStore) -> some View {
        HStack(spacing: 0) {
            ForEach(LoungeTab.allCases) { tab in
                Button(action: { Haptics.selection(); store.tab = tab }) {
                    Text(tab.title)
                        .font(.system(size: 13, weight: store.tab == tab ? .semibold : .regular))
                        .foregroundStyle(store.tab == tab ? Palette.onCream : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(store.tab == tab ? Palette.creamElevated : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.tab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Palette.field.opacity(0.82)))
        .overlay(Capsule().stroke(Palette.goldRing.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, LoungeMetrics.horizontalPadding)
    }

    /// §5.1 — filters scroll horizontally rather than wrapping into dense rows.
    private func filterBar(store: LoungeFeedStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(LoungeFilter.allCases) { filter in
                    let selected = store.filter == filter
                    Button(action: { Haptics.selection(); store.filter = filter }) {
                        Text(filter.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.onCream : Palette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(selected ? Palette.creamElevated : Palette.field.opacity(0.78)))
                            .overlay(Capsule().stroke(selected ? Color.clear : Palette.goldRing.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, LoungeMetrics.horizontalPadding)
        }
    }

    // MARK: Body

    @ViewBuilder private var feedBody: some View {
        if store.isEmpty && store.loadFailed {
            LoungeMessageBlock(icon: "wifi.slash",
                               title: "Can't reach the room",
                               message: "You're offline or the Lounge is unreachable. Nothing was lost — pull to try again.")
        } else if store.isEmpty && store.loadedOnce {
            LoungeMessageBlock(icon: "moon.stars",
                               title: "Quiet in here",
                               message: "No posts match this filter yet. Try another category or check back in a bit.")
        } else if store.isEmpty {
            LoungeSkeleton()
        } else if store.tab == .live {
            // §7/§9 — Live Now is a uniform single-column list of consistent
            // full-width live cards; the organized-chaos bands stay on
            // For You / Following.
            liveNowList
        } else {
            ForEach(store.bands) { band in
                bandView(band)
                    .padding(.horizontal, LoungeMetrics.horizontalPadding)
                    .onAppear { prefetchIfNeeded(band) }
            }
        }
    }

    @ViewBuilder private var liveNowList: some View {
        // Ended rooms never show in Live Now.
        let rooms = store.posts.filter { $0.kind == .live && $0.live?.isLive == true }
        if rooms.isEmpty {
            LoungeMessageBlock(icon: "dot.radiowaves.left.and.right",
                               title: "Nothing live right now",
                               message: "No circles are burning at the moment. Check back in a bit — or pass something to the feed meanwhile.")
        } else {
            ForEach(rooms) { room in
                LoungeLiveCard(post: room, featured: true,
                               onOpen: { Haptics.tap(); detailPost = $0 },
                               onJoin: { joinLive($0) })
                    .padding(.horizontal, LoungeMetrics.horizontalPadding)
                    .onAppear { prefetchIfNeededLive(room, rooms: rooms) }
            }
        }
    }

    /// Live-list twin of prefetchIfNeeded: page in more once the user nears
    /// the bottom of the uniform list.
    private func prefetchIfNeededLive(_ room: LoungePost, rooms: [LoungePost]) {
        guard store.hasMore, !store.isLoading else { return }
        let tail = rooms.suffix(2).map(\.id)
        guard tail.contains(room.id) else { return }
        Task { await store.loadMore() }
    }

    @ViewBuilder private func bandView(_ band: LoungeBand) -> some View {
        switch band {
        case .full(let placement):
            card(placement)

        case .wideNarrow(let lead, let trail):
            LoungeSplit(leadingFraction: LoungeMetrics.wideFraction) {
                card(lead)
                card(trail)
            }

        case .narrowWide(let lead, let trail):
            LoungeSplit(leadingFraction: LoungeMetrics.narrowFraction) {
                card(lead)
                card(trail)
            }

        case .pairedShort(let lead, let trail):
            LoungeSplit(leadingFraction: 0.5) {
                card(lead)
                card(trail)
            }

        case .singleBubble(let placement, let side, let fraction):
            // Deliberate negative space on the opposite side (§6.2). The branch
            // lives outside LoungeSplit so the Layout always receives exactly
            // two static children rather than one _ConditionalContent.
            if side == .leading {
                LoungeSplit(leadingFraction: fraction) {
                    card(placement)
                    Color.clear.frame(height: 1)
                }
            } else {
                LoungeSplit(leadingFraction: 1 - fraction) {
                    Color.clear.frame(height: 1)
                    card(placement)
                }
            }
        }
    }

    private func card(_ placement: LoungePlacement) -> some View {
        LoungePostCard(
            placement: placement,
            onOpen: { Haptics.tap(); detailPost = $0 },
            onReact: { post in Task { await store.toggleReaction(post) } },
            onVote: { post, choice in Task { await store.vote(post, choiceID: choice) } },
            onMenu: { menuPost = $0 },
            onJoinLive: { joinLive($0) }
        )
    }

    /// The single join action for live rooms, shared by the feed cards and the
    /// detail sheet. Opens the room full screen; an ended room opens straight
    /// into its graceful wind-down state (§9).
    private func joinLive(_ post: LoungePost) {
        guard post.live != nil else {
            joinToast = "This live room isn't available"
            return
        }
        Haptics.tap()
        if detailPost != nil {
            // From the detail sheet: dismiss it and let its onDismiss present
            // the room once the transition completes.
            pendingLiveRoom = post
            detailPost = nil
        } else {
            liveRoomPost = post
        }
    }

    /// Floating compose entry — pass something to the circle.
    private var composeButton: some View {
        Button(action: { Haptics.tap(); showCompose = true }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.onGreen)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(
                        LinearGradient(colors: [Palette.green, Palette.greenDeep],
                                       startPoint: .top, endPoint: .bottom))
                )
                .overlay(Circle().stroke(Palette.goldRing.opacity(0.45), lineWidth: 1))
                // Lamp-glow: the button sits in the room's warm light.
                .shadow(color: Palette.gold.opacity(0.35), radius: 14, y: 4)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityLabel("Pass something to the circle")
        .padding(.trailing, 18)
        .padding(.bottom, 24)
    }

    @ViewBuilder private var footer: some View {
        if store.isLoading && !store.isEmpty {
            ProgressView()
                .tint(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else if store.loadFailed && !store.isEmpty {
            Button(action: { Task { await store.loadMore() } }) {
                Text("Tap to retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.greenBright)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        } else if !store.hasMore && !store.isEmpty {
            Text("You're all caught up.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    /// Page in more content a little before the user hits the end. New pages
    /// append, so nothing already on screen moves (§10).
    private func prefetchIfNeeded(_ band: LoungeBand) {
        guard store.hasMore, !store.isLoading else { return }
        let tail = store.bands.suffix(3).map(\.id)
        guard tail.contains(band.id) else { return }
        Task { await store.loadMore() }
    }
}

// MARK: - Supporting views

struct LoungeMessageBlock: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .padding(.vertical, 46)
    }
}

/// Placeholder bands while the first page loads — same rhythm as real content
/// so the feed doesn't jump when posts arrive.
struct LoungeSkeleton: View {
    var body: some View {
        VStack(spacing: LoungeMetrics.bandSpacing) {
            shimmer(height: 150)
            LoungeSplit(leadingFraction: LoungeMetrics.wideFraction) {
                shimmer(height: 190)
                shimmer(height: 120)
            }
            shimmer(height: 130)
        }
        .padding(.horizontal, LoungeMetrics.horizontalPadding)
        .accessibilityHidden(true)
    }

    private func shimmer(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.stroke, lineWidth: 1))
            .frame(height: height)
            .opacity(0.55)
    }
}

/// §12 reporting. Reasons mirror the policy list so moderation can act on them.
struct LoungeReportSheet: View {
    @Environment(LoungeFeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: LoungePost

    @State private var reason: LoungeReportReason = .other
    @State private var detail: String = ""
    @State private var submitting = false
    @State private var submitError: String?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Report post", onBack: { dismiss() })
                    .padding(.top, 8)

                Text("Reports are reviewed by moderation. The post is hidden from your feed either way.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    ForEach(LoungeReportReason.allCases) { option in
                        Button(action: { reason = option; Haptics.selection() }) {
                            HStack {
                                Text(option.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.text)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if reason == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.green)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Palette.field))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                InputField(label: "", placeholder: "Anything else we should know?", value: $detail)

                if let submitError {
                    Text(submitError)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.moodAngry)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: submit) {
                    Text(submitting ? "Sending…" : "Submit report")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(Palette.green))
                }
                .buttonStyle(.plain)
                .disabled(submitting)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        submitError = nil
        Task {
            let ok = await store.report(post, reason: reason, detail: detail)
            if ok {
                dismiss()
            } else {
                submitting = false
                submitError = "Couldn't send the report. Check your connection and try again."
                Haptics.warning()
            }
        }
    }
}
