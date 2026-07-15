//
//  ChatViews.swift
//  The SESH
//
//  Split out of SocialViews.swift (#3 — file size). No code changes.
//

import SwiftUI

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

