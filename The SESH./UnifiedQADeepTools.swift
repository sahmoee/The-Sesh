import SwiftUI
import UIKit
import Combine

struct UnifiedQACheck: Identifiable, Codable, Hashable {
    let id: String
    let area: String
    let title: String
    let expected: String
}

enum UnifiedQAVerdict: String, Codable, CaseIterable {
    case untested, pass, fail, blocked
    var symbol: String {
        switch self { case .untested: "circle"; case .pass: "checkmark.circle.fill"; case .fail: "xmark.octagon.fill"; case .blocked: "exclamationmark.triangle.fill" }
    }
    var color: Color {
        switch self { case .untested: .secondary; case .pass: .green; case .fail: .red; case .blocked: .orange }
    }
}

struct UnifiedQACheckState: Codable {
    var verdict: UnifiedQAVerdict = .untested
    var note = ""
    var updatedAt = Date()
}

struct UnifiedQAProcess: Identifiable, Codable {
    var id = UUID()
    var name: String
    var startedAt = Date()
    var endedAt: Date?
    var status = "running"
    var detail = ""
}

struct UnifiedQARun: Identifiable, Codable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var passed = 0
    var failed = 0
    var blocked = 0
}

struct UnifiedQAFinding: Identifiable, Codable {
    var id = UUID()
    var severity: String
    var area: String
    var detail: String
    var createdAt = Date()
}

struct UnifiedQAProfile {
    let app: String
    let checks: [UnifiedQACheck]

    static func forApp(_ app: String) -> UnifiedQAProfile {
        switch app.lowercased() {
        case "nova": return .init(app: app, checks: nova)
        case "atlas": return .init(app: app, checks: atlas)
        default: return .init(app: app, checks: sesh)
        }
    }

    private static func item(_ id: String, _ area: String, _ title: String, _ expected: String) -> UnifiedQACheck {
        .init(id: id, area: area, title: title, expected: expected)
    }

