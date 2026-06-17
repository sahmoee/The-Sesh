//
//  SeshActivityAttributes.swift
//  The SESH
//
//  Shared definition for the live sesh Live Activity (Dynamic Island + lock
//  screen). This file MUST be a member of BOTH the app target and the widget
//  extension target — in Xcode, select it and tick both under "Target
//  Membership". ActivityKit is available on iOS 16.1+.
//
//  The static `SeshActivityAttributes` describes the unchanging part of an
//  activity (the strain), and `ContentState` is the live, updatable part
//  (current stage + when the sesh started, so the timer renders itself).
//

import Foundation
import ActivityKit

struct SeshActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// SeshStage.rawValue — kept as a String so this file has no dependency
        /// on the app's models (the widget target only needs this file).
        var stageRaw: String
        /// When the sesh began; the Live Activity uses a self-updating timer
        /// (Text(timerInterval:)) anchored to this, so it ticks without pushes.
        var startedAt: Date
        /// Optional roll result (seconds) once the roll timer has been stopped.
        var rollSeconds: Int?

        var stageLabel: String { stageRaw }
    }

    /// Unchanging for the life of the activity.
    var strainName: String
}
