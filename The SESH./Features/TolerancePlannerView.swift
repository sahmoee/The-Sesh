//
//  TolerancePlannerView.swift
//  The SESH
//
//  (Feature 15) Rest-day & tolerance planner. Schedule weekly rest days,
//  track how you're doing against them from the journal, and see your current
//  streaks. User-controlled reminders only; no medical claims anywhere.
//

import SwiftUI
import UserNotifications

struct TolerancePlannerView: View {
    @Environment(AppSession.self) private var session

    /// Weekday numbers (1 = Sunday … 7 = Saturday) chosen as rest days.
    @State private var restDays: Set<Int> = TolerancePlan.restDays
    @State private var remindersOn = TolerancePlan.remindersOn

    private static let daySymbols = Calendar.current.shortWeekdaySymbols

    // MARK: derived stats

    /// Days in the last 28 with no logged session.
    private var restDaysTaken: Int {
        let cal = Calendar.current
        let seshDays = Set(session.entries
            .filter { $0.date > cal.date(byAdding: .day, value: -28, to: Date())! }
            .map { cal.startOfDay(for: $0.date) })
        return (0..<28).filter { off in
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -off, to: Date())!)
            return !seshDays.contains(day)
        }.count
    }

    /// Current consecutive rest-day streak ending today/yesterday.
    private var currentBreakStreak: Int {
        let cal = Calendar.current
        let seshDays = Set(session.entries.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while !seshDays.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
            if streak > 365 { break }
        }
        return streak
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        statCard("Rest days (28d)", "\(restDaysTaken)")
                        statCard("Current break", currentBreakStreak == 0 ? "—" : "\(currentBreakStreak)d")
                    }

                    FieldLabel(text: "Weekly rest days")
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let on = restDays.contains(day)
                            Button {
                                if on { restDays.remove(day) } else { restDays.insert(day) }
                                TolerancePlan.restDays = restDays
                                if remindersOn { TolerancePlan.scheduleReminders() }
                                Haptics.selection()
                            } label: {
                                Text(Self.daySymbols[day - 1])
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(on ? Palette.green : Palette.field))
                                    .foregroundStyle(on ? .white : Palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(Self.daySymbols[day - 1]) rest day")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }

                    Toggle(isOn: $remindersOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Morning reminders on rest days")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            Text("A gentle 10am nudge — nothing else.")
                                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .tint(Palette.green)
                    .onChange(of: remindersOn) { _, on in
                        TolerancePlan.remindersOn = on
                        if on { TolerancePlan.scheduleReminders() } else { TolerancePlan.cancelReminders() }
                    }

                    Text("Taking breaks tends to bring effects back at lower amounts for many people. This is a planning tool, not medical advice — do what works for you.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                .padding(16)
            }
        }
        .navigationTitle("Rest Days")
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.greenBright)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Persistence + notifications for the rest-day plan.
@MainActor
enum TolerancePlan {
    private static let daysKey = "sesh.tolerance.restdays.v1"
    private static let remindKey = "sesh.tolerance.reminders.v1"

    static var restDays: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: daysKey) as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: daysKey) }
    }
    static var remindersOn: Bool {
        get { UserDefaults.standard.bool(forKey: remindKey) }
        set { UserDefaults.standard.set(newValue, forKey: remindKey) }
    }

    static func scheduleReminders() {
        cancelReminders()
        for day in restDays {
            let content = UNMutableNotificationContent()
            content.title = "Rest day 🌱"
            content.body = "Today's a planned break. Future you says thanks."
            content.sound = .default
            var comps = DateComponents()
            comps.weekday = day; comps.hour = 10
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "sesh.rest.\(day)", content: content, trigger: trigger))
        }
    }

    static func cancelReminders() {
        let ids = (1...7).map { "sesh.rest.\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
