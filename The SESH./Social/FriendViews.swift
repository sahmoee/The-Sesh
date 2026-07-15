//
//  FriendViews.swift
//  The SESH
//
//  Split out of SocialViews.swift (#3 — file size). No code changes.
//

import SwiftUI

struct FriendSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    let user: SeshUser
    @State private var showBlockConfirm = false

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
                    ActivityGlyph(activity: user.activity, size: 22)
                    Text(user.displayName + " " + user.activity.phrase).font(.system(size: 15, weight: .medium)).foregroundStyle(user.activity.tint)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Palette.field))

                // Friend's currently-playing track, if they share it.
                if let np = user.nowPlaying, np.isCurrent() {
                    NowPlayingLine(np: np)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.field.opacity(0.6)))
                }

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
                Button(role: .destructive) { showBlockConfirm = true } label: {
                    Label("Block", systemImage: "hand.raised")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.moodAngry)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                }.buttonStyle(.plain)
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
                    FriendRow(friend: f)
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

// MARK: - One friend row (split out so FriendsView.friendsList type-checks fast)

private struct FriendRow: View {
    let friend: SeshUser

    var body: some View {
        HStack(spacing: 12) {
            PresenceAvatar(user: friend, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                statusLines
            }
            Spacer()
            if friend.streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Palette.gold)
                    Text("\(friend.streak)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    @ViewBuilder private var statusLines: some View {
        if friend.activity.isActive {
            HStack(spacing: 5) {
                ActivityGlyph(activity: friend.activity, size: 14)
                Text(friend.activity.phrase.replacingOccurrences(of: "is ", with: "").capitalized)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(friend.activity.tint)
            }
            HStack(spacing: 5) {
                if friend.activity == .live {
                    Circle().fill(Palette.moodAngry).frame(width: 6, height: 6)
                    Text("Live now").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                } else {
                    Text("\(seshAgo(friend.lastSeen)) elapsed").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
            }
        } else {
            HStack(spacing: 5) {
                Circle().fill(Palette.textTertiary.opacity(0.5)).frame(width: 6, height: 6)
                Text("Offline · \(seshAgo(friend.lastSeen))").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
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
                                        ActivityGlyph(activity: e.activity, size: 20)
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
