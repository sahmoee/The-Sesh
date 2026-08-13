//
//  EnterLoungeCard.swift
//  The SESH
//
//  (SESH-RL-001-R2 §4.1) The home screen's destination card for The Lounge.
//
//  This is deliberately not a generic button: it previews the environment —
//  warm room light, live status, a short invitation — with one clear Enter
//  action. Home and the Lounge share a visual world so entering feels like
//  walking deeper into the same room (§3).
//

import SwiftUI

struct EnterLoungeCard: View {
    /// Shows LIVE NOW only when there is meaningful active community activity.
    var liveCount: Int = 0
    var onEnter: () -> Void = {}

    private var isLive: Bool { liveCount > 0 }

    var body: some View {
        Button(action: { Haptics.tap(); onEnter() }) {
            ZStack(alignment: .leading) {
                roomBackdrop
                roomScene
                content
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Palette.goldRing.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLive
                            ? "Enter the Lounge, live now, \(liveCount) active"
                            : "Enter the Lounge")
        .accessibilityHint("Opens the public community feed")
    }

    /// A warm, low-light room: deep brown base with lamp light pooling from the
    /// right, echoing the Lounge's own hanging lamp.
    private var roomBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.card, Palette.cardElevated, Palette.goldDeep.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            Image("leaf_texture")
                .resizable()
                .scaledToFill()
                .opacity(0.08)
                .blendMode(.softLight)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Palette.gold.opacity(0.30), .clear],
                        center: .center, startRadius: 0, endRadius: 130
                    )
                )
                .frame(width: 240, height: 180)
                .offset(x: 96, y: -18)
                .blur(radius: 18)
        }
        .accessibilityHidden(true)
    }

    private var roomScene: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: -12) {
                Spacer()
                plant
                couch
                    .frame(width: 150, height: 72)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.stroke.opacity(0.65))
                    .frame(width: 1, height: 18)
                LampShade()
                    .fill(LinearGradient(colors: [Palette.goldDeep, Palette.goldSoft],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 17)
                Circle()
                    .fill(Palette.goldSoft)
                    .frame(width: 8, height: 8)
                    .blur(radius: 2)
            }
            .offset(x: -34, y: -46)

            Circle()
                .fill(Palette.gold.opacity(0.32))
                .frame(width: 108, height: 108)
                .blur(radius: 24)
                .offset(x: -18, y: -30)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var couch: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.moodAngry.opacity(0.34))
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.goldRing.opacity(0.26), lineWidth: 1))
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.goldDeep.opacity(0.34))
                    .frame(width: 42, height: 30)
                    .rotationEffect(.degrees(-5))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.greenDeep.opacity(0.42))
                    .frame(width: 42, height: 28)
                    .rotationEffect(.degrees(4))
            }
            .offset(y: -20)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Palette.goldDeep.opacity(0.36))
                .frame(width: 86, height: 8)
                .offset(y: 10)
        }
    }

    private var plant: some View {
        VStack(spacing: 0) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 34))
                .foregroundStyle(Palette.greenBright.opacity(0.35))
                .rotationEffect(.degrees(-18))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.goldDeep.opacity(0.32))
                .frame(width: 18, height: 14)
        }
        .frame(width: 56)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if isLive {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.greenBright).frame(width: 6, height: 6)
                        Text("LIVE NOW")
                            .font(.system(size: 9, weight: .bold)).tracking(0.7)
                            .foregroundStyle(Palette.greenBright)
                    }
                }

                Text("Enter the Lounge")
                    .font(.system(size: 27, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)

                Text(isLive
                     ? "Join the vibe. See who's high right now."
                     : "Come hang for a minute. See what the circle's on.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text("Enter").font(.system(size: 14, weight: .bold))
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 20).padding(.vertical, 13)
            .background {
                Capsule()
                    .fill(Palette.goldSoft)
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: Palette.gold.opacity(0.28), radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 16)
    }
}
