import Foundation

/// Run without a simulator or application data:
/// xcrun swiftc 'The SESH./CoreUI/JournalInputPolicy.swift' scripts/JournalUIContractChecks.swift -o /tmp/sesh-journal-ui-checks
/// /tmp/sesh-journal-ui-checks
@main enum JournalUIContractChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        check(JournalInputPolicy.decimal(" 2.75\n", locale: us) == 2.75, "Trim complete decimal")
        check(JournalInputPolicy.decimal("2,75", locale: de) == 2.75, "Localized decimal")
        check(JournalInputPolicy.decimal(".5", locale: us) == 0.5, "Leading decimal")
        check(JournalInputPolicy.decimal("5.", locale: us) == 5, "Trailing decimal")
        check(JournalInputPolicy.decimal("0", locale: us) == 0, "Optional zero")
        check(JournalInputPolicy.decimal("٢٫٥", locale: Locale(identifier: "ar_EG")) == 2.5, "Localized digits")
        for invalid in ["", " \n", "-2", "+2", "2g", "2 5", "2,500", "2.5.0", "nan", "inf", "1e3", ".", "²"] {
            check(JournalInputPolicy.decimal(invalid, locale: us) == nil, "Reject entire invalid input: \(invalid)")
        }
        check(JournalInputPolicy.decimal("2.75", locale: de) == nil, "Reject ambiguous foreign/group separator")
        check(JournalInputPolicy.decimal(String(repeating: "9", count: 400), locale: us) == nil, "Reject overflow")
        for number in [0, 0.125, 1.23456789, 0.000000001, 12345.6789] {
            let formatted = JournalInputPolicy.editableDecimal(number, locale: de)
            check(JournalInputPolicy.decimal(formatted, locale: de) == number, "Historical amount round-trip: \(number)")
        }
        check(JournalInputPolicy.matches("  CAFE\n", fields: ["Café notes"], locale: us), "Search accent and whitespace")
        check(JournalInputPolicy.matches(" \n", fields: [], locale: us), "Empty query matches")
        check(JournalInputPolicy.matches("calm", fields: ["strain", "Calm"], locale: us), "Search across metadata")
        check(!JournalInputPolicy.matches("missing", fields: ["notes"], locale: us), "No match")
        check(JournalInputPolicy.fingerprint(["a|b", "c"]) != JournalInputPolicy.fingerprint(["a", "b|c"]), "Draft delimiter collision")
        check(JournalInputPolicy.fingerprint(["ab", "c"]) != JournalInputPolicy.fingerprint(["a", "bc"]), "Draft concatenation collision")
        check(JournalInputPolicy.fingerprint(["🍃", ""]) == JournalInputPolicy.fingerprint(["🍃", ""]), "Unicode fingerprint stability")
        let old = Date(timeIntervalSince1970: 1)
        let recent = Date(timeIntervalSince1970: 2)
        check(JournalInputPolicy.precedes(metric: 8, date: old, id: "a", otherMetric: 6, otherDate: recent, otherID: "b", usesMetric: true), "Rating outranks recency")
        check(!JournalInputPolicy.precedes(metric: 8, date: old, id: "a", otherMetric: 6, otherDate: recent, otherID: "b", usesMetric: false), "Date sort ignores metric")
        check(JournalInputPolicy.precedes(metric: 0, date: old, id: "a", otherMetric: nil, otherDate: recent, otherID: "b", usesMetric: true), "Known zero precedes missing metric")
        check(!JournalInputPolicy.precedes(metric: nil, date: recent, id: "a", otherMetric: 1, otherDate: old, otherID: "b", usesMetric: true), "Thought follows rated entries")
        check(JournalInputPolicy.precedes(metric: nil, date: recent, id: "a", otherMetric: nil, otherDate: old, otherID: "b", usesMetric: true), "Unrated rows stay newest-first")
        check(JournalInputPolicy.precedes(metric: 8, date: old, id: "a", otherMetric: 8, otherDate: old, otherID: "b", usesMetric: true), "Stable tie break")
        check(!JournalInputPolicy.precedes(metric: 8, date: old, id: "a", otherMetric: 8, otherDate: old, otherID: "a", usesMetric: true), "Strict comparator identity")

        // Wiring checks supplement pure policy fixtures, not UI runtime tests.
        func source(_ path: String) throws -> String { try String(contentsOfFile: "The SESH./" + path, encoding: .utf8) }
        let journal = try source("Journal/JournalView.swift")
        check(journal.contains("JournalInputPolicy.precedes"), "Journal actually uses metric ordering")
        check(journal.contains(".extraStrains ?? []") && journal.contains(".sessionTags ?? []"), "Search includes recorded metadata")
        check(journal.contains(".disabled(filter == \"Thoughts\")"), "Session filters unavailable in Thoughts")
        check(journal.contains("if !filters.contains(filter) { filter = \"All\" }"), "Deleted category recovers")
        check(!journal.contains("allowsFullSwipe: true"), "No destructive full-swipe journal path")
        check(journal.contains("accessibilityAction(named: \"Edit thought\")"), "Accessible thought editing")
        check(journal.contains(".presentationDetents([.medium, .large])"), "Filter sheet expands")
        for path in ["Journal/ThoughtsView.swift", "Session/LogSeshView.swift", "Session/SaveSeshView.swift", "Stash/StashView.swift"] {
            let text = try source(path)
            check(text.contains(".interactiveDismissDisabled(hasEdits)"), "Draft dismissal guard: \(path)")
            check(text.contains(".seshReadableForm()") && text.contains(".seshEditorPresentation()"), "Adaptive themed form: \(path)")
        }
        let thoughts = try source("Journal/ThoughtsView.swift")
        check(thoughts.contains("session.thoughts.first(where:") && thoughts.contains("saveError ="), "Thought edits use live record")
        check(thoughts.contains("confirmVisibility") && thoughts.contains("does not publish"), "Sharing preference confirmation")
        let log = try source("Session/LogSeshView.swift")
        check(log.contains("session.entries.first(where:") && log.contains("hasPendingFields"), "Live entry and pending draft guard")
        check(!log.contains("Double(amount.filter"), "No digit stripping")
        let stash = try source("Stash/StashView.swift")
        check(stash.contains("guard canSave, let parsedCost, let parsedAmount"), "Full stash save guard")
        check(!stash.contains(".onDelete"), "Stash deletes go through confirmation")
        let chat = try source("Social/ChatViews.swift")
        check(chat.contains("if social.send(draft, to: roomID)"), "Composer clears only successful durable enqueue")
        check(chat.contains("chat.unsentDraftError"), "Retained draft error is exposed")
        let banner = try source("CoreUI/ConnectivityBanner.swift")
        check(banner.contains("outbox.retryHeldOperations()") && banner.contains("outbox.statusMessage"), "Outbox recovery wired")
        check(!banner.contains("queue.map") && !banner.contains("ownerID"), "Banner does not expose account payloads")
        print("Journal UI policy and wiring checks passed: \(checks)")
    }
}
