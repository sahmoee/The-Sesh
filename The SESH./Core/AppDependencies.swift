//
//  AppDependencies.swift
//  The SESH
//
//  (#5) Dependency injection seams. Stores stop constructing concrete services
//  internally; they take protocol-typed dependencies with production defaults,
//  so tests can inject fakes (frozen clock, canned API, in-memory images)
//  without any global setup.
//
//  Adoption is incremental: every initializer keeps default arguments, so
//  existing call sites compile unchanged.
//

import Foundation
import UIKit

// MARK: Clock

protocol Clock: Sendable {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

/// Test clock: fixed or manually advanced.
struct FixedClock: Clock {
    var now: Date
}

// MARK: Image loading

@MainActor
protocol ImageLoading {
    func image(strainID: String) async -> UIImage?
}

// MARK: Notification scheduling

@MainActor
protocol NotificationScheduling {
    func notify(kind: SeshNotification.Kind, title: String, body: String, id: String, icon: String?)
}

extension NotificationManager: NotificationScheduling {}

// MARK: Container

/// One place that owns production service instances. Built once at app launch
/// and handed to stores; previews/tests build their own with fakes.
@MainActor
struct AppDependencies {
    var clock: Clock = SystemClock()
    var api: SeshAPI = SeshAPI()
    var outbox: OfflineOutbox = .shared
    var connectivity: ConnectivityMonitor = .shared
    var auth: SeshAuth = .shared
    var privacy: PrivacySettings = .shared

    static let live = AppDependencies()
}