    static let nova = [
        item("launch", "App", "Cold launch and resume", "Launches without a blank screen and restores the correct tab."),
        item("browse", "Browse", "Browse shelves", "Shelves load, scroll smoothly, and do not duplicate individual episodes."),
        item("search", "Browse", "Search and filters", "Movies and series resolve accurately and filters remain responsive."),
        item("detail", "Catalog", "Movie and series details", "Metadata, artwork, seasons, progress, and actions match the selected title."),
        item("episodes", "Catalog", "Episode grouping", "Episodes remain inside their series; only the most recently watched series entry appears elsewhere."),
        item("streams", "Playback", "Stream discovery", "Providers resolve, rank, retry, and explain unavailable sources."),
        item("player", "Playback", "Playback lifecycle", "Play, pause, seek, subtitles, progress, resume, and completion work."),
        item("external", "Playback", "External player return", "External playback launches safely and reconciles progress on return."),
        item("downloads", "Downloads", "Long-press download", "Long-pressing a movie or episode queues the correct item."),
        item("manager", "Downloads", "Download manager", "Pause, resume, retry, delete, storage, and offline playback remain consistent."),
        item("calendar", "Episodes", "Release calendar", "Only the newest available or release episode is surfaced."),
        item("notify", "Episodes", "Episode notifications", "Only the newest episode creates a notification and duplicates are suppressed."),
        item("library", "My Nova", "Library identity", "Watch progress and identity deduplicate across sources."),
        item("smb", "My Nova", "SMB folder browser", "Authentication, browsing, selection, reconnect, and library ingestion work."),
        item("trakt", "Tracking", "Trakt sync", "Authentication, expiry, watch state, ratings, and retries reconcile."),
        item("simkl", "Tracking", "SIMKL sync", "PIN login, token persistence, lists, watched state, and errors work."),
        item("tmdb", "Tracking", "TMDB account", "Account connection and list actions give visible success or failure."),
        item("addons", "Sources", "Addon management", "Install, configure, health, ordering, and removal work."),
        item("debrid", "Sources", "Real-Debrid", "Login, validation, expiry, resolution, and clear errors work."),
        item("direct", "Sources", "Direct URL and magnet", "Legal gate, validation, routing, and failures work."),
        item("accessibility", "UI", "Accessibility", "Labels, focus order, Dynamic Type, contrast, and 44-point targets pass."),
        item("network", "Reliability", "Offline and recovery", "Offline state is clear and pending work retries once."),
        item("memory", "Reliability", "Long-session resources", "Memory stays bounded and background/foreground does not leak playback."),
        item("privacy", "Security", "Credentials and reports", "Secrets stay in Keychain and QA evidence contains no secret values."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]

    static let atlas = [
        item("launch", "App", "Cold launch and resume", "Atlas launches, restores navigation, and preserves unfinished work."),
        item("browse", "Guides", "Browse map and categories", "All categories, shelves, filters, and recent guides route correctly."),
        item("search", "Guides", "Search ranking", "Titles, steps, tags, synonyms, and safety content rank predictably."),
        item("guide", "Guides", "Guide details", "Steps, tools, time, difficulty, tips, and safety notes remain complete."),
        item("progress", "Guides", "Step progress", "Step completion, undo, overall completion, and resume persist."),
        item("save", "Library", "Save, pin, and recent", "Saved, pinned, and recently viewed guides deduplicate and persist."),
        item("collections", "Library", "Collections", "Create, rename, add, remove, and delete preserve guide identity."),
        item("ask", "AI Guides", "Ask Atlas generation", "Requests validate, queue offline, generate complete guides, and explain errors."),
        item("policy", "AI Guides", "Safety and content policy", "Unsafe requests are refused while legitimate safety guidance remains useful."),
        item("documents", "Documents", "Create and edit documents", "Capture, OCR, generation, editing, history, and export work."),
        item("scanner", "Documents", "Camera and document scanning", "Permission, cancellation, multi-page scans, and failures recover."),
        item("export", "Documents", "Document export", "Share and export produce readable, complete artifacts."),
        item("history", "Account", "History and reset", "History displays accurately and reset removes only documented user data."),
        item("streak", "Progress", "Streak and freezes", "Day boundaries, freezes, longest streak, and timezone changes are correct."),
        item("milestones", "Progress", "Milestones", "Each milestone earns once, celebrates once, and remains visible."),
        item("profile", "Account", "Profile and appearance", "Profile, theme, text size, and identity persist."),
        item("backup", "Account", "iCloud backup and restore", "Merges do not lose or duplicate saves, progress, notes, or documents."),
        item("catalog", "Content", "Catalog integrity", "Every guide has unique identity, valid category, ordered steps, and safety metadata."),
        item("remote", "Content", "Remote catalog", "Signing, replacement, fallback, and bundled-content recovery work."),
        item("offline", "Reliability", "Offline request queue", "Queued requests remain visible and retry exactly once when online."),
        item("widgets", "Extensions", "Widgets and activities", "Widget and Live Activity state reflects the app and handles stale data."),
        item("accessibility", "UI", "Accessibility", "VoiceOver, focus, Dynamic Type, contrast, and touch targets pass."),
        item("performance", "Reliability", "Large library performance", "Browse, search, and document history stay responsive."),
        item("privacy", "Security", "Private content", "Documents, photos, notes, credentials, and QA evidence remain private."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]

    static let sesh = [
        item("launch", "App", "Cold launch and resume", "Sesh launches and restores the correct tab and active session."),
        item("onboarding", "Profile", "Onboarding and profile", "Profile, theme, consent, and account state persist correctly."),
        item("log", "Sessions", "Log a sesh", "Strain, method, mood, effects, duration, rating, price, photo, and notes save."),
        item("live", "Sessions", "Live session lifecycle", "Start, update, background, resume, end, and discard are consistent."),
        item("multi", "Sessions", "Multi-strain sessions", "Primary and additional strains remain unique and stats use the documented primary."),
        item("journal", "Journal", "Journal and thoughts", "Entries sort, filter, edit, delete, search, and retain photos."),
        item("strains", "Strains", "Strain library", "Search, aliases, type, effects, potency, family tree, and similar strains work."),
        item("custom", "Strains", "Custom strains", "Create, edit, photo, match, merge, and delete do not corrupt history."),
        item("favorites", "Strains", "Favorites and wishlist", "Favorite and wishlist states remain distinct and persistent."),
        item("insights", "Insights", "Personal strain insights", "Counts, averages, effects, recommendations, and recency use valid sessions."),
        item("stats", "Insights", "Stats and trends", "Week, streak, spend, rating, tolerance, and recap calculations are correct."),
        item("stash", "Stash", "Stash inventory", "Purchases, quantities, costs, consumption, goals, and forecast reconcile."),
        item("goals", "Stash", "Goals and tolerance", "Targets, progress, reminders, breaks, and edits remain consistent."),
        item("music", "Music", "Music and playlists", "Search, memory, playlist, Apple Music export, and strain association work."),
        item("community", "Community", "Lounge feed", "Posts, replies, reactions, reporting, pagination, and offline errors work."),
        item("cyph", "Community", "Cyphs and live chat", "Create, join, invite, message, presence, and exit work without duplicate rooms."),
        item("friends", "Community", "Friends and privacy", "Requests, block, visibility, identity, and private content rules work."),
        item("notifications", "System", "Notifications", "Permission, scheduling, deep links, deduplication, and cancellation work."),
        item("widget", "System", "Widget and Live Activity", "Streak, last strain, stash, and live state stay current."),
        item("icloud", "Sync", "iCloud backup and restore", "Sessions, thoughts, profile, and settings merge without loss or duplication."),
        item("worker", "Sync", "Unified Worker", "Authentication, outbox, retries, conflicts, and server errors are visible."),
        item("offline", "Reliability", "Offline and recovery", "Queued social operations retry once and local tracking remains usable."),
        item("accessibility", "UI", "Accessibility", "VoiceOver, Dynamic Type, contrast, reduced motion, and touch targets pass."),
        item("privacy", "Security", "Sensitive health and social data", "Exports, logs, tickets, photos, and credentials avoid unintended disclosure."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]
}

@MainActor
final class UnifiedQADeepStore: ObservableObject {
    @Published var states: [String: UnifiedQACheckState] = [:]
    @Published var processes: [UnifiedQAProcess] = []
    @Published var runs: [UnifiedQARun] = []
    @Published var findings: [UnifiedQAFinding] = []
    @Published var hudVisible = false

    private var app = ""
    private var timer: Timer?

    func configure(app: String) {
        guard self.app != app else { return }
        self.app = app
        load()
        startBackgroundChecks()
    }

    func state(for check: UnifiedQACheck) -> UnifiedQACheckState { states[check.id] ?? .init() }

    func set(_ check: UnifiedQACheck, verdict: UnifiedQAVerdict, note: String = "") {
        states[check.id] = .init(verdict: verdict, note: note, updatedAt: Date())
        persist()
    }

    func startRun() {
        runs.insert(.init(), at: 0)
        if runs.count > 50 { runs.removeLast(runs.count - 50) }
        persist()
    }

    func finishRun() {
        guard let index = runs.firstIndex(where: { $0.endedAt == nil }) else { return }
        let values = states.values
        runs[index].endedAt = Date()
        runs[index].passed = values.filter { $0.verdict == .pass }.count
        runs[index].failed = values.filter { $0.verdict == .fail }.count
        runs[index].blocked = values.filter { $0.verdict == .blocked }.count
        persist()
    }

    func startProcess(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        processes.insert(.init(name: name), at: 0)
        trimAndPersist()
    }

    func finishProcess(_ id: UUID, failed: Bool) {
        guard let index = processes.firstIndex(where: { $0.id == id }) else { return }
        processes[index].endedAt = Date()
        processes[index].status = failed ? "failed" : "passed"
        trimAndPersist()
    }

    func runAutomaticChecks(ticketCount: Int, unsyncedCount: Int, memoryMB: Int, hitchMS: Int) {
        var next: [UnifiedQAFinding] = []
        if unsyncedCount > 0 { next.append(.init(severity: "major", area: "Sync", detail: "\(unsyncedCount) ticket(s) are waiting to sync.")) }
        if memoryMB >= 750 { next.append(.init(severity: "major", area: "Memory", detail: "Resident memory is \(memoryMB) MB.")) }
        if hitchMS >= 1_500 { next.append(.init(severity: "blocker", area: "Performance", detail: "Main thread stalled for \(hitchMS) ms.")) }
        if processes.contains(where: { $0.status == "running" && Date().timeIntervalSince($0.startedAt) > 120 }) {
            next.append(.init(severity: "major", area: "Process", detail: "A tracked process has remained unresolved for over two minutes."))
        }
        let failedChecks = states.values.filter { $0.verdict == .fail }.count
        if failedChecks > 0 { next.append(.init(severity: "major", area: "Checklist", detail: "\(failedChecks) app-specific check(s) are failing.")) }
        findings = next
        persist()
    }

    func resetChecklist() { states = [:]; persist() }

    private func startBackgroundChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.runAutomaticChecks(ticketCount: 0, unsyncedCount: 0, memoryMB: 0, hitchMS: 0)
            }
        }
    }

    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UnifiedQADeep-\(app).json")
    }

    private struct Snapshot: Codable {
        var states: [String: UnifiedQACheckState]
        var processes: [UnifiedQAProcess]
        var runs: [UnifiedQARun]
        var findings: [UnifiedQAFinding]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        states = value.states; processes = value.processes; runs = value.runs; findings = value.findings
    }

    private func trimAndPersist() {
        if processes.count > 100 { processes.removeLast(processes.count - 100) }
        persist()
    }

    private func persist() {
        let value = Snapshot(states: states, processes: processes, runs: runs, findings: findings)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
    }
}

