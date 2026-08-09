//
//  LoungeLiveRoomView.swift
//  The SESH
//
//  (SESH-RL-001-R2 §9, Phase 4) The live room.
//
//  A "shared active space" — messages, quick reactions, presence — never a
//  livestream. The room rides SocialStore's room-message machinery (the server
//  auto-provisions roomID "lounge_<postID>" for every live post), polls for new
//  messages on a short cadence while the app is active, and degrades into a
//  graceful ended state that routes people to rooms still burning.
//

import SwiftUI

// MARK: - Entry

struct LoungeLiveRoomView: View {
    @Environment(\.dismiss) private var dismiss

    let post: LoungePost

    /// Set when the user hops from this room's ended state into another live
    /// room. `.id` below resets all room state for the new post.
    @State private var switched: LoungePost?

    private var active: LoungePost { switched ?? post }

    var body: some View {
        LoungeLiveRoomContent(
            post: active,
            onLeave: { dismiss() },
            onSwitch: { next in
                Haptics.tap()
                switched = next
            }
        )
        .id(active.id)
    }
}

// MARK: - Room content

private struct LoungeLiveRoomContent: View {
    @Environment(LoungeFeedStore.self) private var store
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase

    let post: LoungePost
    var onLeave: () -> Void
    var onSwitch: (LoungePost) -> Void

    @State private var draft = ""
    @State private var endedLocally = false
    @State private var showEndConfirm = false
    @State private var ending = false
    @State private var roomToast: String?
    /// Live participant count from GET /api/rooms/:id/presence; nil until the
    /// first successful fetch (falls back to the post's stored count).
    @State private var presenceCount: Int?

    /// One-tap reactions, sent as ordinary room messages so everyone sees them.
    private let quickReactions = ["🔥", "😂", "💨", "🎶"]

    private var live: LoungeLiveRoom? { post.live }
    private var isEnded: Bool { endedLocally || live?.isLive != true }
    /// The post's author id is the Worker-verified uid ("apple:…"/"guest:…"),
    /// so host detection must compare against the verified session uid — NOT
    /// `social.me.id`, which is the raw unprefixed credential id.
    private var isHost: Bool {
        guard let uid = SeshAuth.shared.uid else { return false }
        return post.author.id == uid
    }
    /// Server contract: live posts auto-provision roomID "lounge_<postID>".
    private var roomID: String { live?.roomID ?? "lounge_\(post.id)" }

