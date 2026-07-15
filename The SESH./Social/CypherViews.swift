//
//  CypherViews.swift
//  The SESH
//
//  Split out of SocialViews.swift (#3 — file size). No code changes.
//

import SwiftUI

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

