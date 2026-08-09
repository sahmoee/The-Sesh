//
//  SafetyAndPrivacy.swift
//  The SESH
//
//  Batch 3 — (#App16) granular privacy controls, (#App17) moderation UX,
//  (#App18) age gate + responsible-use safeguards.
//
//  One file so it can be added to the Xcode target in one step. Contains:
//    - PrivacySettings   per-field sharing toggles, persisted; consulted by
//                        SocialStore before anything leaves the device
//    - AgeGate + AgeGateView   21+ confirmation on first launch
//    - SafetySettingsView      responsible-use info + configurable reminders
//    - PrivacySettingsView     the App16 toggles
//    - PrivacySafetyHubView    entry point linked from Profile settings
//    - CommunityRulesView      visible community rules (App17)
//    - ReportSheet             categorised reporting (App17)
//    - blockConfirmation(...)  confirm-before-block modifier (App17)
//

import SwiftUI
import UserNotifications

// MARK: - Privacy settings (#App16)

/// What the user shares with friends. Everything defaults to ON (current
/// behaviour) except thoughts, which were already visibility-scoped. Stores
/// read these BEFORE broadcasting; they are enforcement, not decoration.
@MainActor
@Observable
final class PrivacySettings {
    static let shared = PrivacySettings()

    var shareActivity: Bool      { didSet { save() } }   // status / presence
    var shareStrainDetails: Bool { didSet { save() } }   // strain names in events
    var shareMusic: Bool         { didSet { save() } }   // now-playing
    var shareSessionDuration: Bool { didSet { save() } } // timer details in status
    var shareLiveStatus: Bool    { didSet { save() } }   // "went live" broadcasts
    var discoverableByCode: Bool { didSet { save() } }   // friend-code lookup

    private static let key = "sesh.privacy.v1"

    private init() {
        let d = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        shareActivity        = d["activity"] ?? true
        shareStrainDetails   = d["strain"] ?? true
        shareMusic           = d["music"] ?? true
        shareSessionDuration = d["duration"] ?? true
        shareLiveStatus      = d["live"] ?? true
        discoverableByCode   = d["discoverable"] ?? true
    }

    private func save() {
        UserDefaults.standard.set([
            "activity": shareActivity, "strain": shareStrainDetails,
            "music": shareMusic, "duration": shareSessionDuration,
            "live": shareLiveStatus, "discoverable": discoverableByCode,
        ], forKey: Self.key)
    }
}

// MARK: - Age gate (#App18)

enum AgeGate {
    private static let key = "sesh.agegate.confirmed.v1"
    static var isConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct AgeGateView: View {
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 56)).foregroundStyle(Palette.green)
                Text("Before you roll in")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.text).padding(.top, 18)
                Text("The SESH is for adults of legal age in a place where cannabis is legal.")
                    .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    safetyRow("checkmark.shield", "I'm 21 or older (or of legal age where I live).")
                    safetyRow("car.fill", "I won't drive or operate machinery while impaired.")
                    safetyRow("lock.fill", "My journal stays private unless I choose to share.")
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                .padding(.horizontal, 24).padding(.top, 24)

                Spacer()

                Button {
                    AgeGate.isConfirmed = true
                    Haptics.success()
                    onConfirm()
                } label: {
                    Text("I confirm — enter The SESH")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Text("Nothing here is medical advice. Sesh responsibly.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    .padding(.top, 12).padding(.bottom, 28)
            }
        }
        .interactiveDismissDisabled()
    }

    private func safetyRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.greenBright).frame(width: 22)
            Text(text).font(.system(size: 14)).foregroundStyle(Palette.text)
        }
    }
}

// MARK: - Consumption reminders (#App18)

/// User-controlled check-in reminder during long sessions. Purely opt-in and
/// framed around hydration/awareness — no medical claims.
@MainActor
enum SeshReminders {
    private static let intervalKey = "sesh.reminder.interval.v1"   // minutes; 0 = off
    static let options = [0, 30, 60, 90, 120]

    static var intervalMinutes: Int {
        get { UserDefaults.standard.integer(forKey: intervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: intervalKey) }
    }

