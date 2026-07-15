//
//  ProfileView.swift
//  HighThoughts
//

import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        avatarSection
                        statRow
                        extrasMenu
                        gamificationMenu
                        settingsMenu
                        versionFooter
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private var headerSection: some View {
        ZStack {
            Text("Profile")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            HStack {
                Spacer()
                NavigationLink {
                    ProfileSettingsView().environment(session).navigationBarBackButtonHidden(true)
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Palette.text)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.cardElevated).frame(width: 96, height: 96)
                Circle().stroke(Palette.green, lineWidth: 2).frame(width: 96, height: 96)
                Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(Palette.green)
            }
            Text(session.userName)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            Text(session.joinedText)
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(Palette.green)
                Text("Cannabis Explorer").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var statRow: some View {
        HStack(spacing: 0) {
            statCol("\(session.sessionsLogged)", "Sessions")
            statCol("\(session.uniqueStrains)", "Strains")
            statCol("\(session.thoughts.count)", "Thoughts")
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    @ViewBuilder private var extrasMenu: some View {
        VStack(spacing: 0) {
            NavigationLink { SeshExtrasHub().environment(session).environment(strains) } label: {
                menuRow("square.grid.2x2.fill", "Extras")
            }.buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    /// App version footer (small feature): shows the composed build label.
    private var versionFooter: some View {
        Text(BuildConfig.displayLabel)
            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    @ViewBuilder private var gamificationMenu: some View {
        VStack(spacing: 0) {
            NavigationLink { JourneyMilestonesView().environment(session).environment(social).navigationBarBackButtonHidden(true) } label: {
                menuRow("trophy.fill", "Journey")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { PersonalRecordsView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("medal.fill", "Personal Records")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { YearlyRecapView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("calendar.badge.clock", "Yearly Recap")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { SecretBadgesView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("lock.fill", "Secret Badges")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { PersonalityProfileView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("person.fill.viewfinder", "Smoking Style")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { GoalsView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("target", "Goals")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { JokesView().navigationBarBackButtonHidden(true) } label: {
                menuRow("face.smiling", "Dad Jokes & Giggles")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { ListenView().navigationBarBackButtonHidden(true) } label: {
                menuRow("music.note", "Listen")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { MusicIdentityView().navigationBarBackButtonHidden(true) } label: {
                menuRow("waveform", "Music Identity")
            }.buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    @ViewBuilder private var settingsMenu: some View {
        VStack(spacing: 0) {
            NavigationLink { ProfileSettingsView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("gearshape", "Settings")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { ExportView().environment(session).navigationBarBackButtonHidden(true) } label: {
                menuRow("square.and.arrow.up", "Export & Backup")
            }.buttonStyle(.plain)
            rowDivider
            NavigationLink { AboutView().navigationBarBackButtonHidden(true) } label: {
                menuRow("info.circle", "About The Sesh")
            }.buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var rowDivider: some View {
        Rectangle().fill(Palette.stroke).frame(height: 1).padding(.leading, 50)
    }

    private func statCol(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text(l).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Palette.green).frame(width: 24)
            Text(title).font(.system(size: 16)).foregroundStyle(Palette.text)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings / Edit profile

struct ProfileSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(SocialStore.self) private var social
    @State private var name = ""
    @State private var showResetConfirm = false
    @State private var showClearMusicConfirm = false
    @State private var hapticsOn = true
    @State private var iCloudOn = CloudSync.isEnabled
    /// Friend-notifications toggle. Backed by the same UserDefaults key the
    /// NotificationManager reads, so flipping it here enables/disables friend
    /// status, invite, and chat notifications.
    @AppStorage(DefaultsKey.notifEnabled) private var notificationsOn = true

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 18) {
                        InputField(label: "Display Name", placeholder: "Your name", value: $name)
                        PrimaryButton(title: "Save") {
                            let n = name.trimmingCharacters(in: .whitespaces)
                            if !n.isEmpty { session.userName = n; session.save() }
                            Haptics.success()
                            dismiss()
                        }

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Account (Sign in with Apple)
                        accountSection

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // iCloud sync
                        iCloudSection

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Friend notifications
                        notificationsSection

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Now-playing scrobbler (Apple Music + Spotify)
                        ScrobbleSettingsSection()

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Appearance — theme + icon style now live on their own page.
                        NavigationLink {
                            AppearanceView().navigationBarBackButtonHidden(true)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paintbrush.fill")
                                    .font(.system(size: 16)).foregroundStyle(Palette.greenBright).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Appearance").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("Theme · \(theme.choice.label), Icons · \(theme.iconStyle.label)")
                                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Privacy & Safety: sharing controls, responsible use,
                        // community rules (#App16, #App17, #App18).
                        NavigationLink {
                            PrivacySafetyHubView().navigationBarBackButtonHidden(true)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 16)).foregroundStyle(Palette.greenBright).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Privacy & Safety").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("Sharing, responsible use, community rules")
                                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Preferences: haptics + clear music history
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Preferences")
                            Toggle(isOn: $hapticsOn) {
                                HStack(spacing: 10) {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.system(size: 15)).foregroundStyle(Palette.greenBright).frame(width: 22)
                                    Text("Haptics").font(.system(size: 15)).foregroundStyle(Palette.text)
                                }
                            }
                            .tint(Palette.green)
                            .onChange(of: hapticsOn) { _, newValue in
                                session.hapticsEnabled = newValue
                                if newValue { Haptics.selection() }
                            }

                            Button {
                                Haptics.warning(); showClearMusicConfirm = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 15)).foregroundStyle(Palette.moodAngry).frame(width: 22)
                                    Text("Clear Music History").font(.system(size: 15)).foregroundStyle(Palette.moodAngry)
                                    Spacer()
                                    Text("\(session.songPlays.count)")
                                        .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                                }
                                .padding(.vertical, 10).padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().overlay(Palette.stroke).padding(.vertical, 4)

                        // Danger zone: reset everything (also "logs out")
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Reset")
                            Button {
                                Haptics.warning(); showResetConfirm = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.counterclockwise")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Reset All Data & Log Out")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("Erases every session, thought, and photo, then signs you out.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Palette.moodAngry.opacity(0.8))
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(Palette.moodAngry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                }
            }
        }
        .onAppear { name = session.userName; hapticsOn = session.hapticsEnabled }
        .alert("Clear music history?", isPresented: $showClearMusicConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                session.clearMusicHistory(); Haptics.success()
            }
        } message: {
            Text("Removes all songs captured during your seshes. Stations and pairings will reset.")
        }
        .alert("Reset all data and log out?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Log Out", role: .destructive) {
                session.resetEverything()
                strains.clearCustom()
                Haptics.success()
                dismiss()
            }
        } message: {
            Text("This permanently erases everything on this device — sessions, thoughts, photos, and custom strains — and signs you out. This can't be undone.")
        }
    }

    // Sign in with Apple — signed-in status or the sign-in button.
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Account")
            if auth.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo").font(.system(size: 20)).foregroundStyle(Palette.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.fullName ?? "Signed in with Apple").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        if let email = auth.email {
                            Text(email).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        } else {
                            Text("Synced across your devices").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        // (#C9) Unregister this device's push token + drop the
                        // backend session before clearing local identity.
                        Task { await social.signOut() }
                        auth.signOut(); Haptics.warning()
                    } label: {
                        Text("Sign Out").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.moodAngry)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Palette.field))
                    }.buttonStyle(.plain)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            } else {
                AppleSignInRow()
                Text("Sign in to sync your sessions, thoughts, and settings across devices.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    // iCloud sync toggle.
    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "iCloud")
            Toggle(isOn: $iCloudOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with iCloud").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(CloudSync.isAvailable
                         ? "Back up sessions, thoughts, profile, and theme — and restore them on a new device."
                         : "Sign in to iCloud on this device to back up and sync your data.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.green)
            .disabled(!CloudSync.isAvailable)
            .onChange(of: iCloudOn) { _, newValue in
                CloudSync.isEnabled = newValue
                if newValue { session.save() }   // push current data up when re-enabled
                Haptics.selection()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    // Friend notifications on/off.
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Notifications")
            Toggle(isOn: $notificationsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friend notifications").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Get notified when friends change their status, invite you to a sesh, or send a message.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.green)
            .onChange(of: notificationsOn) { _, _ in Haptics.selection() }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

}

struct ExportView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Data", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 16) {
                        DarkCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your data stays on this device.")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("\(session.sessionsLogged) sessions · \(session.thoughts.count) thoughts")
                                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        PrimaryButton(title: "Export as JSON", icon: "square.and.arrow.up") {
                            if let url = makeExport() { shareURL = url; showShare = true }
                        }

                        Button {
                            Haptics.warning(); showClearConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("Clear All Data").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(Palette.moodAngry)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.top, 8)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .alert("Clear all data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { session.clearAll(); dismiss() }
        } message: {
            Text("This permanently removes all sessions, thoughts, and photos on this device. This can't be undone.")
        }
    }

    /// Serializes everything into a single JSON file in the temp dir.
    private func makeExport() -> URL? {
        let payload = ExportPayload(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            user: session.userName,
            entries: session.entries,
            thoughts: session.thoughts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sesh-Export.json")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

private struct ExportPayload: Codable {
    let exportedAt: String
    let user: String
    let entries: [JournalEntry]
    let thoughts: [HighThought]
}

/// UIKit share sheet bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DarkCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "leaf.fill").font(.system(size: 28)).foregroundStyle(Palette.green)
                            Text("The Sesh")
                                .font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Palette.text)
                            Text("Your cannabis companion. Track your sessions, sesh together in Cyphers, go live, and chat with the community.")
                                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                            Text(BuildConfig.displayLabel)
                                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("CHANGELOG").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)

                    ForEach(AppChangelog.versions) { version in
                        DarkCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("v\(version.version)").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                                    if version.isLatest {
                                        Text("LATEST").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onGreen)
                                            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Palette.green))
                                    }
                                    Spacer()
                                    Text(version.buildLabel).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                }
                                ForEach(version.entries) { entry in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: entry.icon).font(.system(size: 14)).foregroundStyle(entry.tint).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                                            Text(entry.detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8)
                // Clear the home indicator / bottom safe area so the last card is
                // always fully visible and tappable when scrolled to the end.
                .padding(.bottom, 24)
            }
            // Pin the header above the scrolling content so it stays in place and
            // the back button is always reachable while the list scrolls beneath.
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader(title: "About The Sesh", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                    .background(AppBackground())
            }
            .scrollIndicators(.visible)
        }
    }
}
