//
//  ConnectivityMonitor.swift
//  The SESH
//
//  (#C6) Shared network-path state via NWPathMonitor, and (#App14) the app-wide
//  connectivity model. One instance is owned by the app; stores consult it to
//  pause aggressive work while offline and to refresh immediately after
//  reconnecting, and the UI can show a real state instead of guessing:
//
//    .offline        no network path
//    .serverDown     network is up, the Worker isn't answering
//    .syncing        connected, replaying queued work / fetching
//    .current        connected and up to date
//
//  Cached data remains visible in every state — the state describes freshness.
//

import Foundation
import Network
import Observation

enum ConnectivityState: Equatable {
    case offline
    case serverDown
    case syncing
    case current

    var label: String {
        switch self {
        case .offline:    return "Offline — showing saved data"
        case .serverDown: return "Can't reach SESH — showing saved data"
        case .syncing:    return "Syncing…"
        case .current:    return "Up to date"
        }
    }
    var showsBanner: Bool { self == .offline || self == .serverDown }
}

@MainActor
@Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    /// Raw path state from NWPathMonitor.
    private(set) var pathSatisfied = true
    /// Whether the last Worker call succeeded (fed by SocialStore/SeshAPI).
    var serverReachable = true
    /// Whether a sync/replay is currently in flight (fed by stores).
    var isSyncing = false

    /// Called when the path flips from unsatisfied to satisfied — stores hook
    /// this to refresh immediately instead of waiting for the next poll (#C6).
    var onReconnect: (() -> Void)?

    var state: ConnectivityState {
        if !pathSatisfied { return .offline }
        if !serverReachable { return .serverDown }
        if isSyncing { return .syncing }
        return .current
    }

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.pathSatisfied
                self.pathSatisfied = satisfied
                if satisfied && wasOffline {
                    self.serverReachable = true   // optimistic until proven otherwise
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sesh.connectivity"))
    }
}