    /// Schedule a repeating check-in while a sesh is live. Call on sesh start.
    static func scheduleForActiveSesh() {
        cancel()
        let minutes = intervalMinutes
        guard minutes > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Check-in 💧"
        content.body = "Still seshing? Grab some water and see how you're feeling."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60), repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "sesh.checkin", content: content, trigger: trigger))
    }

    /// Cancel on sesh end.
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["sesh.checkin"])
    }
}

// MARK: - Hub linked from Profile settings

struct PrivacySafetyHubView: View {
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Privacy & Safety")

                    hubLink("hand.raised.fill", "Sharing & Privacy",
                            "Control what friends can see") { PrivacySettingsView() }
                    hubLink("heart.text.square.fill", "Responsible Use",
                            "Check-in reminders & guidance") { SafetySettingsView() }
                    hubLink("text.book.closed.fill", "Community Rules",
                            "What's OK in Cyphers and chat") { CommunityRulesView() }
                    hubLink("doc.text.fill", "Policies & Support",
                            "Privacy, license, and help") { SeshLegalLinksView() }
                }
                .padding(16)
            }
        }
        .navigationTitle("Privacy & Safety")
    }

    private func hubLink<Dest: View>(_ symbol: String, _ title: String, _ subtitle: String,
                                     @ViewBuilder dest: @escaping () -> Dest) -> some View {
        NavigationLink {
            dest().navigationBarBackButtonHidden(true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16)).foregroundStyle(Palette.greenBright).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Privacy toggles screen (#App16)

struct PrivacySettingsView: View {
    @State private var privacy = PrivacySettings.shared

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "What friends can see")
                    Group {
                        privacyToggle("dot.radiowaves.left.and.right", "Activity & status",
                                      "Rolling up, smoking, vibing…", $privacy.shareActivity)
                        privacyToggle("leaf.fill", "Strain details",
                                      "Strain names in your status and events", $privacy.shareStrainDetails)
                        privacyToggle("music.note", "Now playing",
                                      "The song you're listening to", $privacy.shareMusic)
                        privacyToggle("timer", "Session duration",
                                      "How long you've been seshing", $privacy.shareSessionDuration)
                        privacyToggle("dot.circle.and.hand.point.up.left.fill", "Live status",
                                      "\"Went live\" alerts to friends", $privacy.shareLiveStatus)
                        privacyToggle("qrcode", "Discoverable by friend code",
                                      "People with your code can add you", $privacy.discoverableByCode)
                    }
                    Text("Changes apply from your next status update. Your journal, stash, and insights are always private.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .navigationTitle("Sharing & Privacy")
    }

    private func privacyToggle(_ symbol: String, _ title: String, _ subtitle: String,
                               _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15)).foregroundStyle(Palette.greenBright).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .tint(Palette.green)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Responsible use (#App18)

struct SafetySettingsView: View {
    @State private var interval = SeshReminders.intervalMinutes

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Check-in reminders")
                    Text("During a sesh, get a gentle nudge to drink water and check how you're feeling.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)

                    Picker("Remind me", selection: $interval) {
                        Text("Off").tag(0)
                        ForEach(SeshReminders.options.dropFirst(), id: \.self) { m in
                            Text("Every \(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: interval) { _, newValue in
                        SeshReminders.intervalMinutes = newValue
                        Haptics.selection()
                    }

                    Divider().overlay(Palette.stroke).padding(.vertical, 8)

                    FieldLabel(text: "Sesh responsibly")
                    Group {
                        infoRow("car.fill", "Never drive or operate machinery while impaired. Plan a ride before you spark.")
                        infoRow("clock.fill", "Edibles can take 1–2 hours to peak. Start low, go slow.")
                        infoRow("drop.fill", "Hydrate. Dry mouth is real; water fixes more than you'd think.")
                        infoRow("person.2.fill", "If you feel too high: you're not in danger, it passes. Sit down, breathe, and stay with a friend.")
                        infoRow("lock.shield.fill", "Keep your stash away from kids and pets, and out of sight while traveling.")
                    }
                    Text("This is general guidance, not medical advice.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary).padding(.top, 4)
                }
                .padding(16)
            }
        }
        .navigationTitle("Responsible Use")
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15)).foregroundStyle(Palette.greenBright).frame(width: 24)
            Text(text).font(.system(size: 14)).foregroundStyle(Palette.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Community rules (#App17)

struct CommunityRulesView: View {
    private static let appealsURL = URL(string: "mailto:appeals@thesesh.app?subject=Moderation%20appeal")

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "The house rules")
                    Group {
                        rule("1", "Adults only. Anyone appearing underage is removed and reported.")
                        rule("2", "No buying, selling, or sourcing. The SESH is for tracking and hanging out — not transactions.")
                        rule("3", "Be cool. No harassment, hate, threats, or dogpiling. Blocking is one tap and we act on reports.")
                        rule("4", "No pressuring anyone to consume, and no glorifying dangerous use.")
                        rule("5", "Keep other people's info private. No doxxing, no screenshots of private rooms.")
                    }
                    FieldLabel(text: "Enforcement").padding(.top, 8)
                    Text("Reports are reviewed against these rules. Repeated or severe violations remove access to Community features. If you believe a decision was wrong, contact us and we'll take a second look.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    if let appealsURL = Self.appealsURL {
                        Link(destination: appealsURL) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14)).foregroundStyle(Palette.greenBright)
                                Text("Contact / appeal a decision")
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Community Rules")
    }

    private func rule(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.greenBright)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.field))
            Text(text).font(.system(size: 14)).foregroundStyle(Palette.text)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Report sheet (#App17)

enum ReportCategory: String, CaseIterable, Identifiable {
    case harassment = "Harassment or hate"
    case underage = "Possibly underage"
    case selling = "Buying / selling"
    case spam = "Spam"
    case dangerous = "Encouraging dangerous use"
    case other = "Something else"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .harassment: return "exclamationmark.bubble.fill"
        case .underage:   return "person.crop.circle.badge.exclamationmark"
        case .selling:    return "dollarsign.circle.fill"
        case .spam:       return "envelope.badge.fill"
        case .dangerous:  return "flame.fill"
        case .other:      return "ellipsis.circle.fill"
        }
    }
}

