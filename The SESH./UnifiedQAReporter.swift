import SwiftUI
import UIKit
import Combine

enum UnifiedQASettings {
    static let enabledKey = "sesh.qa.enabled"
    static let touchesKey = "sesh.qa.touches"
}

struct UnifiedQASettingsView: View {
    @AppStorage(UnifiedQASettings.enabledKey) private var enabled = false
    @AppStorage(UnifiedQASettings.touchesKey) private var touches = true
    @AppStorage(UnifiedQAPasscode.unlockedUntilKey) private var unlockedUntil = 0.0
    @State private var code = ""
    @State private var wrongCode = false
    private var unlocked: Bool { unlockedUntil > Date().timeIntervalSinceReferenceDate }
    var body: some View {
        VStack(alignment: .leading) {
            if unlocked { Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Sesh QA")
                    Text("Session, journal, social, music, screenshot, ticket, and fix-verification reporting.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } } else {
                SecureField("QA passcode", text: $code).textFieldStyle(.roundedBorder)
                if wrongCode { Text("Incorrect passcode").font(.caption).foregroundStyle(.red) }
                Button("Unlock QA") { wrongCode = !UnifiedQAPasscode.unlock(code); code = ""; unlockedUntil = UserDefaults.standard.double(forKey: UnifiedQAPasscode.unlockedUntilKey) }
            }
            if unlocked && enabled { Toggle("Record anonymous touch positions", isOn: $touches).font(.caption) }
        }
        .onAppear { if !unlocked { enabled = false } }
    }
}

struct UnifiedQATicket: Codable, Identifiable {
    var id = UUID()
    var number: String
    var title: String
    var body: String
    var severity: String
    var status = "open"
    var createdAt = Date()
    var updatedAt = Date()
    var screen: String
    var hasScreenshot: Bool
    var environment: [String: String]
    var resolution: String?
    var verifiedAt: Date?
    var refileCount: Int?
    var requiresManualReview: Bool?
}

@MainActor final class UnifiedQAStore: ObservableObject {
    static let shared = UnifiedQAStore()
    @Published private(set) var tickets: [UnifiedQATicket] = []
    @Published var syncMessage = ""
    private let base = URL(string: "https://api.sowensstudios.com/_unified/qa")!

    private init() { load() }

    func save(app: String, source: String, prefix: String, ticket: UnifiedQATicket?, title: String,
              details: String, severity: String, screen: String, status: String, resolution: String,
              requiresManualReview: Bool) {
        let shot = Self.capture()
        var value = ticket ?? UnifiedQATicket(number: nextNumber(prefix: prefix), title: title,
            body: details, severity: severity, screen: screen, hasScreenshot: shot != nil,
            environment: Self.environment(app: app), resolution: nil, verifiedAt: nil, refileCount: nil)
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        value.severity = severity
        value.screen = screen
        value.status = status
        value.resolution = resolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : resolution
        value.requiresManualReview = requiresManualReview
        value.updatedAt = Date()
        value.hasScreenshot = value.hasScreenshot || shot != nil
        if let index = tickets.firstIndex(where: { $0.id == value.id }) { tickets[index] = value }
        else { tickets.insert(value, at: 0) }
        persist(ticket: value, screenshot: shot)
        Task { await sync(value, source: source) }
    }

    func retryAll(source: String) { Task { await syncAll(source: source) } }

    private func syncAll(source: String) async {
        await pull(source: source)
        for ticket in tickets { await sync(ticket, source: source) }
    }

    private func pull(source: String) async {
        guard UnifiedQAPasscode.isUnlocked else { return }
        do {
            var components = URLComponents(url: base.appendingPathComponent("tickets/sync"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "source", value: source), URLQueryItem(name: "limit", value: "1000")]
            var request = URLRequest(url: components.url!); request.httpMethod = "POST"; request.setValue("Joo", forHTTPHeaderField: "X-QA-Passcode")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let values = try JSONSerialization.data(withJSONObject: object?["tickets"] as? [[String: Any]] ?? [])
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let remote = try decoder.decode([UnifiedQATicket].self, from: values)
            var byNumber = Dictionary(uniqueKeysWithValues: tickets.map { ($0.number, $0) })
            for ticket in remote where ticket.updatedAt >= (byNumber[ticket.number]?.updatedAt ?? .distantPast) { byNumber[ticket.number] = ticket }
            tickets = byNumber.values.sorted { $0.updatedAt > $1.updatedAt }
            for ticket in remote { persist(ticket: ticket, screenshot: nil) }
            saveIndex(); syncMessage = "Loaded \(remote.count) cross-device ticket(s)"
        } catch { syncMessage = "Saved locally · device sync will retry" }
    }

    func verify(_ ticket: UnifiedQATicket, source: String) {
        var value = ticket; value.status = "verified"; value.verifiedAt = Date(); value.updatedAt = Date()
        replaceAndSync(value, source: source)
    }

