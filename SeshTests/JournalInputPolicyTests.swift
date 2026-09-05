import Testing
import Foundation
@testable import The_SESH_

@Suite struct JournalInputPolicyTests {
    @Test func localizedAmountIsNotSilentlyRewritten() {
        #expect(JournalInputPolicy.decimal("1,25", locale: Locale(identifier: "de_DE")) == 1.25)
        for text in ["-1", "1g", "1,250", "1.2.3", "1e3", "nan"] {
            #expect(JournalInputPolicy.decimal(text, locale: Locale(identifier: "en_US")) == nil)
        }
    }

    @Test func editingRetainsHistoricalPrecision() {
        let locale = Locale(identifier: "de_DE")
        for number in [0.125, 1.23456789, 0.000000001] {
            #expect(JournalInputPolicy.decimal(JournalInputPolicy.editableDecimal(number, locale: locale), locale: locale) == number)
        }
    }

    @Test func searchFoldsAccentsAndSurroundingWhitespace() {
        #expect(JournalInputPolicy.matches("  CAFE\n", fields: ["Café notes"]))
        #expect(JournalInputPolicy.matches("\n", fields: []))
        #expect(!JournalInputPolicy.matches("missing", fields: ["notes"]))
    }

    @Test func draftFingerprintCannotCollideAtSeparators() {
        #expect(JournalInputPolicy.fingerprint(["a|b", "c"]) != JournalInputPolicy.fingerprint(["a", "b|c"]))
        #expect(JournalInputPolicy.fingerprint(["a,b", ""]) != JournalInputPolicy.fingerprint(["a", "b,"]))
    }

    @Test func metricSortDoesNotBecomeDateSort() {
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)
        #expect(JournalInputPolicy.precedes(metric: 9, date: older, id: "a", otherMetric: 2, otherDate: newer, otherID: "b", usesMetric: true))
        #expect(!JournalInputPolicy.precedes(metric: 9, date: older, id: "a", otherMetric: 2, otherDate: newer, otherID: "b", usesMetric: false))
    }

    @Test func missingMetricComesLastAndTiesAreStable() {
        let date = Date(timeIntervalSince1970: 1)
        #expect(JournalInputPolicy.precedes(metric: 0, date: date, id: "a", otherMetric: nil, otherDate: date, otherID: "b", usesMetric: true))
        #expect(JournalInputPolicy.precedes(metric: 5, date: date, id: "a", otherMetric: 5, otherDate: date, otherID: "b", usesMetric: true))
        #expect(!JournalInputPolicy.precedes(metric: 5, date: date, id: "a", otherMetric: 5, otherDate: date, otherID: "a", usesMetric: true))
    }
}
