//
//  SocialViews.swift
//  SESH
//
//  The social companion surfaces: a live activity feed, friends' presence,
//  Cyphers (shared sessions you can host/join), live streams, and chat rooms.
//  Backed by SocialStore (Worker + seeded fallback).
//

import SwiftUI

// MARK: - Shared helpers

/// Compact "2m", "1h", "just now" relative time for the social feed.
func seshAgo(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 10 { return "just now" }
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h" }
    return "\(h / 24)d"
}

// MARK: - Presence avatar

struct PresenceAvatar: View {
    let user: SeshUser
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Palette.greenDeep, Palette.green],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(user.initials).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(Palette.onGreen))
                .frame(width: size, height: size)
            if user.activity.isActive {
                Circle()
                    .stroke(user.activity.tint, lineWidth: 2.5)
                    .frame(width: size + 6, height: size + 6)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

// MARK: - Friends presence row (horizontal)

struct PresenceRow: View {
    @Environment(SocialStore.self) private var social
    var onTapFriend: (SeshUser) -> Void

    var body: some View {
        let active = social.activeFriends
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Active now").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Circle().fill(Palette.greenBright).frame(width: 7, height: 7)
                    Text("\(active.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(active) { f in
                            Button { onTapFriend(f) } label: {
                                VStack(spacing: 5) {
                                    PresenceAvatar(user: f, size: 54)
                                    Text(f.displayName).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                                    Text("\(f.activity.emoji)").font(.system(size: 11))
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Activity feed (the social ticker)

struct ActivityFeedCard: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("The Feed").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    if !social.online {
                        Text("offline").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                }
                ForEach(social.feed.prefix(6)) { e in
                    HStack(spacing: 10) {
                        Text(e.activity.emoji).font(.system(size: 16)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.line).font(.system(size: 14)).foregroundStyle(Palette.text)
                            if let d = e.detail, !d.isEmpty {
                                Text(d).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer()
                        Text(seshAgo(e.at)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Quick activity broadcaster

struct BroadcastStrip: View {
    @Environment(SocialStore.self) private var social

    // Available/Busy are presence states; the rest are sesh activities.
    private let options: [SeshActivity] = [.available, .busy, .rollingUp, .lighting, .smoking, .hittingBong, .packingBowl]

    private func elapsedPhrase(_ since: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(since)))
        if secs < 60 { return "\(secs)s" }
        let m = secs / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Current status with a live-updating timer (auto-ticks every second).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let act = social.me.activity
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(act.tint.opacity(0.2)).frame(width: 38, height: 38)
                        Text(act.emoji).font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your status").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                        Text("You \(act.phrase) · \(elapsedPhrase(social.activityStartedAt))")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    Spacer()
                    if act != .idle {
                        Button { social.setMyActivity(.idle); Haptics.selection() } label: {
                            Text("Clear").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(act.tint.opacity(0.3), lineWidth: 1))
            }

            Text("Set your vibe").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { act in
                        let isCurrent = social.me.activity == act
                        EmojiChip(emoji: act.emoji,
                                  title: act.phrase.replacingOccurrences(of: "is ", with: "").capitalized,
                                  isSelected: isCurrent, fillWidth: false) {
                            social.setMyActivity(act); Haptics.selection()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cyphers list

struct CyphersView: View {
    @Environment(SocialStore.self) private var social
    @State private var showHost = false
    @State private var joined: Cypher?

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cyphers")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .padding(.top, 8)
                    Text("Shared sessions. Host your own Cyph or pull up to one that's already rolling.")
                        .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

                    if let activeID = social.activeCypherID,
                       let active = social.cyphers.first(where: { $0.id == activeID }) {
                        activeBanner(active)
                    }

                    ForEach(social.cyphers) { c in
                        CypherCard(cypher: c, onJoin: { social.joinCypher(c); joined = c; Haptics.success() })
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 18)
            }

            Button { showHost = true; Haptics.tap() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16, weight: .semibold))
                    Text("Host a Cypher").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Palette.onGreen)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Capsule().fill(Palette.green))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showHost) { HostCypherView() }
        .sheet(item: $joined) { c in CypherRoomView(cypherID: c.id) }
    }

    private func activeBanner(_ c: Cypher) -> some View {
        Button { joined = c } label: {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Palette.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're in \(c.title)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(c.participantCount) in the Cypher · tap to open").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.gold.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.gold.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CypherCard: View {
    @Environment(SocialStore.self) private var social
    let cypher: Cypher
    var onJoin: () -> Void

    private var amIn: Bool { cypher.participantIDs.contains(social.me.id) }

    var body: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(cypher.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                            if cypher.isLive {
                                Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Palette.moodAngry))
                            }
                        }
                        Text("Hosted by \(cypher.hostName)").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Text(seshAgo(cypher.startedAt)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }

                if let note = cypher.note {
                    Text(note).font(.system(size: 13)).foregroundStyle(Palette.text.opacity(0.9))
                }

                HStack(spacing: 12) {
                    if let strain = cypher.strainName {
                        Label(strain, systemImage: "leaf.fill").font(.system(size: 12)).foregroundStyle(Palette.greenBright)
                    }
                    Label("\(cypher.participantCount)/\(cypher.maxParticipants)", systemImage: "person.2.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button(action: onJoin) {
                        Text(amIn ? "Open" : (cypher.isFull ? "Full" : "Join"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(amIn ? Palette.text : Palette.onGreen)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(amIn ? Palette.field : (cypher.isFull ? Palette.textTertiary : Palette.green)))
                    }
                    .buttonStyle(.plain)
                    .disabled(cypher.isFull && !amIn)
                }
            }
        }
    }
}

// MARK: - Host a Cypher

struct HostCypherView: View {
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var strain = ""
    @State private var visibility: CypherVisibility = .publicCypher
    @State private var created: Cypher?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Host a Cypher", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 18) {
                        InputField(label: "Cypher name", placeholder: "e.g. Sunset sesh", value: $title)
                        InputField(label: "Strain (optional)", placeholder: "What you're smoking on", value: $strain)

                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Who can join")
                            Picker("", selection: $visibility) {
                                Text("Public").tag(CypherVisibility.publicCypher)
                                Text("Friends").tag(CypherVisibility.friends)
                                Text("Private").tag(CypherVisibility.privateCypher)
                            }.pickerStyle(.segmented)
                        }

                        PrimaryButton(title: "Start Cypher", icon: "dot.radiowaves.left.and.right") {
                            let c = social.hostCypher(title: title, strainName: strain.isEmpty ? nil : strain,
                                                      visibility: visibility, live: false)
                            Haptics.success()
                            created = c
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(item: $created) { c in
            CypherRoomView(cypherID: c.id, dismissParent: { dismiss() })
        }
    }
}

// MARK: - Cypher room (inside a shared session)

struct CypherRoomView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    let cypherID: String
    var dismissParent: (() -> Void)? = nil

    @State private var draft = ""

    private var cypher: Cypher? { social.cyphers.first { $0.id == cypherID } }
    // Cypher chat now syncs through the Worker, keyed by the Cypher's id.
    private var roomMessages: [ChatMessage] { social.messages(in: cypherID) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                if let c = cypher {
                    participantsStrip(c)
                    Divider().overlay(Palette.stroke)
                    messagesList
                    composer
                } else {
                    Spacer()
                    EmptyStateView(icon: "dot.radiowaves.left.and.right", title: "Cypher ended", message: "This session is no longer active.")
                    Spacer()
                }
            }
        }
        .onAppear { social.openRoom(cypherID) }
        .onDisappear { social.closeRoom(cypherID) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss(); dismissParent?() } label: {
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(cypher?.title ?? "Cypher").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    if cypher?.isLive == true {
                        Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Palette.moodAngry))
                    }
                }
                Text("\(cypher?.participantCount ?? 0) in the Cypher").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                social.leaveCypher(cypherID); Haptics.warning(); dismiss(); dismissParent?()
            } label: {
                Text("Leave").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.moodAngry)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.field))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
    }

    private func participantsStrip(_ c: Cypher) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(social.participants(of: c)) { p in
                    VStack(spacing: 4) {
                        PresenceAvatar(user: p, size: 46)
                        Text(p.id == social.me.id ? "You" : p.displayName)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                    }.frame(width: 56)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Say something to the Cypher 🌿")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                    ForEach(roomMessages) { m in
                        ChatBubble(message: m)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .onChange(of: roomMessages.count) {
                if let last = roomMessages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("Message the Cypher…").foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Palette.field))
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            Button { sendMessage() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Palette.green)
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.tabBar.overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .top))
    }

    /// Cypher chat syncs through the Worker (keyed by the Cypher id), so all
    /// participants see each other's messages.
    private func sendMessage() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        social.send(t, to: cypherID)
        draft = ""; Haptics.tap()
    }
}

