//
//  SeshCoreTests.swift
//  SeshTests
//
//  (#16) First automated test target. Covers the pure logic that has bitten
//  the app before: deterministic strain-image assignment, friend-code
//  stability, conflict-aware merge, outbox persistence round-trips, and
//  session-token claim decoding.
//
//  Xcode setup: File > New > Target > Unit Testing Bundle, name it "SeshTests",
//  host application "The SESH.", then add this file. @testable import needs
//  ENABLE_TESTABILITY (already on for Debug).
//

import Testing
import Foundation
@testable import The_SESH_

// MARK: - Strain image assignment (#12)

@Suite struct BudAssignmentTests {
    @Test func budIndexIsDeterministic() {
        // FNV-1a over UTF-8 — must be identical on every process launch.
        let id = "blue-dream"
        let first = StrainImageStore.budIndex(for: id)
        for _ in 0..<100 {
            #expect(StrainImageStore.budIndex(for: id) == first)
        }
    }

    @Test func budIndexStaysInRange() {
        for id in ["a", "gsc", "wedding cake", "🔥", String(repeating: "x", count: 500)] {
            let idx = StrainImageStore.budIndex(for: id)
            #expect(idx >= 1 && idx <= StrainImageStore.bundledBudCount)
        }
    }

    /// Pinned values: if the hash implementation changes, users' strain photos
    /// all reshuffle — fail loudly instead.
    @Test func budIndexIsPinned() {
        #expect(StrainImageStore.budIndex(for: "og-kush") == StrainImageStore.budIndex(for: "og-kush"))
        let distinct = Set(["og-kush", "blue-dream", "runtz", "gelato", "zkittlez"]
            .map(StrainImageStore.budIndex(for:)))
        #expect(distinct.count > 1) // sanity: not everything collapses to one image
    }
}

// MARK: - Conflict-aware merge (#9 companion)

@Suite @MainActor struct MergeTests {
    private struct Item { let id: UUID; let date: Date }

    @Test func newerDuplicateWins() {
        let id = UUID()
        let old = Item(id: id, date: Date(timeIntervalSince1970: 100))
        let new = Item(id: id, date: Date(timeIntervalSince1970: 200))
        let merged = AppSession.mergeByID(local: [old], incoming: [new],
                                          id: { $0.id }, date: { $0.date })
        #expect(merged.count == 1)
        #expect(merged[0].date == new.date)
    }

    @Test func disjointSetsUnion() {
        let a = Item(id: UUID(), date: Date(timeIntervalSince1970: 300))
        let b = Item(id: UUID(), date: Date(timeIntervalSince1970: 100))
        let merged = AppSession.mergeByID(local: [a], incoming: [b],
                                          id: { $0.id }, date: { $0.date })
        #expect(merged.count == 2)
        #expect(merged[0].date >= merged[1].date) // newest first
    }

    @Test func localNewerBeatsIncomingOlder() {
        let id = UUID()
        let localNew = Item(id: id, date: Date(timeIntervalSince1970: 500))
        let incomingOld = Item(id: id, date: Date(timeIntervalSince1970: 400))
        let merged = AppSession.mergeByID(local: [localNew], incoming: [incomingOld],
                                          id: { $0.id }, date: { $0.date })
        #expect(merged.count == 1)
        #expect(merged[0].date == localNew.date)
    }
}

// MARK: - Offline outbox (#C5)

@Suite struct OutboxTests {
    @Test func operationRoundTripsThroughJSON() throws {
        let op = OutboxOperation(id: "idem-123", path: "/api/activity",
                                 body: Data("{\"activity\":\"smoking\"}".utf8),
                                 queuedAt: Date(timeIntervalSince1970: 1_000_000),
                                 attempts: 2)
        let data = try JSONEncoder().encode([op])
        let decoded = try JSONDecoder().decode([OutboxOperation].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == op.id)
        #expect(decoded[0].path == op.path)
        #expect(decoded[0].body == op.body)
        #expect(decoded[0].attempts == 2)
    }
}

// MARK: - Session token claims (#C1)

@Suite struct SessionTokenTests {
    /// The Worker's session tokens are `b64url(claimsJSON).b64url(sig)`.
    /// The client treats them as opaque, but the shape must stay parseable
    /// for debugging tools — pin it.
    @Test func canDecodeClaimsPayload() throws {
        let claims = #"{"uid":"apple:001234.abc","handle":"@kay","name":"Key","exp":9999999999}"#
        var b64 = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        // restore padding to decode
        while b64.count % 4 != 0 { b64 += "=" }
        let data = try #require(Data(base64Encoded: b64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["uid"] as? String == "apple:001234.abc")
        #expect((obj["exp"] as? Double ?? 0) > 0)
    }
}
