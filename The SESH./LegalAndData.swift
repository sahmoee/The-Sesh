// LegalAndData.swift
// Studio-wide legal, business-details, age-confirmation and data-deletion surface.
// Additive: no app data model changes. Copy is identical across Sowens Studios apps; only the
// values in `StudioAppProfile` below differ. Canonical policy pages live at sowensstudios.com.

import SwiftUI
import Foundation
import Security
import UserNotifications
#if os(iOS)
import UIKit
#endif

// MARK: - Per-app values

enum StudioAppProfile {
    static let appName = "Sesh"
    /// App Group identifiers whose containers and defaults hold this app's data (widgets, watch).
    static let appGroups: [String] = ["group.com.sowens.The-SESH-"]
    /// Youngest age allowed to use the app. Confirmed once, on first launch.
    static let minimumAge = 21
    /// True only when the app itself sells something (drives the Refund Policy row).
    static let hasPurchases = false
    /// One sentence shown under the Legal & Data section.
    static let dataSummary = "Your sessions and notes stay on this device unless you turn on sync or community features. Sharing is off until you turn it on. We never sell your data or use it for advertising."
}

// MARK: - Constants and local erase

enum StudioLegal {
    static let company = "Sowens Studios"
    static let email = "support@sowensstudios.com"
    static let site = "https://sowensstudios.com"

    static func url(_ path: String) -> URL { URL(string: site + path) ?? URL(string: site)! }
    static var privacy: URL { url("/privacy/") }
    static var terms: URL { url("/terms/") }
    static var refunds: URL { url("/refunds/") }
    static var cookies: URL { url("/cookies/") }
    static var deleteData: URL { url("/delete-data/") }
    static var about: URL { url("/about/") }
    static var licenses: URL { url("/licenses/") }
    static var accessibility: URL { url("/accessibility/") }
    static var support: URL { url("/support/") }
    static var deletionMail: URL {
        URL(string: "mailto:\(email)?subject=Data%20deletion%20request%20-%20\(StudioAppProfile.appName.replacingOccurrences(of: " ", with: "%20"))")
            ?? URL(string: "mailto:\(email)")!
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    // MARK: Pending erase (runs before any store opens, at the next launch)

    private static let pendingKey = "studio.legal.pendingErase.v1"

    static var isErasePending: Bool { UserDefaults.standard.bool(forKey: pendingKey) }

    /// Marks all local data for deletion. Deletion happens at the next launch, before databases
    /// or stores are opened, so nothing is deleted from under an open file.
    static func requestErase() {
        UserDefaults.standard.set(true, forKey: pendingKey)
        UserDefaults.standard.synchronize()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func cancelErase() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.synchronize()
    }

    static func performPendingEraseIfNeeded(appGroups: [String] = StudioAppProfile.appGroups) {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }
        eraseNow(appGroups: appGroups)
    }

    static func eraseNow(appGroups: [String]) {
        let fm = FileManager.default
        var dirs: [URL] = []
        for d in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory, .cachesDirectory] {
            dirs += fm.urls(for: d, in: .userDomainMask)
        }
        dirs.append(fm.temporaryDirectory)
        for g in appGroups {
            if let u = fm.containerURL(forSecurityApplicationGroupIdentifier: g) { dirs.append(u) }
        }
        for dir in dirs {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? fm.removeItem(at: item) }
        }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        for g in appGroups { UserDefaults(suiteName: g)?.removePersistentDomain(forName: g) }
        let store = NSUbiquitousKeyValueStore.default
        for key in store.dictionaryRepresentation.keys { store.removeObject(forKey: key) }
        store.synchronize()
        let classes: [CFString] = [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassKey, kSecClassCertificate, kSecClassIdentity]
        for cls in classes {
            let query: [String: Any] = [kSecClass as String: cls, kSecAttrSynchronizable as String: kSecAttrSynchronizableAny as Any]
            SecItemDelete(query as CFDictionary)
        }
    }
}

// MARK: - Launcher (erases first, then starts the real App)

@main enum StudioLauncher {
    @MainActor static func main() {
        StudioLegal.performPendingEraseIfNeeded()
        SeshApp.main()
    }
}

// MARK: - Legal & Data section (drop into any List or Form)

struct LegalAndDataSection: View {
    var body: some View {
        Section {
            StudioLinkRow(title: "Privacy Policy", symbol: "hand.raised", url: StudioLegal.privacy)
            StudioLinkRow(title: "Terms of Service", symbol: "doc.text", url: StudioLegal.terms)
            if StudioAppProfile.hasPurchases {
                StudioLinkRow(title: "Refund Policy", symbol: "creditcard", url: StudioLegal.refunds)
            }
            StudioLinkRow(title: "Cookies & Tracking", symbol: "shield.lefthalf.filled", url: StudioLegal.cookies)
            StudioLinkRow(title: "Open-Source Licenses & Credits", symbol: "text.book.closed", url: StudioLegal.licenses)
            StudioLinkRow(title: "Accessibility Statement", symbol: "figure.stand", url: StudioLegal.accessibility)
            NavigationLink { StudioBusinessDetailsView() } label: {
                Label("About & Business Details", systemImage: "building.2")
            }
            NavigationLink { StudioDataRightsView() } label: {
                Label("Your Data & Deletion", systemImage: "trash")
            }
        } header: {
            Text("Legal & Data")
        } footer: {
            Text(StudioAppProfile.dataSummary)
        }
    }
}

struct StudioLinkRow: View {
    let title: String
    let symbol: String
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .accessibilityHint("Opens sowensstudios.com in your browser")
    }
}