    /// Live presence when known, else the count the feed delivered. Never 0 —
    /// the viewer is in the room.
    private var displayedParticipants: Int {
        max(1, presenceCount ?? live?.participantCount ?? 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            LoungeLampGlow().padding(.top, 10)

            // Guard gracefully: a live post without room data, or a room that
            // has ended, opens the wind-down state instead of a dead chat.
            if live == nil || isEnded {
                endedState
            } else {
                roomBody
            }
        }
        .toast($roomToast, systemImage: "dot.radiowaves.left.and.right")
        .confirmationDialog("End this sesh?",
                            isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("End Session", role: .destructive) { endSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The room closes for everyone in the circle.")
        }
    }

    // MARK: Live room

    private var roomBody: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.stroke)
            messageFeed
            reactionRow
            composer
        }
        .onAppear { social.openRoom(roomID) }
        .onDisappear { social.closeRoom(roomID) }
        // Poll for new messages every ~5s. Keyed on scenePhase so the loop is
        // cancelled the moment the app leaves the foreground and restarts on
        // return; leaving the room cancels it via .task's lifecycle.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // First tick immediately so presence isn't stale for 5s on entry.
            if let count = await store.api.fetchRoomPresence(roomID: roomID,
                                                            identity: store.currentIdentity) {
                presenceCount = count
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                // Merge (not replace) so optimistic sends that haven't flushed
                // through the outbox don't vanish mid-poll.
                await social.refreshRoom(roomID)
                if let count = await store.api.fetchRoomPresence(roomID: roomID,
                                                                identity: store.currentIdentity) {
                    presenceCount = count
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                livePill
                Spacer(minLength: 0)
                if isHost && !isEnded {
                    Button(action: { Haptics.tap(); showEndConfirm = true }) {
                        Text(ending ? "Ending…" : "End Session")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.moodAngry)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Capsule().fill(Palette.field))
                            .overlay(Capsule().stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .minimumTapTarget()
                    .disabled(ending)
                    .accessibilityLabel("End this live session")
                }
                Button(action: { Haptics.tap(); onLeave() }) {
                    Text("Leave")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Palette.field))
                        .overlay(Capsule().stroke(Palette.strokeSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Leave the room")
            }

            Text(live?.title ?? "Live session")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
                .shadow(color: Palette.gold.opacity(0.3), radius: 10, y: 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                participantAvatars
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.goldSoft)
                    Text("\(displayedParticipants) in the circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(displayedParticipants) people in the circle")
            }

            if let tags = live?.vibeTags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(tags, id: \.self) { LoungeChip(text: $0) }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var livePill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isEnded ? Palette.textTertiary : Palette.moodAngry)
                .frame(width: 6, height: 6)
            Text(isEnded ? "ENDED" : "LIVE")
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.5)))
        .overlay(Capsule().stroke(Palette.goldRing.opacity(0.4), lineWidth: 1))
        .accessibilityLabel(isEnded ? "Session ended" : "Live now")
    }

    @ViewBuilder private var participantAvatars: some View {
        let avatars = Array((live?.participantAvatars ?? []).prefix(4))
        if !avatars.isEmpty {
            HStack(spacing: -7) {
                ForEach(Array(avatars.enumerated()), id: \.offset) { _, raw in
                    Group {
                        if let url = URL(string: raw) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Palette.field)
                            }
                        } else {
                            Circle().fill(Palette.field)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.goldRing.opacity(0.5), lineWidth: 1))
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Messages

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if social.hasMoreByRoom[roomID] != false && social.messages(in: roomID).count >= 50 {
                        Button(action: { Task { await social.loadOlderMessages(in: roomID) } }) {
                            Text("Load earlier messages")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.gold)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    if social.messages(in: roomID).isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 22))
                                .foregroundStyle(Palette.textTertiary)
                            Text("Quiet circle so far. Say something.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    ForEach(social.messages(in: roomID)) { message in
                        ChatBubble(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: social.messages(in: roomID).count) {
                if let last = social.messages(in: roomID).last {
                    withMotion { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    /// One-tap emoji reactions, sent into the room like any message.
    private var reactionRow: some View {
        HStack(spacing: 8) {
            ForEach(quickReactions, id: \.self) { emoji in
                Button(action: {
                    Haptics.tap()
                    social.send(emoji, to: roomID)
                }) {
                    Text(emoji)
                        .font(.system(size: 18))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Palette.field))
                        .overlay(Capsule().stroke(Palette.strokeSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Send \(emoji) reaction")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    /// Mirrors the app's chat composer (ChatRoomView / Cypher chat).
    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft,
                      prompt: Text("Say something to the circle…")
                        .foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Palette.field))
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
                .accessibilityLabel("Message the circle")
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.green)
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.tabBar.overlay(
            Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .top))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        social.send(text, to: roomID)
        draft = ""
        Haptics.tap()
    }

    // MARK: Host controls

    private func endSession() {
        guard !ending else { return }
        ending = true
        Task {
            let ok = await store.api.endLoungeLive(postID: post.id, identity: store.currentIdentity)
            if ok {
                // Reflect the ended room in the feed so cards update too.
                store.applyPublic(to: post.id) { $0.live?.isLive = false }
                endedLocally = true
                Haptics.tap()
            } else {
                roomToast = "Couldn't end the session. Try again."
                Haptics.warning()
            }
            ending = false
        }
    }

    // MARK: Ended state (§9)

    /// Other rooms still going, offered as the next stop.
    private var stillBurning: [LoungePost] {
        store.posts.filter { $0.kind == .live && $0.live?.isLive == true && $0.id != post.id }
    }

    private var endedState: some View {
        VStack(spacing: 0) {
            HStack {
                livePill
                Spacer()
                Button(action: { Haptics.tap(); onLeave() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.field))
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 22) {
                    EmptyStateView(icon: "moon.stars",
                                   title: "This sesh has ended",
                                   message: "The circle wound down and the lamp's been turned off. Thanks for pulling up.")
                        .padding(.top, 26)

                    if !stillBurning.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Still burning")
                                .font(.system(size: 17, weight: .semibold, design: .serif))
                                .foregroundStyle(Palette.text)
                                .shadow(color: Palette.gold.opacity(0.25), radius: 8, y: 1)
                            ForEach(stillBurning) { other in
                                stillBurningRow(other)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                    }

                    Button(action: { Haptics.tap(); onLeave() }) {
                        Text("Back to the Lounge")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.onGreen)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(Palette.green))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .accessibilityLabel("Back to the Lounge")

                    Color.clear.frame(height: 30)
                }
            }
        }
    }

    private func stillBurningRow(_ other: LoungePost) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.goldDeep.opacity(0.6), Palette.card],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.goldSoft)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(other.live?.title ?? "Live session")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text("\(max(1, other.live?.participantCount ?? 1)) in the circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)

            Button(action: { onSwitch(other) }) {
                Text("Join")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.green))
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("Join \(other.live?.title ?? "live session")")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .stroke(Palette.goldRing.opacity(0.4), lineWidth: 1))
    }
}
