import Foundation
import Combine
@preconcurrency import WatchConnectivity
import WatchKit

@MainActor final class SeshWatchStore: NSObject, ObservableObject, WCSessionDelegate {
    nonisolated static let delivery = SeshWatchDeliveryTracker()
    @Published private(set) var state = SeshWatchLocalState()
    @Published var status = "Open The SESH. on iPhone to sync."
    @Published var error: String?
    @Published private(set) var reachable = false
    @Published private(set) var syncing = false
    @Published private(set) var page: SeshWatchPage?
    @Published private(set) var loadingPage = false
    private var pageRequestID: UUID?
    private var snapshotGate = SeshWatchRequestGate()
    private var pageTimeout: Task<Void, Never>?
    private var pageRefreshTask: Task<Void, Never>?
    private var snapshotTimeout: Task<Void, Never>?
    private var flights = Set<UUID>()
    private let file: SeshWatchFile<SeshWatchLocalState>
    private var draftTask: Task<Void, Never>?
    override init() {
        file = SeshWatchFile(url: .applicationSupportDirectory.appending(path: "WatchCompanion/private-state-v1.json"))
        super.init(); reload()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func reload() {
        do { let loaded = try file.load() ?? SeshWatchLocalState(); try loaded.validate(); state = loaded; error = nil }
        catch { file.blocked = true; self.error = "Saved watch data could not be read. Nothing was erased. Unlock the watch and retry loading." }
    }
    private func commit(_ next: SeshWatchLocalState) throws { try next.validate(); try file.write(next); state = next }
    func draft(_ value: SeshWatchLog, rawAmount: String? = nil) {
        state.draft = value
        if let rawAmount { state.amountDraft = rawAmount }
        scheduleDraft()
    }
    func thoughtDraft(_ value: String) { state.thoughtDraft = value; scheduleDraft() }
    func stashDraft(_ value: SeshWatchStashDraft) { state.stashDraft = value; scheduleDraft() }
    func goalDraft(_ value: SeshWatchGoalDraft) { state.goalDraft = value; scheduleDraft() }
    private func scheduleDraft() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }; self?.flushDraft()
        }
    }
    func flushDraft() {
        draftTask?.cancel()
        do { try state.validate(); try file.write(state) } catch { self.error = "The draft could not be saved. Keep this screen open and retry after freeing storage." }
    }
    func startTimer(_ value: SeshWatchLog) {
        do {
            var next = state; next.draft = value; next.timerStarted = Date(); try commit(next); haptic(); status = "Watch timer started."
        } catch { self.error = error.localizedDescription }
    }
    func discardTimer() {
        do { var next = state; next.timerStarted = nil; try commit(next); status = "Watch timer discarded." }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult func enqueue(_ command: SeshWatchCommand, clearDraft: Bool = false) -> Bool {
        do {
            draftTask?.cancel()
            var next = state; try next.enqueue(command)
            if clearDraft { next.draft = SeshWatchLog(); next.amountDraft = ""; next.timerStarted = nil }
            if command.kind == .thought { next.thoughtDraft = "" }
            if command.kind == .addStash { next.stashDraft = SeshWatchStashDraft() }
            if command.kind == .addGoal { next.goalDraft = SeshWatchGoalDraft() }
            try commit(next); status = "Queued privately. Waiting for iPhone confirmation."; haptic(); sendPending(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func log(_ value: SeshWatchLog) -> Bool {
        guard let epoch = state.snapshot?.epoch else { error = "Sync with iPhone before your first log."; return false }
        return enqueue(SeshWatchCommand(epoch: epoch, kind: .log, log: value), clearDraft: true)
    }
    func setFlag(_ kind: SeshWatchCommand.Kind, id: UUID, value: Bool) {
        guard let epoch = state.snapshot?.epoch else { return }
        _ = enqueue(SeshWatchCommand(epoch: epoch, kind: kind, recordID: id, flag: value))
    }
    func saveThought(_ text: String) -> Bool {
        guard let epoch = state.snapshot?.epoch else { return false }
        return enqueue(SeshWatchCommand(epoch: epoch, kind: .thought, text: text))
    }
    func saveStash(_ row: SeshWatchStash) -> Bool {
        guard let epoch = state.snapshot?.epoch else { return false }
        return enqueue(SeshWatchCommand(id: row.id, epoch: epoch, kind: .addStash, stash: row))
    }
    func saveGoal(_ row: SeshWatchGoal) -> Bool {
        guard let epoch = state.snapshot?.epoch else { return false }
        return enqueue(SeshWatchCommand(id: row.id, epoch: epoch, kind: .addGoal, goal: row))
    }
    func preference(haptics: Bool? = nil, hideText: Bool? = nil) {
        do { var next = state; if let haptics { next.haptics = haptics }; if let hideText { next.hidePrivateText = hideText }; try commit(next) }
        catch { self.error = error.localizedDescription }
    }
    func retryPending() {
        do { var next = state; for i in next.pending.indices where next.pending[i].retryable { next.pending[i].message = nil }; try commit(next); sendPending() }
        catch { self.error = error.localizedDescription }
    }
    func dismissPending(_ id: UUID) {
        do {
            var next = state; next.pending.removeAll { $0.id == id }; try commit(next)
            for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo["commandID"] as? String == id.uuidString { transfer.cancel() }
            flights.remove(id)
            status = "Action removed from this queue. A request already delivered may still save on iPhone; check history before recreating it."
        } catch { self.error = "The queued action could not be removed. Nothing was discarded." }
    }
    func eraseLocalCopy() {
        do {
            draftTask?.cancel(); snapshotTimeout?.cancel(); snapshotGate.cancel(); pageRequestID = nil; pageTimeout?.cancel(); pageRefreshTask?.cancel(); page = nil; flights.removeAll(); syncing = false; loadingPage = false
            WCSession.default.outstandingUserInfoTransfers.forEach { $0.cancel() }
            try file.erase(); state = SeshWatchLocalState(); status = "Local watch copy erased. Saved iPhone records are unchanged."; error = nil
        } catch { self.error = "The watch copy could not be erased. Unlock the watch and retry." }
    }
    func sync() {
        guard WCSession.default.activationState == .activated else { status = "Activating the iPhone connection…"; return }
        reachable = WCSession.default.isReachable
        guard reachable else { status = "Offline. Cached records and queued actions remain on this watch."; return }
        guard snapshotGate.current == nil else { return }
        let id = snapshotGate.begin(); syncing = true
        snapshotTimeout?.cancel()
        snapshotTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.snapshotGate.current == id else { return }
            self.snapshotGate.cancel(); self.syncing = false; self.status = "iPhone did not respond. Open both apps and retry."
        }
        do {
            let data = try SeshWatchContract.encode(SeshWatchPacket(request: true))
            WCSession.default.sendMessageData(data, replyHandler: { [weak self] data in
                Task { @MainActor in
                    guard let self, self.snapshotGate.current == id else { return }
                    guard self.snapshotGate.finish(id) else { return }; self.snapshotTimeout?.cancel(); self.syncing = false
                    self.receive(data, allowNewEpoch: true); self.sendPending()
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.snapshotGate.current == id else { return }
                    self.snapshotGate.cancel(); self.syncing = false; self.snapshotTimeout?.cancel()
                    self.status = "iPhone is unavailable. Your queued actions are preserved."
                }
            })
        } catch { snapshotGate.cancel(); syncing = false; self.error = error.localizedDescription }
    }
    func browse(_ area: SeshWatchPageRequest.Area, query: String, offset: Int = 0) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable, let epoch = state.snapshot?.epoch else {
            error = "Connect to iPhone to browse beyond the offline copy."; return
        }
        guard !loadingPage else { return }
        let request = SeshWatchPageRequest(epoch: epoch, area: area, query: query, offset: offset)
        pageRequestID = request.id; loadingPage = true; error = nil
        pageTimeout?.cancel()
        pageTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.pageRequestID == request.id else { return }
            self.pageRequestID = nil; self.loadingPage = false; self.error = "iPhone did not finish this page. Retry when connected."
        }
        do {
            try request.validate()
            let data = try SeshWatchContract.encode(SeshWatchPacket(pageRequest: request))
            WCSession.default.sendMessageData(data, replyHandler: { [weak self] data in
                Task { @MainActor in
                    guard let self, self.pageRequestID == request.id else { return }
                    self.loadingPage = false; self.pageTimeout?.cancel()
                    do {
                        let packet = try SeshWatchContract.decode(SeshWatchPacket.self, data); try packet.validate()
                        guard let page = packet.page, page.request.id == request.id, page.request.epoch == self.state.snapshot?.epoch else { throw SeshWatchError.invalid("The page changed. Search again.") }
                        self.page = page
                    } catch { self.error = "The requested page is unavailable. Open iPhone and retry." }
                }
            }, errorHandler: { [weak self] _ in Task { @MainActor in
                guard let self, self.pageRequestID == request.id else { return }; self.loadingPage = false; self.pageTimeout?.cancel(); self.error = "iPhone could not load this page. Try again when connected."
            } })
        } catch { loadingPage = false; self.error = error.localizedDescription }
    }
    func cancelPage() { pageRefreshTask?.cancel(); pageTimeout?.cancel(); pageRequestID = nil; loadingPage = false; page = nil }
    private func schedulePageRefresh() {
        guard page != nil, reachable else { return }
        pageRefreshTask?.cancel()
        pageRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            // Coalesce an acknowledgement burst, then wait for the one active
            // read to complete or time out before refreshing its latest page.
            while let self, self.loadingPage {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            guard !Task.isCancelled, let self, let current = self.page else { return }
            self.browse(current.request.area, query: current.request.query, offset: current.request.offset)
        }
    }
    private func sendPending() {
        guard !file.blocked, WCSession.default.activationState == .activated, state.snapshot?.enabled == true else { return }
        let outstanding = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["commandID"] as? String })
        for row in state.pending where row.message == nil && row.command.epoch == state.snapshot?.epoch {
            do {
                let data = try SeshWatchContract.encode(SeshWatchPacket(command: row.command))
                if !outstanding.contains(row.id.uuidString) { WCSession.default.transferUserInfo([SeshWatchContract.channel: data, "commandID": row.id.uuidString]) }
                guard WCSession.default.isReachable, flights.insert(row.id).inserted else { continue }
                WCSession.default.sendMessageData(data, replyHandler: { [weak self] response in Task { @MainActor in
                    self?.flights.remove(row.id); self?.receive(response)
                } }, errorHandler: { [weak self] _ in Task { @MainActor in self?.flights.remove(row.id) } })
            } catch { self.error = error.localizedDescription }
        }
    }
    private func receive(_ data: Data, allowNewEpoch: Bool = false) {
        do {
            let packet = try SeshWatchContract.decode(SeshWatchPacket.self, data); try packet.validate()
            var next = state
            if let snapshot = packet.snapshot {
                if let current = state.snapshot, current.epoch != snapshot.epoch, !allowNewEpoch {
                    status = "The iPhone journal changed. Sync to verify its current private copy."; return
                }
                let changedEpoch = state.snapshot != nil && state.snapshot?.epoch != snapshot.epoch
                if changedEpoch || !snapshot.enabled { cancelPage() }
                try next.receive(snapshot, allowNewEpoch: allowNewEpoch)
                try commit(next)
                status = changedEpoch ? "iPhone journal reset verified. Old watch records and queued actions cleared." : snapshot.enabled ? "Private copy updated from iPhone." : "Watch access is disabled on iPhone."
            }
            if let receipt = packet.receipt {
                try next.receive(receipt); try commit(next)
                if receipt.accepted {
                    schedulePageRefresh()
                    for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo["commandID"] as? String == receipt.commandID.uuidString { transfer.cancel() }
                }
                status = receipt.message
            }
        } catch { self.error = "The iPhone update could not be saved or read. Your queued actions are preserved; retry sync." }
    }
    func finishBackgroundDelivery() async {
        var quiet = 0
        while !Task.isCancelled {
            let ready = WCSession.default.activationState == .activated && !WCSession.default.hasContentPending && Self.delivery.idle
            quiet = ready ? quiet + 1 : 0
            if quiet >= 2 { flushDraft(); return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }
    func haptic() { if state.haptics { WKInterfaceDevice.current().play(.success) } }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let context = session.receivedApplicationContext[SeshWatchContract.channel] as? Data
        Task { @MainActor in if let context { self.receive(context) }; self.reachable = WCSession.default.isReachable; self.sync(); self.sendPending() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = WCSession.default.isReachable; if self.reachable { self.sync() } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[SeshWatchContract.channel] as? Data else { return }; Self.delivery.begin(); Task { @MainActor in defer { Self.delivery.end() }; self.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo info: [String: Any]) {
        guard let data = info[SeshWatchContract.channel] as? Data else { return }; Self.delivery.begin(); Task { @MainActor in defer { Self.delivery.end() }; self.receive(data) }
    }
}
