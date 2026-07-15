//
//  SocialCache.swift
//  The SESH
//
//  (#15) Persisted server-state cache. The last good snapshot and each room's
//  last message page are written to disk, so the social screens have real
//  content immediately on a cold offline launch instead of empty states.
//  (#C8) The snapshot's ETag (a server revision) is stored alongside it and
//  sent back as If-None-Match — an unchanged snapshot costs a 304 with no
//  body instead of a full download.
//

import Foundation

@MainActor
enum SocialCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("social", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: Snapshot + ETag

    static func saveSnapshot(_ s: SeshSnapshot, etag: String?) {
        if let data = try? encoder.encode(s) {
            try? data.write(to: dir.appendingPathComponent("snapshot.json"), options: .atomic)
        }
        if let etag {
            try? Data(etag.utf8).write(to: dir.appendingPathComponent("snapshot.etag"), options: .atomic)
        }
    }

    static func loadSnapshot() -> SeshSnapshot? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.json")) else { return nil }
        return try? decoder.decode(SeshSnapshot.self, from: data)
    }

    static func snapshotETag() -> String? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.etag")) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Room messages

    static func saveMessages(_ msgs: [ChatMessage], roomID: String) {
        guard let data = try? encoder.encode(msgs.suffix(200)) else { return }
        try? data.write(to: dir.appendingPathComponent("room-\(roomID).json"), options: .atomic)
    }

    static func loadMessages(roomID: String) -> [ChatMessage]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("room-\(roomID).json")) else { return nil }
        return try? decoder.decode([ChatMessage].self, from: data)
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: dir)
    }
}
