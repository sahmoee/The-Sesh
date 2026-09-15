import Foundation

/// Native checks only; creates its own temporary directory and never opens app data.
@main enum JournalStudioChecks {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checks += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        let today = calendar.startOfDay(for: now)
        check(JournalStudioPolicy.includes(today, days: 1, now: now, calendar: calendar), "Today starts at midnight")
        check(!JournalStudioPolicy.includes(today.addingTimeInterval(-1), days: 1, now: now, calendar: calendar), "Exclude previous day")
        check(!JournalStudioPolicy.includes(calendar.date(byAdding: .day, value: 1, to: today)!, days: 7, now: now, calendar: calendar), "Exclude tomorrow")
        check(JournalStudioPolicy.includes(calendar.date(byAdding: .day, value: -6, to: today)!, days: 7, now: now, calendar: calendar), "Seven-day inclusive boundary")
        check(!JournalStudioPolicy.includes(calendar.date(byAdding: .day, value: -7, to: today)!, days: 7, now: now, calendar: calendar), "Seven days doesn't include eight")
        check(JournalStudioPolicy.includes(.distantPast, days: 0, now: now), "All time")
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 13))!
        check(JournalStudioPolicy.includes(calendar.startOfDay(for: spring), days: 1, now: spring, calendar: calendar), "DST day boundaries")
        check(JournalStudioPolicy.validName("  Weekend  ", existing: []) == "Weekend", "Trim names")
        check(JournalStudioPolicy.validName("cafe", existing: ["Café"]) == nil, "Reject accent-insensitive duplicate name")
        check(JournalStudioPolicy.validName(" \n", existing: []) == nil, "Reject blank name")
        check(JournalStudioPolicy.validName(String(repeating: "a", count: 61), existing: []) == nil, "Bound name")
        check(JournalStudioPolicy.csvCell("a,\"b\"\nc") == "\"a,\"\"b\"\"\nc\"", "Quote CSV commas quotes and newlines")
        for input in ["=SUM(A1)", " +cmd", "-2+3", "@SUM(A1)", "\t123", "\r123"] {
            check(JournalStudioPolicy.csvCell(input).hasPrefix("\"'"), "Neutralize spreadsheet formula")
        }
        check(JournalStudioPolicy.csv(rows: [["A", "B"], ["1", "2"]]).hasSuffix("\r\n"), "CRLF export")
        let a = UUID(), b = UUID()
        check(JournalStudioPolicy.duplicateKey(ids: [a, b]) == JournalStudioPolicy.duplicateKey(ids: [b, a]), "Stable duplicate review identity")
        let priorMonth = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let sameMonth = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        let nextMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let spend = JournalStudioPolicy.monthlySpend([(priorMonth, 99), (sameMonth, 12), (nextMonth, 33), (now, .nan), (now, -2)], now: now, calendar: calendar)
        check(spend.count == 5, "September five buckets")
        check(spend.reduce(0) { $0 + $1.1 } == 12, "Only finite current-month positive amounts")
        check(spend[1].1 == 12 && calendar.component(.day, from: spend[1].0) == 8, "Real weekly labels")
        let temp = FileManager.default.temporaryDirectory.appending(path: "sesh-studio-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appending(path: "organization.json")
        let store = JournalStudioStore(file: file)
        check(store.error == nil && store.snapshot.pinned.isEmpty, "Clean first launch")
        check(store.change { $0.pinned.insert(a) }, "Persist before observable success")
        let loaded = JournalStudioStore(file: file)
        check(loaded.snapshot.pinned == [a], "Pin durable across relaunch")
        let notebook = JournalNotebook(name: "Weekend")
        check(store.change { $0.notebooks.append(notebook); $0.savedViews.append(JournalStudioSavedView(name: "Recent", filter: JournalStudioFilter(days: 7))) }, "Notebook and saved view persisted")
        store.toggleMembership(a, notebook: notebook.id)
        check(store.snapshot.notebooks[0].entryIDs == [a], "Notebook membership")
        store.toggleMembership(a, notebook: notebook.id)
        check(store.snapshot.notebooks[0].entryIDs.isEmpty, "Membership toggle")
        check(store.saveReflection(JournalReflection(id: a, text: "Personal note", dueAt: now)), "Save reflection")
        check(store.saveReflection(JournalReflection(id: a, text: "Revised", dueAt: now, completedAt: now)), "Update reflection by ID")
        check(store.snapshot.reflections.count == 1 && store.snapshot.reflections[0].text == "Revised", "No duplicate reflection")
        let reloaded = JournalStudioStore(file: file)
        check(reloaded.snapshot.savedViews[0].filter.days == 7 && reloaded.snapshot.reflections[0].completedAt == now, "Complete snapshot round trip")
        store.removeReferences(to: a)
        check(store.snapshot.pinned.isEmpty && store.snapshot.reflections.isEmpty, "Deleted record metadata removed")
        let invalid = temp.appending(path: "invalid.json")
        let corrupt = Data("preserve me".utf8)
        try corrupt.write(to: invalid)
        let damaged = JournalStudioStore(file: invalid)
        check(damaged.error != nil, "Expose corrupt store")
        check(!damaged.change { $0.pinned.insert(a) }, "Do not overwrite unreadable store")
        let retained = try Data(contentsOf: invalid)
        check(retained == corrupt, "Corrupt bytes preserved")
        damaged.clear()
        check(!FileManager.default.fileExists(atPath: invalid.path) && damaged.error == nil, "Explicit reset erases even unreadable private metadata")
        check(damaged.change { $0.pinned.insert(a) }, "Usable after explicit reset")
        let blocker = temp.appending(path: "not-a-directory")
        try Data().write(to: blocker)
        let blocked = JournalStudioStore(file: blocker.appending(path: "organization.json"))
        check(!blocked.change { $0.pinned.insert(a) }, "I/O failure reported")
        check(blocked.snapshot.pinned.isEmpty, "No optimistic success after I/O failure")
        print("Journal Studio checks passed: \(checks)")
    }
}
