//
//  SeshHardeningTests.swift
//  SeshTests
//
//  Pins the crash, data-preservation and input-validation fixes from the
//  portfolio refinement batch: timer/duration formatting that used to trap in
//  Int(_:), budget parsing, photo-name path safety, deep-link friend codes,
//  stash amount lines and the sparkline's VoiceOver summary.
//

import Testing
import Foundation
@testable import The_SESH_

// MARK: - Duration formatting

@Suite @MainActor struct DurationFormattingTests {
    @Test func normalIntervalsFormat() {
        #expect(seshDuration(0) == "0:00")
        #expect(seshDuration(65) == "1:05")
        #expect(seshDuration(3_725) == "1:02:05")
    }

    @Test func negativeOrNonFiniteIntervalsDoNotTrap() {
        // A clock moved backwards after a sesh started yields a negative interval.
        #expect(seshDuration(-30) == "0:00")
        #expect(seshDuration(.nan) == "0:00")
        #expect(seshDuration(.infinity) == "0:00")
        #expect(seshDuration(1e300) == "999:00:00")
    }

    @Test func loungeTimestampRejectsOutOfRangeServerValues() {
        #expect(LoungePlayerCard.timestamp(75) == "1:15")
        #expect(LoungePlayerCard.timestamp(.nan) == "--:--")
        #expect(LoungePlayerCard.timestamp(-1) == "--:--")
        #expect(LoungePlayerCard.timestamp(1e300) == "--:--")
    }
}

// MARK: - Budget input

@Suite @MainActor struct BudgetParsingTests {
    @Test func acceptsOrdinaryAmountsWithEitherSeparator() {
        #expect(BudgetView.parseBudget("120") == 120)
        #expect(BudgetView.parseBudget(" 12.50 ") == 12.5)
        #expect(BudgetView.parseBudget("12,5") == 12.5)
    }

    @Test func rejectsValuesThatUsedToCrashOnReopen() {
        #expect(BudgetView.parseBudget("inf") == nil)
        #expect(BudgetView.parseBudget("nan") == nil)
        #expect(BudgetView.parseBudget("1e30") == nil)
        #expect(BudgetView.parseBudget("0") == nil)
        #expect(BudgetView.parseBudget("-5") == nil)
        #expect(BudgetView.parseBudget("") == nil)
    }

    @Test func editableTextKeepsCentsAndNeverTraps() throws {
        let text = BudgetView.editableText(12.5)
        // Locale-independent: whatever the separator, it parses back unchanged.
        #expect(BudgetView.parseBudget(text) == 12.5)
        #expect(BudgetView.editableText(.infinity) == "")
        #expect(BudgetView.editableText(.nan) == "")
        #expect(!BudgetView.editableText(1e22).isEmpty)
    }
}

// MARK: - Photo names

@Suite struct PhotoNameSafetyTests {
    @Test func plainGeneratedNamesAreAccepted() {
        #expect(PhotoStore.isSafeName("sesh_\(UUID().uuidString).jpg"))
    }

    @Test func traversalAndSeparatorsAreRejected() {
        for name in ["", ".", "..", "../Library/Preferences/x.plist", "a/b.jpg", "a\\b.jpg",
                     ".hidden", "x\0.jpg", String(repeating: "a", count: 300)] {
            #expect(!PhotoStore.isSafeName(name), "\(name) should be rejected")
        }
    }
}

// MARK: - Deep links

@Suite @MainActor struct FriendDeepLinkTests {
    @Test func wellFormedFriendCodeParses() throws {
        let url = try #require(URL(string: "sesh://friend/sesh-7k9f"))
        guard case .addFriend(let code)? = SeshDeepLink(url: url) else {
            Issue.record("Expected an addFriend link"); return
        }
        #expect(code == "SESH-7K9F")
    }

    @Test func malformedFriendCodesAreRejected() throws {
        for raw in ["sesh://friend/", "sesh://friend/ab",
                    "sesh://friend/" + String(repeating: "A", count: 40),
                    "sesh://friend/SESH%207K9F", "sesh://friend/%3Cscript%3E"] {
            let url = try #require(URL(string: raw))
            #expect(!isAddFriend(SeshDeepLink(url: url)), "\(raw)")
        }
    }

    @Test func codeValidator() {
        #expect(SeshDeepLink.isWellFormedFriendCode("SESH-7K9F"))
        #expect(!SeshDeepLink.isWellFormedFriendCode("SESH 7K9F"))
        #expect(!SeshDeepLink.isWellFormedFriendCode("ÅÄÖÜ-1234"))
    }

    private func isAddFriend(_ link: SeshDeepLink?) -> Bool {
        if case .addFriend? = link { return true }
        return false
    }
}

// MARK: - Stash amount line

@Suite @MainActor struct PurchaseAmountLineTests {
    @Test func hugeAmountsDoNotTrap() {
        let p = Purchase(strain: "Runtz", amount: 1e30, unit: "g", cost: 10)
        #expect(p.amountLine.hasSuffix(" g"))
    }

    @Test func wholeAndFractionalAmountsKeepTheirShape() {
        var p = Purchase(strain: "Runtz", amount: 3.5, unit: "g", cost: 30)
        p.used = 1
        let line = p.amountLine
        #expect(line.hasSuffix(" g"))
        #expect(line.contains("/"))
    }
}

// MARK: - Sparkline VoiceOver summary

@Suite @MainActor struct SparklineAccessibilityTests {
    @Test func summaries() {
        #expect(Sparkline.accessibilitySummary([]) == "No ratings yet")
        #expect(Sparkline.accessibilitySummary([.nan]) == "No ratings yet")
        #expect(Sparkline.accessibilitySummary([4, 9, 7]).hasPrefix("3 ratings. Latest 7."))
    }
}