    func refile(_ ticket: UnifiedQATicket, source: String) {
        var value = ticket; value.status = "open"; value.verifiedAt = nil
        value.refileCount = (value.refileCount ?? 0) + 1; value.updatedAt = Date()
        value.body += "\n\nRefiled after fix verification on \(Date().formatted())."
        replaceAndSync(value, source: source)
    }

    private func replaceAndSync(_ ticket: UnifiedQATicket, source: String) {
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) { tickets[index] = ticket }
        persist(ticket: ticket, screenshot: nil); Task { await sync(ticket, source: source) }
    }

    private func nextNumber(prefix: String) -> String {
        let key = "unifiedQA.counter.\(prefix)"
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(prefix)-\(build)-\(String(format: "%04d", next))"
    }

    private var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("QAReports", isDirectory: true)
    }

    private func persist(ticket: UnifiedQATicket, screenshot: UIImage?) {
        let folder = root.appendingPathComponent(ticket.number, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(ticket) { try? data.write(to: folder.appendingPathComponent("ticket.json"), options: .atomic) }
        let fixed = ticket.resolution.map { "\n## What was fixed\n\n\($0)\n" } ?? ""
        let review = ticket.requiresManualReview == true ? "\n> **REQUIRES MANUAL REVIEW:** Ask the tester for specifics before changing code.\n" : ""
        let report = "# \(ticket.number) — \(ticket.title)\n\n**\(ticket.severity)** · \(ticket.status)\n\n## Report\n\n\(ticket.body)\n\(fixed)\n## Context\n\n- Screen: \(ticket.screen)\n- App: \(ticket.environment["appVersion"] ?? "?") build \(ticket.environment["build"] ?? "?")\n- Device: \(ticket.environment["device"] ?? "?") · \(ticket.environment["os"] ?? "?")\n"
        try? Data(report.utf8).write(to: folder.appendingPathComponent("report.md"), options: .atomic)
        if let data = screenshot?.jpegData(compressionQuality: 0.72) { try? data.write(to: folder.appendingPathComponent("screenshot.jpg"), options: .atomic) }
        saveIndex()
    }

    private func saveIndex() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tickets) { try? data.write(to: root.appendingPathComponent("tickets.json"), options: .atomic) }
    }

    private func load() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: root.appendingPathComponent("tickets.json")), let values = try? decoder.decode([UnifiedQATicket].self, from: data) { tickets = values }
    }

    private func sync(_ ticket: UnifiedQATicket, source: String) async {
        do {
            let shotURL = root.appendingPathComponent(ticket.number).appendingPathComponent("screenshot.jpg")
            if ticket.hasScreenshot, let data = try? Data(contentsOf: shotURL) {
                var request = URLRequest(url: base.appendingPathComponent("shots").appending(queryItems: [URLQueryItem(name: "ticket", value: ticket.number), URLQueryItem(name: "kind", value: "screenshot")]))
                request.httpMethod = "POST"; request.httpBody = data; request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let ticketObject = try JSONSerialization.jsonObject(with: encoder.encode(ticket))
            let envelope: [String: Any] = ["schema": "stocked-qa-report/v1", "source": source, "kind": "tickets", "generatedAt": ISO8601DateFormatter().string(from: Date()), "tickets": [ticketObject]]
            var request = URLRequest(url: base.appendingPathComponent("reports")); request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: envelope); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
            syncMessage = "\(ticket.number) synced"
        } catch { syncMessage = "Saved locally · sync will retry" }
    }

    private static func environment(app: String) -> [String: String] {
        var value = ["app": app, "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
         "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
         "device": UIDevice.current.model, "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"]
        value.merge(UnifiedQAAutonomy.shared.evidence) { _, new in new }
        return value
    }

    private static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    }
}

struct UnifiedQAReporter: View {
    let app: String; let source: String; let prefix: String
    @StateObject private var store = UnifiedQAStore.shared
    @State private var presented = false
    @AppStorage(UnifiedQASettings.enabledKey) private var enabled = false
    var body: some View {
        ZStack {
            UnifiedQAGestureObserver().frame(width: 0, height: 0)
            Button { presented = true } label: { Image(systemName: "ladybug.fill").padding(12).background(.ultraThinMaterial).clipShape(Circle()) }
        }
            .accessibilityLabel("Open QA tickets")
            .sheet(isPresented: $presented) { UnifiedQAPasscodeGate { UnifiedQATicketList(app: app, source: source, prefix: prefix).environmentObject(store) } }
            .task {
                guard UnifiedQAPasscode.isUnlocked else { enabled = false; return }
                UnifiedQAAutonomy.shared.start(); store.retryAll(source: source)
            }
            .onReceive(NotificationCenter.default.publisher(for: .unifiedQAQuickReport)) { _ in presented = true }
    }
}

