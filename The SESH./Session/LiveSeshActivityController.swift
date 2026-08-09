//
//  LiveSeshActivityController.swift
//  The SESH
//
//  App-target controller that drives the sesh Live Activity (Dynamic Island /
//  lock screen) and keeps the Home Screen widget's shared snapshot up to date.
//
//  Live Activities need NO server — the timer renders itself from a start date,
//  and we update the stage locally as the sesh progresses. Requires iOS 16.1+,
//  NSSupportsLiveActivities=YES in the app Info.plist, and the widget extension
//  target to exist (see README).
//

import Foundation
@preconcurrency import ActivityKit
import WidgetKit

@MainActor
enum LiveSeshActivityController {
    private static var current: Activity<SeshActivityAttributes>?

    /// Whether the user has Live Activities enabled for the app.
    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start (or restart) the Live Activity for an in-progress sesh.
    static func start(strain: String, stageRaw: String, startedAt: Date,
                      companionCount: Int = 0, thoughtCount: Int = 0) {
        guard isAvailable else { return }
        // If one is already running, just update it instead of stacking.
        if current != nil {
            update(stageRaw: stageRaw, startedAt: startedAt, strainName: strain,
                   companionCount: companionCount, thoughtCount: thoughtCount)
            return
        }
        let attributes = SeshActivityAttributes(strainName: strain.isEmpty ? "Sesh" : strain)
        let state = SeshActivityAttributes.ContentState(
            stageRaw: stageRaw, startedAt: startedAt, rollSeconds: nil,
            strainName: strain.isEmpty ? nil : strain,
            companionCount: companionCount, thoughtCount: thoughtCount)
        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil))
        } catch {
            current = nil   // requesting can throw (disabled, too many, etc.) — fail quietly
        }
    }

    /// Update the running activity's stage / roll result / richer fields.
    static func update(stageRaw: String, startedAt: Date, rollSeconds: Int? = nil,
                       strainName: String? = nil, companionCount: Int = 0, thoughtCount: Int = 0) {
        guard let activity = current else { return }
        let state = SeshActivityAttributes.ContentState(
            stageRaw: stageRaw, startedAt: startedAt, rollSeconds: rollSeconds,
            strainName: (strainName?.isEmpty ?? true) ? nil : strainName,
            companionCount: companionCount, thoughtCount: thoughtCount)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// End the activity (sesh saved or discarded).
    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Writes a tiny snapshot the Home Screen widget reads via the shared App Group.
/// Call after meaningful changes (new entry, stash change, sesh start/stop).
@MainActor
enum SeshWidgetBridge {
    private static let suite = "group.com.sowens.The-SESH-"

    static func update(streak: Int, lastStrain: String, stashCount: Int,
                       isLive: Bool, liveStrain: String) {
        guard let d = UserDefaults(suiteName: suite) else { return }
        d.set(streak, forKey: "widget.streak")
        d.set(lastStrain, forKey: "widget.lastStrain")
        d.set(stashCount, forKey: "widget.stashCount")
        d.set(isLive, forKey: "widget.isLive")
        d.set(liveStrain, forKey: "widget.liveStrain")
        // Ask WidgetKit to refresh the Home Screen widget timelines.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
