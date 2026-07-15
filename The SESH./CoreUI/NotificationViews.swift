//
//  NotificationViews.swift
//  The SESH
//
//  The UI surfaces for notifications:
//    - NotificationBannerModifier: a top in-app banner shown when a notification
//      arrives while the app is foregrounded. Styled like the toast.
//    - NotificationBell: a bell button with an unread badge for headers.
//    - NotificationInboxView: the bell screen — a scrollable history with
//      mark-all-read and clear.
//

import SwiftUI

// MARK: - In-app banner

/// Shows `notifications.activeBanner` as a tappable top banner that auto-dismisses.
struct NotificationBannerModifier: ViewModifier {
    @Environment(NotificationManager.self) private var notifications
    var onTap: (SeshNotification) -> Void = { _ in }

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let note = notifications.activeBanner {
                Button {
                    onTap(note)
                    notifications.dismissBanner()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: note.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.greenBright)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text).lineLimit(1)
                            Text(note.body)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.cardElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .padding(.horizontal, 14).padding(.top, 8)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: note.id) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.25)) { notifications.dismissBanner() }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notifications.activeBanner)
    }
}

extension View {
    func notificationBanner(onTap: @escaping (SeshNotification) -> Void = { _ in }) -> some View {
        modifier(NotificationBannerModifier(onTap: onTap))
    }
}

// MARK: - Bell button

/// A bell with an unread badge. Place in a header; `action` opens the inbox.
struct NotificationBell: View {
    @Environment(NotificationManager.self) private var notifications
    var tint: Color = Palette.text
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                if notifications.unreadCount > 0 {
                    Text(notifications.unreadCount > 9 ? "9+" : "\(notifications.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.moodAngry))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inbox screen

struct NotificationInboxView: View {
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                if notifications.inbox.isEmpty {
                    Spacer()
                    EmptyStateView(icon: "bell.slash",
                                   title: "No notifications yet",
                                   message: "Friend activity and invites will show up here.")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notifications.inbox) { note in
                                inboxRow(note)
                                if note.id != notifications.inbox.last?.id {
                                    Divider().overlay(Palette.stroke).padding(.leading, 56)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { notifications.markAllRead() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            }.buttonStyle(.plain)
            Text("Notifications")
                .font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
            Spacer()
            if !notifications.inbox.isEmpty {
                Button { notifications.clearInbox(); Haptics.tap() } label: {
                    Text("Clear").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
    }

    private func inboxRow(_ note: SeshNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor(note.kind))
                .frame(width: 32, height: 32)
                .background(Circle().fill(iconColor(note.kind).opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(note.body).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(relativeTime(note.at)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }

    private func iconColor(_ kind: SeshNotification.Kind) -> Color {
        switch kind {
        case .status:    return Palette.greenBright
        case .invite:    return Palette.gold
        case .chat:      return Palette.green
        case .milestone: return Palette.gold
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86_400 { return "\(secs / 3600)h" }
        return "\(secs / 86_400)d"
    }
}