// MARK: - Live Chat

/// A single always-on live chat room. Real-time text only — no video/voice.
/// Backed by the same server chat as community rooms, keyed by "rm_live".
struct LiveChatView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private let roomID = "rm_live"
    private var messages: [ChatMessage] { social.messages(in: roomID) }
    private var liveCount: Int { max(1, social.activeFriends.count + 1) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                Divider().overlay(Palette.stroke)
                messagesList
                composer
            }
        }
        .onAppear { social.openRoom(roomID) }
        .onDisappear { social.closeRoom(roomID) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    .frame(width: 38, height: 38).background(Circle().fill(Palette.cream)).overlay(Circle().stroke(Palette.creamStroke, lineWidth: 1))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Live Chat").font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Palette.moodAngry))
                }
                Text("\(liveCount) here now").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("Say something to the room \u{1F33F}")
                            .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    }
                    ForEach(messages) { m in
                        ChatBubble(message: m).id(m.id)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("Message the room\u{2026}").foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Palette.field))
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Palette.green)
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.tabBar.overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .top))
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        social.send(t, to: roomID)
        draft = ""; Haptics.tap()
    }
}


// MARK: - Chat rooms

struct ChatRoomsView: View {
    @Environment(SocialStore.self) private var social
    @State private var openRoom: ChatRoom?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Chat Rooms")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.text).padding(.top, 8)
                    Text("Jump into the conversation.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

                    ForEach(social.rooms) { room in
                        Button { social.markRoomRead(room.id); openRoom = room } label: {
                            RoomRow(room: room)
                        }.buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 18)
            }
        }
        .sheet(item: $openRoom) { r in ChatRoomView(roomID: r.id) }
    }
}