struct UnifiedQADeepView: View {
    let app: String
    let tickets: [UnifiedQATicket]
    let unsyncedCount: Int
    let memoryMB: Int
    let hitchMS: Int

    @StateObject private var store = UnifiedQADeepStore()
    @State private var search = ""
    @State private var processName = ""

    private var profile: UnifiedQAProfile { .forApp(app) }
    private var filteredChecks: [UnifiedQACheck] {
        guard !search.isEmpty else { return profile.checks }
        return profile.checks.filter { ($0.area + " " + $0.title + " " + $0.expected).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section("Autonomous findings") {
                if store.findings.isEmpty { Label("No current automatic findings", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                ForEach(store.findings) { finding in
                    VStack(alignment: .leading) {
                        Text(finding.area + " · " + finding.severity.capitalized).font(.caption.bold()).foregroundStyle(finding.severity == "blocker" ? .red : .orange)
                        Text(finding.detail)
                    }
                }
                Button("Run all automatic checks") { store.runAutomaticChecks(ticketCount: tickets.count, unsyncedCount: unsyncedCount, memoryMB: memoryMB, hitchMS: hitchMS) }
            }

            Section("App-specific checklist") {
                TextField("Search checks and evidence", text: $search)
                ForEach(Dictionary(grouping: filteredChecks, by: \.area).keys.sorted(), id: \.self) { area in
                    DisclosureGroup(area) {
                        ForEach(filteredChecks.filter { $0.area == area }) { check in
                            NavigationLink { checkDetail(check) } label: {
                                Label(check.title, systemImage: store.state(for: check).verdict.symbol)
                                    .foregroundStyle(store.state(for: check).verdict.color)
                            }
                        }
                    }
                }
                Button("Reset checklist", role: .destructive) { store.resetChecklist() }
            }

            Section("Tracked processes") {
                HStack { TextField("Process or action", text: $processName); Button("Start") { store.startProcess(processName); processName = "" } }
                ForEach(store.processes.prefix(20)) { process in
                    VStack(alignment: .leading) {
                        HStack { Text(process.name); Spacer(); Text(process.status.capitalized).font(.caption) }
                        if process.status == "running" {
                            HStack { Button("Pass") { store.finishProcess(process.id, failed: false) }; Button("Fail", role: .destructive) { store.finishProcess(process.id, failed: true) } }
                        }
                    }
                }
            }

            Section("QA runs") {
                HStack { Button("Start run") { store.startRun() }; Button("Finish active run") { store.finishRun() } }
                ForEach(store.runs.prefix(12)) { run in
                    Text("\(run.startedAt.formatted()) · \(run.endedAt == nil ? "running" : "\(run.passed) pass, \(run.failed) fail, \(run.blocked) blocked")").font(.caption)
                }
            }

            Section("Duplicate and recurring tickets") {
                let groups = recurring
                if groups.isEmpty { Text("No likely recurring ticket titles.").foregroundStyle(.secondary) }
                ForEach(groups, id: \.key) { group in Text("\(group.value.count)× \(group.value.first?.title ?? group.key)") }
            }

            Section("Full environment") {
                LabeledContent("App", value: app)
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("Device", value: UIDevice.current.model)
                LabeledContent("Memory", value: "\(memoryMB) MB")
                LabeledContent("Longest hang", value: "\(hitchMS) ms")
                LabeledContent("Pending ticket sync", value: "\(unsyncedCount)")
                LabeledContent("Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
                LabeledContent("Thermal", value: String(describing: ProcessInfo.processInfo.thermalState))
                Button("Copy diagnostics") { UIPasteboard.general.string = diagnosticsText }
            }
        }
        .navigationTitle("\(app) QA Lab")
        .onAppear {
            store.configure(app: app)
            store.runAutomaticChecks(ticketCount: tickets.count, unsyncedCount: unsyncedCount, memoryMB: memoryMB, hitchMS: hitchMS)
        }
    }

    @ViewBuilder private func checkDetail(_ check: UnifiedQACheck) -> some View {
        Form {
            Section(check.title) { Text(check.expected) }
            Section("Verdict") {
                ForEach(UnifiedQAVerdict.allCases, id: \.self) { verdict in
                    Button { store.set(check, verdict: verdict) } label: {
                        Label(verdict.rawValue.capitalized, systemImage: verdict.symbol).foregroundStyle(verdict.color)
                    }
                }
            }
            if !store.state(for: check).note.isEmpty { Section("Evidence note") { Text(store.state(for: check).note) } }
        }.navigationTitle(check.area)
    }

    private var recurring: [(key: String, value: [UnifiedQATicket])] {
        let groups = Dictionary(grouping: tickets) { ticket in
            ticket.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(5).joined(separator: " ")
        }
        return groups.filter { $0.value.count > 1 }.sorted { $0.value.count > $1.value.count }
    }

    private var diagnosticsText: String {
        """
        \(app) QA diagnostics
        Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        Memory: \(memoryMB) MB
        Longest hang: \(hitchMS) ms
        Tickets: \(tickets.count), pending sync: \(unsyncedCount)
        Checks: \(profile.checks.count)
        """
    }
}
