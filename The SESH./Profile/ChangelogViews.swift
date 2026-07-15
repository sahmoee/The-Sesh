//
//  ChangelogViews.swift
//  The SESH
//
//  Split out of AppChangelog.swift (#3 — file size). No code changes.
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var version: ChangelogVersion = AppChangelog.latest

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("What's New").font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    Text(version.headline).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(BuildConfig.displayLabel).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22).padding(.horizontal, 24).padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(version.entries) { entry in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(entry.tint)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(entry.tint.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text(entry.detail).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                }

                PrimaryButton(title: "Let's go", icon: "checkmark") {
                    AppChangelog.markWhatsNewSeen(); Haptics.success(); dismiss()
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
    }
}

// MARK: - Full changelog history (from Settings → About)

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Changelog", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(AppChangelog.versions) { version in
                            DarkCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Text("v\(version.version)").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                                        if version.isLatest {
                                            Text("LATEST").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onGreen)
                                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Palette.green))
                                        }
                                        Spacer()
                                        Text(version.buildLabel).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                    }
                                    ForEach(version.entries) { entry in
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: entry.icon).font(.system(size: 14)).foregroundStyle(entry.tint)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                                                Text(entry.detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