/// Categorised report flow. Present as a sheet; sends "category: details" as
/// the reason so moderation can triage without parsing free text.
struct ReportSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss

    var user: SeshUser? = nil
    var messageID: String? = nil

    @State private var category: ReportCategory? = nil
    @State private var details = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if sent {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 40)).foregroundStyle(Palette.green)
                                Text("Report received").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                                Text("Thanks for keeping the community safe. We review reports against the community rules.")
                                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            FieldLabel(text: "What's going on?")
                            ForEach(ReportCategory.allCases) { c in
                                Button {
                                    category = c; Haptics.selection()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: c.symbol)
                                            .font(.system(size: 15)).foregroundStyle(Palette.greenBright).frame(width: 24)
                                        Text(c.rawValue).font(.system(size: 15)).foregroundStyle(Palette.text)
                                        Spacer()
                                        if category == c {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16)).foregroundStyle(Palette.green)
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .stroke(category == c ? Palette.green : Palette.stroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }

                            FieldLabel(text: "Details (optional)").padding(.top, 8)
                            TextField("Anything that helps us review this…", text: $details, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                .foregroundStyle(Palette.text)

                            Button {
                                guard let category, !sending else { return }
                                sending = true
                                let reason = "\(category.rawValue): \(details.trimmingCharacters(in: .whitespacesAndNewlines))"
                                Task {
                                    _ = await social.report(user: user, messageID: messageID, reason: reason)
                                    sending = false
                                    sent = true
                                    Haptics.success()
                                }
                            } label: {
                                Text(sending ? "Sending…" : "Send report")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .fill(category == nil ? Palette.field : Palette.green))
                                    .foregroundStyle(category == nil ? Palette.textTertiary : .white)
                            }
                            .buttonStyle(.plain)
                            .disabled(category == nil || sending)
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(user.map { "Report \($0.displayName)" } ?? "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Block confirmation (#App17)

extension View {
    /// Confirm-before-block. Blocking also unfriends both ways (server-side).
    func blockConfirmation(user: SeshUser?, isPresented: Binding<Bool>,
                           social: SocialStore) -> some View {
        confirmationDialog(
            "Block \(user?.displayName ?? "this person")?",
            isPresented: isPresented, titleVisibility: .visible
        ) {
            Button("Block & remove friend", role: .destructive) {
                guard let user else { return }
                Task { await social.block(user) }
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to see your activity or message you, and you'll stop seeing theirs. They aren't notified.")
        }
    }
}
