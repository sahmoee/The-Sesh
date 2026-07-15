//
//  StatusPill.swift
//  The SESH
//
//  The user's status as a compact, global pill that opens a dropdown to override.
//  Status is mostly automatic (away -> ready on open, rolling/smoking during a
//  sesh, vibing -> away after), but the dropdown lets the user set any of the
//  five states or a custom one. Auto-transitions win over manual choices.
//

import SwiftUI

/// A compact status pill — shows the current status + "time since last sesh",
/// and opens a dropdown menu to change it. Designed to sit off to the side
/// (e.g. a header corner) rather than be a main attraction.
struct StatusPill: View {
    @Environment(SocialStore.self) private var social
    @Environment(AppSession.self) private var session
    var compact: Bool = false
    @State private var showCustom = false

    var body: some View {
        Menu {
            ForEach(SeshStatus.presets, id: \.self) { status in
                Button {
                    social.setStatus(status); Haptics.selection()
                } label: {
                    if social.myStatus == status {
                        Label(status.label, systemImage: "checkmark")
                    } else {
                        Text(status.label)
                    }
                }
            }
            if !session.savedStatuses.isEmpty {
                Divider()
                ForEach(session.savedStatuses) { saved in
                    Button {
                        social.setStatus(.custom(saved.text)); Haptics.selection()
                    } label: {
                        if social.myStatus == .custom(saved.text) {
                            Label(saved.text, systemImage: "checkmark")
                        } else {
                            Label(saved.text, systemImage: "bookmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                showCustom = true
            } label: {
                Label("Custom…", systemImage: "square.and.pencil")
            }
        } label: {
            pill
        }
        .alert("Set a custom status", isPresented: $showCustom) {
            CustomStatusField { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    social.setStatus(.custom(trimmed))
                    session.rememberStatus(trimmed)   // save for reuse in the dropdown
                    Haptics.success()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Show your friends what you're up to.")
        }
    }

    private var pill: some View {
        let status = social.myStatus
        return HStack(spacing: 6) {
            Circle().fill(status.tint).frame(width: 8, height: 8)
            if !compact {
                Text(status.shortLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text)
                if let since = session.timeSinceLastSeshPhrase, status == .away || status == .ready {
                    Text("· \(since)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.field))
        .overlay(Capsule().stroke(status.tint.opacity(0.35), lineWidth: 1))
    }
}

/// A tiny text field used inside the custom-status alert.
private struct CustomStatusField: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("e.g. Wake n bake", text: $text)
        Button("Set") { onSubmit(text) }
    }
}
