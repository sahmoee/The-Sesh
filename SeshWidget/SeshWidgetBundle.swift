//
//  SeshWidgetBundle.swift
//  SeshWidget (Widget Extension target)
//
//  This file belongs to the WIDGET EXTENSION target only (NOT the app target).
//  It contains:
//    1. The Live Activity UI — lock screen + Dynamic Island regions — for an
//       in-progress sesh, with a self-updating timer.
//    2. A paired Home Screen widget showing your current sesh status (or your
//       last sesh when nothing is live).
//
//  Colors are kept self-contained (no dependency on the app's Theme.swift) so
//  the widget target only needs this file + SeshActivityAttributes.swift.
//
//  SETUP (Xcode): File → New → Target → Widget Extension, name it "SeshWidget",
//  CHECK "Include Live Activity". Replace the generated files with this one and
//  add SeshActivityAttributes.swift to the new target's membership. See the
//  README for the full checklist.
//

import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Palette (self-contained for the widget target)

private enum W {
    static let bg      = Color(red: 0.10, green: 0.12, blue: 0.09)
    static let card    = Color(red: 0.16, green: 0.19, blue: 0.13)
    static let text    = Color(red: 0.93, green: 0.91, blue: 0.85)
    static let subtle  = Color(red: 0.60, green: 0.63, blue: 0.53)
    static let green   = Color(red: 0.43, green: 0.50, blue: 0.29)
    static let gold    = Color(red: 0.79, green: 0.64, blue: 0.29)

    /// Emoji for a SeshStage rawValue.
    static func stageEmoji(_ raw: String) -> String {
        switch raw {
        case "Picking Strain": return "🌿"
        case "Rolling Up":     return "🧻"
        case "Sparked Up":     return "🔥"
        case "Smoking":        return "💨"
        case "Finished":       return "✅"
        default:                return "🌿"
        }
    }
}

// MARK: - 1. Live Activity

struct SeshLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SeshActivityAttributes.self) { context in
            // Lock screen / banner presentation
            lockScreen(context)
                .activityBackgroundTint(W.bg)
                .activitySystemActionForegroundColor(W.text)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text(W.stageEmoji(context.state.stageRaw)).font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture,
                         countsDown: false)
                        .monospacedDigit()
                        .frame(maxWidth: 64)
                        .foregroundStyle(W.gold)
                        .font(.system(size: 16, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.attributes.strainName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(W.text).lineLimit(1)
                        Text(context.state.stageLabel)
                            .font(.system(size: 11)).foregroundStyle(W.subtle)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let r = context.state.rollSeconds {
                        Text("Rolled in \(r)s").font(.system(size: 11)).foregroundStyle(W.green)
                    }
                }
            } compactLeading: {
                Text(W.stageEmoji(context.state.stageRaw))
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture,
                     countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(W.gold)
            } minimal: {
                Text(W.stageEmoji(context.state.stageRaw))
            }
            .keylineTint(W.green)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<SeshActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Text(W.stageEmoji(context.state.stageRaw)).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.strainName)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(W.text).lineLimit(1)
                Text(context.state.stageLabel)
                    .font(.system(size: 12)).foregroundStyle(W.subtle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(W.gold)
                    .frame(maxWidth: 90, alignment: .trailing)
                Text("this sesh").font(.system(size: 10)).foregroundStyle(W.subtle)
            }
        }
        .padding(16)
    }
}

// MARK: - 2. Paired Home Screen widget (sesh status)
//
// Reads a tiny shared snapshot written by the app via App Group UserDefaults
// (suite "group.com.sowens.The-SESH-"). The app writes keys on every relevant
// change; if there's nothing there yet, the widget shows a friendly empty state.

struct SeshStatusEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let lastStrain: String
    let stashCount: Int
    let isLive: Bool
    let liveStrain: String
}

struct SeshStatusProvider: TimelineProvider {
    private let suite = "group.com.sowens.The-SESH-"

    private func snapshot() -> SeshStatusEntry {
        let d = UserDefaults(suiteName: suite)
        return SeshStatusEntry(
            date: Date(),
            streak: d?.integer(forKey: "widget.streak") ?? 0,
            lastStrain: d?.string(forKey: "widget.lastStrain") ?? "—",
            stashCount: d?.integer(forKey: "widget.stashCount") ?? 0,
            isLive: d?.bool(forKey: "widget.isLive") ?? false,
            liveStrain: d?.string(forKey: "widget.liveStrain") ?? "")
    }

    func placeholder(in context: Context) -> SeshStatusEntry {
        SeshStatusEntry(date: Date(), streak: 7, lastStrain: "Blue Dream", stashCount: 2, isLive: false, liveStrain: "")
    }
    func getSnapshot(in context: Context, completion: @escaping (SeshStatusEntry) -> Void) {
        completion(snapshot())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SeshStatusEntry>) -> Void) {
        // Refresh ~every 30 min; the app also nudges reloads on key changes.
        let entry = snapshot()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SeshStatusWidgetView: View {
    var entry: SeshStatusEntry

    var body: some View {
        ZStack {
            W.bg
            if entry.isLive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🔴 SESH LIVE").font(.system(size: 11, weight: .bold)).foregroundStyle(W.gold)
                    Text(entry.liveStrain.isEmpty ? "In progress" : entry.liveStrain)
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(W.text).lineLimit(1)
                    Spacer()
                    Text("Tap to resume").font(.system(size: 11)).foregroundStyle(W.subtle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🔥").font(.system(size: 16))
                        Text("\(entry.streak)").font(.system(size: 26, weight: .heavy)).foregroundStyle(W.text)
                        Text("day streak").font(.system(size: 12)).foregroundStyle(W.subtle)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST SESH").font(.system(size: 9, weight: .bold)).foregroundStyle(W.subtle)
                        Text(entry.lastStrain).font(.system(size: 14, weight: .semibold)).foregroundStyle(W.text).lineLimit(1)
                    }
                    if entry.stashCount > 0 {
                        Text("📦 \(entry.stashCount) in stash").font(.system(size: 11)).foregroundStyle(W.green)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

struct SeshStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SeshStatusWidget", provider: SeshStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                SeshStatusWidgetView(entry: entry).containerBackground(W.bg, for: .widget)
            } else {
                SeshStatusWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Your Sesh")
        .description("Your streak, last strain, and stash — or your live sesh.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct SeshWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeshStatusWidget()
        SeshLiveActivity()
    }
}
