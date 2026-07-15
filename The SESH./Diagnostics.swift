//
//  Diagnostics.swift
//  The SESH
//
//  (#17) Structured diagnostics. One place to get a Logger, emit signposts
//  around interesting spans, and mint per-request IDs that the Worker echoes
//  into its own logs — a failing request can be traced end to end instead of
//  disappearing into a silent `try?`.
//

import Foundation
import os

enum Diag {
    static let subsystem = "com.sowens.The-SESH-"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static let network = logger("network")
    static let persistence = logger("persistence")
    static let social = logger("social")

    private static let signposter = OSSignposter(subsystem: subsystem, category: "spans")

    /// Wrap an async span in a signpost interval for Instruments.
    static func span<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    /// Short unique id attached to every API call as X-Request-ID.
    static func requestID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}
