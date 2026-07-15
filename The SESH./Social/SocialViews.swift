//
//  SocialViews.swift
//  SESH
//
//  The social companion surfaces: a live activity feed, friends' presence,
//  Cyphers (shared sessions you can host/join), live streams, and chat rooms.
//  Backed by SocialStore (Worker + seeded fallback).
//

import SwiftUI

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


// MARK: - Shared helpers

/// Compact "2m", "1h", "just now" relative time for the social feed.
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
                                    ActivityGlyph(activity: f.activity, size: 13)
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
                        ActivityGlyph(activity: e.activity, size: 18).frame(width: 24)
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
                        ActivityGlyph(activity: act, size: 20)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your status").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                        Text("\(social.me.displayName) \(act.phrase) · \(elapsedPhrase(social.activityStartedAt))")
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
                                  isSelected: isCurrent, fillWidth: false,
                                  iconName: act.iconName) {
                            social.setMyActivity(act); Haptics.selection()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cyphers list

