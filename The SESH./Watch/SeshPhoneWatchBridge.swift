import Foundation
import Observation
@preconcurrency import WatchConnectivity

private nonisolated struct SeshWatchReply: @unchecked Sendable { let block: (Data) -> Void }
@MainActor @Observable final class SeshPhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = SeshPhoneWatchBridge()
    private struct Settings: Codable {
        var epoch = UUID(); var revision = 0; var enabled = true
        func validate() throws { guard revision >= 0 else { throw SeshWatchError.invalid("Watch settings require recovery.") } }
    }
    private var settings = Settings()
    @ObservationIgnored private let file = SeshWatchFile<Settings>(url: .applicationSupportDirectory.appending(path: "WatchCompanion/phone-state.json"))
    @ObservationIgnored private weak var journal: AppSession?
    @ObservationIgnored private weak var catalog: StrainStore?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private(set) var lastSync: Date?
    private(set) var error: String?
    var enabled: Bool { settings.enabled }
    var connected: Bool { WCSession.isSupported() && WCSession.default.isReachable }
    override private init() {
        super.init()
        do { settings = try file.load() ?? Settings(); try settings.validate(); try file.write(settings) }
        catch { file.blocked = true; self.error = "Watch settings could not be read. Original data is preserved; retry after unlocking iPhone." }
    }
    func configure(session: AppSession, strains: StrainStore) {
        journal = session; catalog = strains
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func retry() {
        do { settings = try file.load() ?? Settings(); try settings.validate(); try file.write(settings); error = nil; refresh() }
        catch { file.blocked = true; self.error = "Watch settings are unavailable. Unlock iPhone and retry." }
    }
    func setEnabled(_ value: Bool) {
        do { var next = settings; next.enabled = value; try file.write(next); settings = next; refresh() }
        catch { self.error = "Watch access could not be saved. Your previous setting is unchanged." }
    }
    func resetJournalEpoch() -> Bool {
        do { var next = settings; next.epoch = UUID(); try file.write(next); settings = next; refreshTask?.cancel(); return true }
        catch { self.error = "The watch journal connection could not be reset. No journal data was deleted. Unlock iPhone and retry."; return false }
    }
    func scheduleSnapshot() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }; self?.refresh()
        }
    }
    func refresh() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled, !file.blocked else { return }
        do {
            let snapshot = try makeSnapshot()
            let data = try SeshWatchContract.encode(SeshWatchPacket(snapshot: snapshot))
            try WCSession.default.updateApplicationContext([SeshWatchContract.channel: data]); error = nil
        } catch { self.error = "The watch update could not be sent. Open both apps and retry." }
    }
    private func entry(_ value: JournalEntry) -> SeshWatchEntry? {
        var log = SeshWatchLog(date: value.date, strain: String(value.strain.prefix(120)), method: value.method, rating: value.rating,
            mood: value.mood?.rawValue, amount: value.amount, unit: value.amountUnit ?? "g", notes: String(value.notes.prefix(500)),
            durationMinutes: value.durationMinutes, moodBefore: value.moodBefore, moodAfter: value.moodAfter,
            tags: Array((value.sessionTags ?? []).prefix(5)))
        if !SeshWatchContract.methods.contains(log.method) { log.method = "Other" }
        if !SeshWatchContract.units.contains(log.unit) { log.amount = nil; log.unit = "g" }
        guard (try? log.validate()) != nil else { return nil }
        return SeshWatchEntry(id: value.id, log: log, favorite: value.isFavorite, pinned: JournalStudioStore.shared.snapshot.pinned.contains(value.id))
    }
    private func stash(_ value: Purchase) -> SeshWatchStash? {
        let row = SeshWatchStash(id: value.id, strain: String(value.strain.prefix(120)), amount: value.amount, used: value.used,
            unit: value.unit, cost: value.cost, date: value.date)
        return (try? row.validate()) != nil ? row : nil
    }
    private func strain(_ value: StrainProfile) -> SeshWatchStrain {
        let detail = ([value.summary ?? ""] + [value.effects.map(\.name).joined(separator: ", "), value.flavors.map(\.name).joined(separator: ", ")]).filter { !$0.isEmpty }.joined(separator: " · ")
        return SeshWatchStrain(id: String(value.id.prefix(120)), name: String(value.name.prefix(120)), type: value.type.rawValue,
            detail: String(detail.prefix(300)), thc: CatalogValuePolicy.percentage(value.thc), cbd: CatalogValuePolicy.percentage(value.cbd))
    }
    private func goal(_ value: SeshGoal, week: PersonalGoalPolicy.WeekSummary) -> SeshWatchGoal? {
        let row = SeshWatchGoal(id: value.id, title: String(value.title.prefix(120)), kind: value.kind.rawValue, target: value.target,
            actual: value.kind == .smokeLess ? Double(week.sessions) : value.kind == .spendLess ? min(1_000_000_000, week.spent) : nil,
            note: String(value.note.prefix(500)), active: value.active)
        return (try? row.validate()) != nil ? row : nil
    }
    private func week(_ session: AppSession) -> PersonalGoalPolicy.WeekSummary {
        PersonalGoalPolicy.week(now: Date(), sessionDates: session.entries.map(\.date), purchases: session.purchases.map { ($0.date, $0.cost) })
    }
    private func makeSnapshot() throws -> SeshWatchSnapshot {
        guard let journal, let catalog, !file.blocked else { throw SeshWatchError.invalid("Open The SESH. on iPhone to finish setup.") }
        var next = settings; guard next.revision < Int.max else { throw SeshWatchError.invalid("Refresh the watch connection in Settings.") }; next.revision += 1
        try file.write(next); settings = next
        var result = SeshWatchSnapshot(epoch: settings.epoch, revision: settings.revision, enabled: settings.enabled, name: String(journal.userName.prefix(120)))
        guard settings.enabled else { return result }
        let summary = week(journal)
        result.weeklySessions = summary.sessions; result.weeklySpend = min(1_000_000_000, summary.spent)
        result.entries = journal.entries.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }.prefix(40).compactMap(entry)
        result.stash = journal.purchases.sorted { $0.date > $1.date }.prefix(35).compactMap(stash)
        let selectedNames = Set((result.entries.map { $0.log.strain } + result.stash.map(\.strain)).map { $0.lowercased() })
        let allStrains = catalog.sorted()
        result.strains = Array(allStrains.filter { selectedNames.contains($0.name.lowercased()) }.prefix(50)).map(strain)
        result.goals = journal.goals.prefix(25).compactMap { goal($0, week: summary) }
        result.thoughts = journal.thoughts.sorted { $0.date > $1.date }.prefix(15).map { SeshWatchThought(id: $0.id, date: $0.date, text: String($0.text.prefix(500))) }
        result.totalEntries = journal.entries.count; result.totalStrains = allStrains.count
        result.phoneSessionStarted = journal.liveSesh?.startedAt; result.phoneSessionStrain = journal.liveSesh.map { String($0.strainName.prefix(120)) }
        result.notice = "Recent offline copy. Browse all or search while iPhone is reachable. Long notes are shortened; originals stay on iPhone."
        // Keep every application-context payload comfortably below the interactive limit.
        while (try? SeshWatchContract.encode(SeshWatchPacket(snapshot: result), maximum: 48_000)) == nil {
            if !result.strains.isEmpty { result.strains.removeLast() }
            else if result.entries.count > 5 { result.entries.removeLast() }
            else if !result.thoughts.isEmpty { result.thoughts.removeLast() }
            else if !result.stash.isEmpty { result.stash.removeLast() }
            else if !result.goals.isEmpty { result.goals.removeLast() }
            else { throw SeshWatchError.invalid("The watch update is too large.") }
        }
        try result.validate(); return result
    }
    private func makePage(_ request: SeshWatchPageRequest) throws -> SeshWatchPage {
        try request.validate()
        guard settings.enabled, request.epoch == settings.epoch, let journal, let catalog else { throw SeshWatchError.invalid("Sync with iPhone before browsing.") }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var page = SeshWatchPage(request: request, total: 0)
        func window<T>(_ values: [T]) -> [T] {
            page.total = values.count
            let lower = min(values.count, request.offset), upper = min(values.count, lower + 20)
            page.nextOffset = upper < values.count ? upper : nil
            return Array(values[lower..<upper])
        }
        switch request.area {
        case .history:
            let rows = journal.entries.filter { query.isEmpty || $0.strain.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
                .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
            page.entries = window(rows).compactMap(entry)
        case .strains: page.strains = window(catalog.search(query)).map(strain)
        case .stash: page.stash = window(journal.purchases.filter { query.isEmpty || $0.strain.localizedCaseInsensitiveContains(query) }.sorted { $0.date > $1.date }).compactMap(stash)
        case .goals: let summary = week(journal); page.goals = window(journal.goals.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }).compactMap { goal($0, week: summary) }
        case .thoughts: page.thoughts = window(journal.thoughts.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.sorted { $0.date > $1.date }).map { SeshWatchThought(id: $0.id, date: $0.date, text: String($0.text.prefix(500))) }
        }
        try page.validate(); return page
    }
    private func handle(_ data: Data) -> Data {
        do {
            let packet = try SeshWatchContract.decode(SeshWatchPacket.self, data); try packet.validate()
            if let command = packet.command {
                guard !file.blocked, settings.enabled, let journal else { throw SeshWatchError.invalid("Open The SESH. on iPhone and enable Watch access.") }
                let receipt: SeshWatchReceipt
                do { receipt = try SeshWatchTransactions.apply(command, epoch: settings.epoch, session: journal) }
                catch { receipt = SeshWatchReceipt(commandID: command.id, epoch: command.epoch, accepted: false, retryable: command.epoch == settings.epoch,
                    message: String(error.localizedDescription.prefix(500))) }
                lastSync = Date(); scheduleSnapshot()
                return try SeshWatchContract.encode(SeshWatchPacket(receipt: receipt))
            }
            if let request = packet.pageRequest { return try SeshWatchContract.encode(SeshWatchPacket(page: makePage(request))) }
            return try SeshWatchContract.encode(SeshWatchPacket(snapshot: makeSnapshot()))
        } catch { self.error = "A watch request could not be completed. Unlock iPhone and retry."; return Data() }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
        let reply = SeshWatchReply(block: replyHandler)
        Task { @MainActor in reply.block(self.handle(data)) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[SeshWatchContract.channel] as? Data else { return }
        Task { @MainActor in
            let response = self.handle(data)
            guard !response.isEmpty, WCSession.default.activationState == .activated else { return }
            WCSession.default.transferUserInfo([SeshWatchContract.channel: response])
        }
    }
}
