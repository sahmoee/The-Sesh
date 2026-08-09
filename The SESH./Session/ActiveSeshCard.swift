//
//  ActiveSeshCard.swift
//  The SESH
//
//  The rich "active sesh" card shown at the top of Home while a sesh is live,
//  matching the redesign mockups: an ACTIVE SESH label, the current activity,
//  the strain with its type and THC, a prominent live timer, the strain image,
//  and inline Log Thought / Change Method / End Sesh actions.
//

import SwiftUI

struct ActiveSeshCard: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(SocialStore.self) private var social

    /// Open the full active session screen (the expand control + card tap).
    var onExpand: () -> Void = {}
    /// Inline actions.
    var onLogThought: () -> Void = {}
    var onChangeMethod: () -> Void = {}
    var onEnd: () -> Void = {}

    @State private var confirmEnd = false

    private var live: LiveSeshState? { session.liveSesh }
    private var strain: StrainProfile? {
        guard let name = live?.strainName, !name.isEmpty else { return nil }
        return strains.strain(named: name)
    }

    private var activityTitle: String {
        // "Currently Smoking", "Currently Rolling up", etc.
        let phrase = social.me.activity.phrase.replacingOccurrences(of: "is ", with: "").capitalized
        return "Currently \(phrase)"
    }

    var body: some View {
        VStack(spacing: 14) {
            topRow
            actionRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.greenBright.opacity(0.35), lineWidth: 1)
        )
        .confirmationDialog("End this sesh?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Sesh", role: .destructive) { onEnd() }
            Button("Keep Going", role: .cancel) {}
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.greenBright).frame(width: 8, height: 8)
                    Text("ACTIVE SESH")
                        .font(.system(size: 11, weight: .bold)).tracking(0.8)
                        .foregroundStyle(Palette.greenBright)
                }
                Text(activityTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.text)

                if let strain {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(Palette.green)
                        Text(strain.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    Text(detailLine(strain))
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                } else if let name = live?.strainName, !name.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(Palette.green)
                        Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Only this readout needs the 1s clock — keep the TimelineView
                    // tight so the rest of the card doesn't re-evaluate every second.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(seshDuration(max(0, context.date.timeIntervalSince(live?.startedAt ?? context.date))))
                            .font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                    Text("active").font(.system(size: 13)).foregroundStyle(Palette.greenBright)
                }
            }
            Spacer(minLength: 0)
            VStack {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .minimumTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand session")
                Spacer()
                strainArt
            }
        }
    }

    @ViewBuilder private var strainArt: some View {
        if let strain {
            StoredImage(name: strain.photoName, size: 76, corner: Radius.md, strainID: strain.id)
        } else {
            RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field)
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: "smoke.fill").font(.system(size: 26)).foregroundStyle(Palette.textTertiary))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton("Log Thought", "brain.head.profile", Palette.text, action: onLogThought)
            actionButton("Change", "arrow.triangle.2.circlepath", Palette.text, action: onChangeMethod)
            actionButton("End Sesh", "xmark.circle", Palette.moodAngry, action: { confirmEnd = true })
        }
        .accessibilityElement(children: .combine)
    }

    private func actionButton(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(tint.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func detailLine(_ strain: StrainProfile) -> String {
        var parts: [String] = [strain.type.rawValue]
        if let thc = strain.thc, thc > 0 {
            parts.append("THC \(Int(thc))%")
        }
        return parts.joined(separator: " · ")
    }
}
