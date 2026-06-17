//
//  SocialModels.swift
//  SESH
//
//  The social layer's data shapes. A "Cypher" (aka Cyph / session) is a shared
//  smoke session people can join. Friends broadcast live activity ("rolling
//  up", "hitting the bong"). Chat rooms and live streams round out the
//  companion experience.
//

import SwiftUI

// MARK: - Friends & presence

/// What a friend is doing right now. Drives the activity ticker and presence dots.
enum SeshActivity: String, Codable, CaseIterable, Identifiable {
    case idle
    case available
    case busy
    case rollingUp        = "rolling_up"
    case smoking
    case hittingBong      = "hitting_bong"
    case packingBowl      = "packing_bowl"
    case lighting
    case inCypher         = "in_cypher"
    case live

    var id: String { rawValue }

    /// Present-tense phrase, e.g. "Shalise is rolling up".
    var phrase: String {
        switch self {
        case .idle:        return "is chilling"
        case .available:   return "is available"
        case .busy:        return "is busy"
        case .rollingUp:   return "is rolling up"
        case .smoking:     return "is smoking"
        case .hittingBong: return "is hitting the bong"
        case .packingBowl: return "is packing a bowl"
        case .lighting:    return "is sparking up"
        case .inCypher:    return "is in a Cypher"
        case .live:        return "is live"
        }
    }

    var emoji: String {
        switch self {
        case .idle:        return "😌"
        case .available:   return "🟢"
        case .busy:        return "⛔️"
        case .rollingUp:   return "🤙"
        case .smoking:     return "💨"
        case .hittingBong: return "🌬️"
        case .packingBowl: return "🥣"
        case .lighting:    return "🔥"
        case .inCypher:    return "🔄"
        case .live:        return "🔴"
        }
    }

    /// Active states show a colored presence ring.
    var isActive: Bool { self != .idle && self != .available && self != .busy }

    var tint: Color {
        switch self {
        case .idle:        return Palette.textSecondary
        case .available:   return Palette.greenBright
        case .busy:        return Palette.moodAngry
        case .live:        return Palette.moodAngry
        case .inCypher:    return Palette.gold
        default:           return Palette.greenBright
        }
    }
}

struct SeshUser: Codable, Identifiable, Hashable {
    var id: String
    var handle: String          // "@shalise"
    var displayName: String     // "Shalise"
    var activity: SeshActivity
    var lastSeen: Date
    var streak: Int             // current daily streak
    var isFriend: Bool

    var initials: String {
        let parts = displayName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

// MARK: - Cyphers (shared sessions)

enum CypherVisibility: String, Codable { case publicCypher = "public", friends, privateCypher = "private" }

struct Cypher: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var hostHandle: String
    var hostName: String
    var strainName: String?
    var participantIDs: [String]
    var maxParticipants: Int
    var isLive: Bool            // host is streaming this Cypher
    var visibility: CypherVisibility
    var startedAt: Date
    var note: String?

    var participantCount: Int { participantIDs.count }
    var isFull: Bool { participantCount >= maxParticipants }
}

// MARK: - Chat

struct ChatRoom: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var topic: String
    var memberCount: Int
    var lastMessage: String?
    var lastMessageAt: Date?
    var unread: Int
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var roomID: String
    var senderHandle: String
    var senderName: String
    var text: String
    var sentAt: Date
    var isMe: Bool
}

// MARK: - Live

struct LiveStream: Codable, Identifiable, Hashable {
    var id: String
    var hostHandle: String
    var hostName: String
    var title: String
    var viewerCount: Int
    var strainName: String?
    var startedAt: Date
    var cypherID: String?       // a live stream may be attached to a Cypher
}

// MARK: - Live session stage (Start Sesh progression)

/// The staged progression of a live, in-the-moment session.
enum SeshStage: String, Codable, CaseIterable, Identifiable {
    case pickingStrain = "Picking Strain"
    case rollingUp     = "Rolling Up"
    case sparkedUp     = "Sparked Up"
    case smoking       = "Smoking"
    case finished      = "Finished"

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .pickingStrain: return "🌿"
        case .rollingUp:     return "🧻"
        case .sparkedUp:     return "🔥"
        case .smoking:       return "💨"
        case .finished:      return "✅"
        }
    }

    /// Extra guidance shown when this is the *current* step (the accordion).
    var detail: String {
        switch self {
        case .pickingStrain: return "Pick what you're smoking. Type a strain name and we'll match it from your library."
        case .rollingUp:     return "Grinding, packing, and rolling. Time your roll to set a personal record, then stop when you spark up."
        case .sparkedUp:     return "Light it up. Take your first hit whenever you're ready."
        case .smoking:       return "Enjoy the sesh. Attach a thought if something comes to mind."
        case .finished:      return "Wrap it up and save this sesh to your journal."
        }
    }

    /// The broadcast activity that mirrors this stage for friends' presence.
    var activity: SeshActivity {
        switch self {
        case .pickingStrain: return .idle
        case .rollingUp:     return .rollingUp
        case .sparkedUp:     return .lighting
        case .smoking:       return .smoking
        case .finished:      return .idle
        }
    }
}

// MARK: - Activity feed item (the social ticker / feed)

struct ActivityEvent: Codable, Identifiable, Hashable {
    var id: String
    var userHandle: String
    var userName: String
    var activity: SeshActivity
    var detail: String?         // e.g. strain or cypher title
    var at: Date

    /// "Shalise is hitting the bong"
    var line: String { "\(userName) \(activity.phrase)" }
}