struct RoomRow: View {
    let room: ChatRoom
    var body: some View {
        DarkCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.greenDeep, Palette.green], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 18)).foregroundStyle(Palette.onGreen)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(room.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        if room.unread > 0 {
                            Text("\(room.unread)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Palette.moodAngry))
                        }
                    }
                    Text(room.lastMessage ?? room.topic).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let at = room.lastMessageAt {
                        Text(seshAgo(at)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Label("\(room.memberCount)", systemImage: "person.2.fill").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }
}

struct ChatRoomView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    @State private var draft = ""

    private var room: ChatRoom? { social.rooms.first { $0.id == roomID } }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                Divider().overlay(Palette.stroke)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if social.hasMoreByRoom[roomID] != false && social.messages(in: roomID).count >= 50 {
                                Button { Task { await social.loadOlderMessages(in: roomID) } } label: {
                                    Text("Load earlier messages")
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.gold)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                }.buttonStyle(.plain)
                            }
                            ForEach(social.messages(in: roomID)) { m in
                                ChatBubble(message: m).id(m.id)
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    .onChange(of: social.messages(in: roomID).count) {
                        if let last = social.messages(in: roomID).last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                composer
            }
        }
        .onAppear { social.openRoom(roomID) }
        .onDisappear { social.closeRoom(roomID) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(room?.name ?? "Room").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(room?.memberCount ?? 0) members").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("Message \(room?.name ?? "")…").foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Palette.field))
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            Button {
                social.send(draft, to: roomID); draft = ""; Haptics.tap()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Palette.green)
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.tabBar.overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .top))
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.isMe { Spacer(minLength: 40) }
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 2) {
                if !message.isMe {
                    Text(message.senderName).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.gold)
                }
                Text(message.text)
                    .font(.system(size: 15)).foregroundStyle(message.isMe ? Palette.onGreen : Palette.text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isMe ? Palette.green : Palette.card))
            }
            if !message.isMe { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Friend profile peek

struct FriendSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    let user: SeshUser
    @State private var showBlockConfirm = false
    @State private var showReport = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Capsule().fill(Palette.stroke).frame(width: 36, height: 4).padding(.top, 10)
                PresenceAvatar(user: user, size: 88)
                VStack(spacing: 4) {
                    Text(user.displayName).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
                    Text(user.handle).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                }
                HStack(spacing: 8) {
                    Text(user.activity.emoji)
                    Text(user.displayName + " " + user.activity.phrase).font(.system(size: 15, weight: .medium)).foregroundStyle(user.activity.tint)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Palette.field))

                HStack(spacing: 24) {
                    stat("\(user.streak)", "day streak")
                    stat(seshAgo(user.lastSeen), "last seen")
                }

                if user.activity == .live {
                    PrimaryButton(title: "Join the Live Chat", icon: "bubble.left.and.bubble.right.fill") { dismiss() }
                        .padding(.horizontal, 18)
                } else if user.activity == .inCypher {
                    PrimaryButton(title: "Join their Cypher", icon: "dot.radiowaves.left.and.right") { dismiss() }
                        .padding(.horizontal, 18)
                }

                // Safety actions
                HStack(spacing: 12) {
                    Button { showReport = true } label: {
                        Label("Report", systemImage: "flag")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    }.buttonStyle(.plain)
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label("Block", systemImage: "hand.raised")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.moodAngry)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18)

                Spacer()
            }
        }
        .confirmationDialog("Block \(user.displayName)?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await social.block(user) }
                Haptics.warning(); dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their activity, cyphers, or messages. You can unblock them later.")
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(user: user).presentationDetents([.medium])
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Friends (add by code)

struct FriendsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var status: String?
    @State private var working = false
    @State private var copied = false
    @State private var friendQuery = ""

    private var friends: [SeshUser] {
        let sorted = social.friends.sorted { $0.displayName < $1.displayName }
        guard !friendQuery.isEmpty else { return sorted }
        return sorted.filter {
            $0.displayName.localizedCaseInsensitiveContains(friendQuery) ||
            $0.handle.localizedCaseInsensitiveContains(friendQuery)
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Friends", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        myCodeCard
                        addByCodeCard
                        friendsList
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18).padding(.top, 4)
                }
            }
        }
    }

    private var myCodeCard: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR FRIEND CODE").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                HStack {
                    Text(social.friendCode)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.gold)
                        .accessibilityLabel("Your friend code is \(social.friendCode.replacingOccurrences(of: "-", with: " "))")
                    Spacer()
                    Button {
                        UIPasteboard.general.string = social.friendCode
                        withAnimation { copied = true }
                        Haptics.success()
                        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.onGreen)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.green))
                    }.buttonStyle(.plain)
                    .accessibilityHint("Copies your friend code to share")
                }
                Text("Share this code so friends can add you.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addByCodeCard: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ADD A FRIEND").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                HStack(spacing: 10) {
                    TextField("", text: $codeInput, prompt: Text("Enter code (e.g. sesh-7K9F)").foregroundStyle(Palette.textTertiary))
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Palette.text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    Button { addFriend() } label: {
                        if working { ProgressView().tint(Palette.onGreen) }
                        else { Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.onGreen) }
                    }
                    .frame(width: 48, height: 46)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                    .buttonStyle(.plain)
                    .disabled(working || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add friend")
                }
                if let status {
                    Text(status).font(.system(size: 13)).foregroundStyle(status.contains("added") ? Palette.greenBright : Palette.moodAngry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var friendsList: some View {
        if social.friends.count > 5 {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                TextField("", text: $friendQuery, prompt: Text("Search friends").foregroundStyle(Palette.textTertiary))
                    .font(.system(size: 14)).foregroundStyle(Palette.text)
                if !friendQuery.isEmpty {
                    Button { friendQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        Text("YOUR FRIENDS (\(friends.count))").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
        if friends.isEmpty {
            EmptyStateView(icon: "person.2",
                           title: friendQuery.isEmpty ? "No friends yet" : "No matches",
                           message: friendQuery.isEmpty ? "Share your code or add someone by theirs to get started." : "Try a different name.")
        } else {
            List {
                ForEach(friends) { f in
                    HStack(spacing: 12) {
                        PresenceAvatar(user: f, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            if f.activity.isActive {
                                // Emoji + sentence-case status, e.g. "🌿 Rolling up"
                                HStack(spacing: 5) {
                                    Text(f.activity.emoji).font(.system(size: 12))
                                    Text(f.activity.phrase.replacingOccurrences(of: "is ", with: "").capitalized)
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(f.activity.tint)
                                }
                                // Live indicator / elapsed
                                HStack(spacing: 5) {
                                    if f.activity == .live {
                                        Circle().fill(Palette.moodAngry).frame(width: 6, height: 6)
                                        Text("Live now").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                    } else {
                                        Text("\(seshAgo(f.lastSeen)) elapsed").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                    }
                                }
                            } else {
                                HStack(spacing: 5) {
                                    Circle().fill(Palette.textTertiary.opacity(0.5)).frame(width: 6, height: 6)
                                    Text("Offline · \(seshAgo(f.lastSeen))").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        Spacer()
                        if f.streak > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Palette.gold)
                                Text("\(f.streak)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Haptics.warning(); social.removeFriend(f)
                        } label: { Label("Remove", systemImage: "person.badge.minus") }
                        Button {
                            Haptics.warning(); Task { await social.block(f) }
                        } label: { Label("Block", systemImage: "hand.raised") }
                        .tint(Palette.moodAngry)
                    }
                    .contextMenu {
                        Button(role: .destructive) { social.removeFriend(f) } label: { Label("Remove friend", systemImage: "person.badge.minus") }
                        Button(role: .destructive) { Task { await social.block(f) } } label: { Label("Block", systemImage: "hand.raised") }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(friends.count) * 78 + 8)
            .scrollDisabled(true)
        }
    }

    private func addFriend() {
        working = true; status = nil
        let code = codeInput
        Task {
            let result = await social.addFriend(code: code)
            working = false
            status = result
            if result.contains("added") { codeInput = ""; Haptics.success() } else { Haptics.warning() }
        }
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    let user: SeshUser
    @State private var reason = ""
    @State private var sent = false

    private let reasons = ["Spam", "Harassment", "Inappropriate content", "Impersonation", "Other"]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Report \(user.displayName)").font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.textTertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)

                if sent {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Palette.greenBright)
                        Text("Report submitted").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Thanks — our team will review it.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WHY ARE YOU REPORTING?").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                            FlowLayout(spacing: 8) {
                                ForEach(reasons, id: \.self) { r in
                                    let on = reason == r
                                    Button { reason = r; Haptics.selection() } label: {
                                        Text(r).font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(on ? Palette.onGreen : Palette.text)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(Capsule().fill(on ? Palette.green : Palette.field))
                                            .overlay(Capsule().stroke(on ? Color.clear : Palette.stroke, lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 4)
                    }
                    PrimaryButton(title: "Submit Report", icon: "flag.fill") {
                        Task { _ = await social.report(user: user, messageID: nil, reason: reason.isEmpty ? "Other" : reason) }
                        Haptics.success(); withAnimation { sent = true }
                        Task { try? await Task.sleep(for: .seconds(1.4)); dismiss() }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 18)
                    .disabled(reason.isEmpty)
                }
            }
        }
    }
}

// MARK: - Friend activity feed (full screen, #17)

struct FriendActivityView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Activity", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                if social.feed.isEmpty {
                    EmptyStateView(icon: "sparkles",
                                   title: "No activity yet",
                                   message: social.online ? "When your friends sesh, it'll show up here." : "You're offline — connect to see friend activity.")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(social.feed) { e in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(e.activity.tint.opacity(0.15)).frame(width: 42, height: 42)
                                        Text(e.activity.emoji).font(.system(size: 18))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.line).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                                        if let d = e.detail, !d.isEmpty {
                                            Text(d).font(.system(size: 12)).foregroundStyle(Palette.greenBright)
                                        }
                                    }
                                    Spacer()
                                    Text(seshAgo(e.at)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 18).padding(.bottom, 28)
                    }
                    .refreshable { await social.refresh() }
                }
            }
        }
    }
}