/// Standalone version for apps whose settings are not a List (wrap in a sheet or NavigationLink).
struct LegalAndDataView: View {
    var body: some View {
        List { LegalAndDataSection() }
            .navigationTitle("Legal & Data")
    }
}

/// Button that opens the Legal & Data screen in a sheet. Use where settings are not a List.
struct LegalAndDataEntry<Label: View>: View {
    @State private var show = false
    let label: () -> Label
    init(@ViewBuilder label: @escaping () -> Label) { self.label = label }
    var body: some View {
        Button { show = true } label: { label() }
            .buttonStyle(.plain)
            .accessibilityHint("Opens legal, privacy and data deletion options")
            .sheet(isPresented: $show) {
                NavigationStack {
                    LegalAndDataView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { show = false }.keyboardShortcut(.defaultAction) } }
                }
            }
    }
}

// MARK: - Business details

struct StudioBusinessDetailsView: View {
    var body: some View {
        List {
            Section("Publisher") {
                detail("Business", StudioLegal.company)
                detail("Operated by", "Jessie Owens (App Store seller)")
                detail("App", StudioAppProfile.appName)
                detail("Version", StudioLegal.appVersion)
            }
            Section("Contact") {
                Link(destination: URL(string: "mailto:\(StudioLegal.email)")!) {
                    Label(StudioLegal.email, systemImage: "envelope")
                }
                .accessibilityHint("Opens your mail app")
                StudioLinkRow(title: "sowensstudios.com", symbol: "globe", url: URL(string: StudioLegal.site)!)
                StudioLinkRow(title: "Support form", symbol: "lifepreserver", url: StudioLegal.support)
            }
            Section {
                Text("Support replies within 5 business days. Privacy requests are answered within 30 days. A mailing address for legal notices is available on request at \(StudioLegal.email).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About & Business")
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Your data and deletion

struct StudioDataRightsView: View {
    @State private var confirmErase = false
    @State private var pending = StudioLegal.isErasePending

    var body: some View {
        List {
            Section {
                Text("You can delete your data at any time. There is no account to close and no reason to give.")
            }
            Section {
                if pending {
                    Label("Erase scheduled. Fully close \(StudioAppProfile.appName) (swipe it away in the app switcher) and open it again to finish.", systemImage: "clock.arrow.circlepath")
                    Button("Cancel scheduled erase") { StudioLegal.cancelErase(); pending = false }
                } else {
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label("Erase all data on this device…", systemImage: "trash")
                    }
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("Removes everything \(StudioAppProfile.appName) stored here: your content, settings, saved sign-ins and caches. It cannot be undone.")
            }
            Section {
                Text("Settings → your name → iCloud → Manage Account Storage → \(StudioAppProfile.appName) → Delete Data.")
                    .font(.callout)
            } header: { Text("In iCloud") } footer: {
                Text("If you turned on iCloud sync, a copy also lives in your iCloud account. Deleting the app does not remove it.")
            }
            Section {
                StudioLinkRow(title: "Request server data deletion", symbol: "person.crop.circle.badge.minus", url: StudioLegal.deleteData)
                Link(destination: StudioLegal.deletionMail) { Label("Email a deletion request", systemImage: "envelope") }
                    .accessibilityHint("Opens your mail app")
            } header: { Text("On our servers") } footer: {
                Text("If you used sync, sharing, tracking or support, we may hold records on our servers. We verify your request by email and delete within 30 days.")
            }
            Section("Other rights") {
                Text("You can also ask for a copy of your data, a correction, or to stop a kind of processing. Email \(StudioLegal.email). Nothing is sold and nothing is used for advertising.")
                    .font(.callout)
            }
        }
        .navigationTitle("Your Data")
        .confirmationDialog("Erase all \(StudioAppProfile.appName) data on this device?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) { StudioLegal.requestErase(); pending = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The erase finishes the next time you open the app.")
        }
    }
}

// MARK: - Age confirmation (first launch)

extension View {
    /// Shows a one-time neutral age confirmation. Nothing is stored except the confirmed minimum age.
    func studioAgeGate() -> some View { modifier(StudioAgeGate()) }
}

struct StudioAgeGate: ViewModifier {
    @AppStorage("studio.age.confirmed.v1") private var confirmedAge = 0
    @AppStorage("studio.age.blocked.v1") private var blocked = false

    private var bypass: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["STUDIO_SKIP_AGE_GATE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-StudioSkipAgeGate")
    }
    private var needsGate: Bool { !bypass && (blocked || confirmedAge < StudioAppProfile.minimumAge) }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: .constant(needsGate)) { gate }
        #else
        content.sheet(isPresented: .constant(needsGate)) { gate.frame(minWidth: 460, minHeight: 420).interactiveDismissDisabled() }
        #endif
    }

    private var gate: some View {
        let n = StudioAppProfile.minimumAge
        return VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "person.badge.shield.checkmark").font(.system(size: 52)).accessibilityHidden(true)
            Text(blocked ? "Not available" : "Before you start").font(.title.bold()).multilineTextAlignment(.center)
            if blocked {
                Text("\(StudioAppProfile.appName) is for people \(n) or older, so we can’t continue. A parent or guardian can contact \(StudioLegal.email) to ask us to delete any information.")
                    .multilineTextAlignment(.center)
            } else {
                Text("\(StudioAppProfile.appName) is for people \(n) or older. Please tell us which applies to you. We don’t ask for or store your birth date.")
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button { confirmedAge = n; blocked = false } label: {
                        Text("I am \(n) or older").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    Button { blocked = true } label: {
                        Text("I am under \(n)").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }
                Text("By continuing you agree to the [Terms](\(StudioLegal.terms.absoluteString)) and acknowledge the [Privacy Policy](\(StudioLegal.privacy.absoluteString)).")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