private struct UnifiedQATicketList: View {
    let app: String; let source: String; let prefix: String
    @EnvironmentObject var store: UnifiedQAStore
    @Environment(\.dismiss) var dismiss
    @State private var editing: UnifiedQATicket?
    @State private var creating = false
    @ObservedObject private var autonomy = UnifiedQAAutonomy.shared
    var body: some View {
        NavigationStack {
            List {
                Section("Automatic coverage") {
                    LabeledContent("Memory", value: "\(autonomy.memoryMB) MB")
                    LabeledContent("Longest hang", value: "\(autonomy.longestHitchMS) ms")
                    Button("Run accessibility sweep") { autonomy.runAccessibilityAudit() }
                    if !autonomy.accessibilityFindings.isEmpty {
                        Text("\(autonomy.accessibilityFindings.count) accessibility finding(s)").foregroundStyle(.orange)
                    }
                    ForEach(autonomy.events.prefix(8)) { event in
                        VStack(alignment: .leading) {
                            Text(event.kind.capitalized).font(.caption.bold())
                            Text(event.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Deep QA") {
                    NavigationLink("Open Sesh QA Lab") {
                        UnifiedQADeepView(app: app, tickets: store.tickets,
                                          unsyncedCount: store.tickets.filter { $0.status != "verified" }.count,
                                          memoryMB: autonomy.memoryMB,
                                          hitchMS: autonomy.longestHitchMS)
                    }
                    Text("Session, strain, stash, journal, insights, community, music, sync, privacy, and reliability checks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !store.syncMessage.isEmpty { Text(store.syncMessage).font(.caption).foregroundStyle(.secondary) }
                ForEach(store.tickets) { ticket in Button { editing = ticket } label: { VStack(alignment: .leading, spacing: 4) { Text(ticket.number).font(.caption.monospaced()); Text(ticket.title).font(.headline); Text(ticket.status.capitalized + " · " + ticket.severity.capitalized).font(.caption).foregroundStyle(.secondary); if ticket.requiresManualReview == true { Label("Requires manual review", systemImage: "person.crop.circle.badge.questionmark").font(.caption).foregroundStyle(.orange) }; if let resolution = ticket.resolution { Text("Fixed: " + resolution).font(.caption).lineLimit(2).foregroundStyle(.green) } } } }
            }
            .navigationTitle("QA Tickets")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $creating) { UnifiedQATicketEditor(app: app, source: source, prefix: prefix, ticket: nil).environmentObject(store) }
            .sheet(item: $editing) { UnifiedQATicketEditor(app: app, source: source, prefix: prefix, ticket: $0).environmentObject(store) }
        }
    }
}

private struct UnifiedQATicketEditor: View {
    let app: String; let source: String; let prefix: String; let ticket: UnifiedQATicket?
    @EnvironmentObject var store: UnifiedQAStore
    @Environment(\.dismiss) var dismiss
    @State private var title: String; @State private var details: String; @State private var severity: String; @State private var screen: String; @State private var status: String; @State private var resolution: String; @State private var requiresManualReview: Bool
    init(app: String, source: String, prefix: String, ticket: UnifiedQATicket?) {
        self.app=app; self.source=source; self.prefix=prefix; self.ticket=ticket
        _title=State(initialValue: ticket?.title ?? ""); _details=State(initialValue: ticket?.body ?? "")
        _severity=State(initialValue: ticket?.severity ?? "major"); _screen=State(initialValue: ticket?.screen ?? "Current screen"); _status=State(initialValue: ticket?.status ?? "open"); _resolution=State(initialValue: ticket?.resolution ?? ""); _requiresManualReview=State(initialValue: ticket?.requiresManualReview ?? false)
    }
    var body: some View { NavigationStack { Form { Section("Issue") { TextField("Short title", text: $title); TextField("What happened and what should happen?", text: $details, axis: .vertical).lineLimit(4...10); Toggle("Requires manual review", isOn: $requiresManualReview); Text("Use when wording or design intent needs human interpretation. AI will ask for specifics.").font(.caption).foregroundStyle(.secondary) }; Section("Context") { Picker("Severity", selection: $severity) { Text("Blocker").tag("blocker"); Text("Major").tag("major"); Text("Minor").tag("minor") }; TextField("Screen", text: $screen) }; Section("Fix lifecycle") { Picker("Status", selection: $status) { Text("Open").tag("open"); Text("Investigating").tag("investigating"); Text("Fixed — needs verification").tag("fixed"); Text("Verified").tag("verified") }; TextField("What was fixed", text: $resolution, axis: .vertical).lineLimit(3...8); if let ticket, ticket.status == "fixed" { Button("Verify Fix") { store.verify(ticket, source: source); dismiss() }; Button("Refile — still broken", role: .destructive) { store.refile(ticket, source: source); dismiss() } } }; Section { Text("A screenshot and device/build context are attached automatically. Saving also syncs immediately; offline reports retry next time QA opens.").font(.caption).foregroundStyle(.secondary) } }.navigationTitle(ticket == nil ? "New Ticket" : "Edit Ticket").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(app: app, source: source, prefix: prefix, ticket: ticket, title: title, details: details, severity: severity, screen: screen, status: status, resolution: resolution, requiresManualReview: requiresManualReview); dismiss() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || status == "fixed" && resolution.trimmingCharacters(in: .whitespaces).isEmpty) } } } }
}
