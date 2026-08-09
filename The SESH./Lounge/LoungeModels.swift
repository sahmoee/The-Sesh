//
//  LoungeModels.swift
//  The SESH
//
//  (SESH-RL-001-R2 §11) The Lounge's content model.
//
//  Content data is deliberately separate from presentation. A post carries the
//  facts — kind, text, media, visibility, moderation — plus cheap layout hints
//  (character count, media aspect, compatible templates). LoungeLayoutEngine,
//  never the server and never a random shuffle, turns those hints into a
//  concrete template. That split is what makes "organized chaos" reproducible.
//

import Foundation

// MARK: - Author

struct LoungeAuthor: Codable, Hashable, Identifiable {
    var id: String
    var handle: String
    var displayName: String
    var avatarURL: String?
    var isFollowed: Bool = false

    var atHandle: String { handle.hasPrefix("@") ? handle : "@\(handle)" }
}

// MARK: - Post kind

enum LoungePostKind: String, Codable, CaseIterable, Hashable {
    case highThought
    case rant
    case photo
    case video
    case music
    case poll
    case review
    case munchies
    case checkIn
    case live

    /// Category label shown in the post chrome.
    var tagTitle: String {
        switch self {
        case .highThought: return "High Thoughts"
        case .rant:        return "Rants"
        case .photo:       return "Setup"
        case .video:       return "Video"
        case .music:       return "Pass the Aux"
        case .poll:        return "Poll"
        case .review:      return "Review"
        case .munchies:    return "Munchies"
        case .checkIn:     return "Check-In"
        case .live:        return "Live"
        }
    }

    var glyph: String {
        switch self {
        case .highThought: return "brain.head.profile"
        case .rant:        return "text.bubble"
        case .photo:       return "photo"
        case .video:       return "play.rectangle"
        case .music:       return "music.note"
        case .poll:        return "chart.bar"
        case .review:      return "star"
        case .munchies:    return "fork.knife"
        case .checkIn:     return "mappin.and.ellipse"
        case .live:        return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Feed sections & filters

/// §Table 2 — the three feed sections.
enum LoungeTab: String, CaseIterable, Identifiable, Hashable {
    case forYou, following, live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou:    return "For You"
        case .following: return "Following"
        case .live:      return "Live Now"
        }
    }
}

/// §5.1 content filters. These scroll horizontally rather than wrapping into
/// multiple dense rows.
enum LoungeFilter: String, CaseIterable, Identifiable, Hashable {
    case all, highThoughts, music, rants, polls, photos, reviews, munchies, live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:          return "All"
        case .highThoughts: return "High Thoughts"
        case .music:        return "Pass the Aux"
        case .rants:        return "Rants"
        case .polls:        return "Polls"
        case .photos:       return "Photos"
        case .reviews:      return "Reviews"
        case .munchies:     return "Munchies"
        case .live:         return "Live"
        }
    }

    /// Kinds this filter admits. `.all` admits everything.
    func admits(_ kind: LoungePostKind) -> Bool {
        switch self {
        case .all:          return true
        case .highThoughts: return kind == .highThought
        case .music:        return kind == .music
        case .rants:        return kind == .rant
        case .polls:        return kind == .poll
        case .photos:       return kind == .photo || kind == .video
        case .reviews:      return kind == .review
        case .munchies:     return kind == .munchies
        case .live:         return kind == .live
        }
    }
}

// MARK: - Attachments

struct LoungeMedia: Codable, Hashable, Identifiable {
    var id: String
    var url: String
    var posterURL: String?
    var isVideo: Bool = false
    /// width / height. Preserved so media keeps a meaningful shape (§6.2).
    var aspectRatio: Double = 1
    /// Author-supplied VoiceOver description (§12) — surfaced as the image's
    /// accessibility label wherever the media renders.
    var altText: String?

    var isPortrait: Bool { aspectRatio < 0.95 }
    var isWideFormat: Bool { aspectRatio > 1.45 }
}

struct LoungeTrack: Codable, Hashable {
    var title: String
    var artist: String
    var artworkURL: String?
    var previewURL: String?
    var durationSeconds: Double?
    /// Vibe tags shown under the player ("Chill", "Night Drive").
    var vibeTags: [String] = []
}

struct LoungePollChoice: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var votes: Int = 0
}

struct LoungePollContent: Codable, Hashable {
    var question: String
    var choices: [LoungePollChoice]
    var totalVotes: Int = 0
    var endsAt: Date?
    /// Choice the viewer picked. Percentages appear only after voting.
    var viewerChoiceID: String?

    var hasVoted: Bool { viewerChoiceID != nil }

    var isClosed: Bool {
        guard let endsAt else { return false }
        return endsAt <= Date()
    }

    func fraction(for choice: LoungePollChoice) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(choice.votes) / Double(totalVotes)
    }

    /// §Table 3 — 4+ options or long labels force a full-width presentation.
    var needsFullWidth: Bool {
        choices.count >= 4 || choices.contains { $0.label.count > 24 }
    }
}

struct LoungeLiveRoom: Codable, Hashable {
    var roomID: String
    var title: String
    var participantCount: Int = 0
    var participantAvatars: [String] = []
    var vibeTags: [String] = []
    var stillURL: String?
    var isLive: Bool = true
}

// MARK: - Governance

enum LoungeVisibility: String, Codable, Hashable {
    case publicFeed = "public"
    case friendsOnly = "friends"
    case privateLog = "private"
}

enum LoungeModerationState: String, Codable, Hashable {
    case ok, pending, hidden, removed

    /// `pending` still renders to its author; `hidden`/`removed` never render.
    var isDisplayable: Bool { self == .ok || self == .pending }
}

/// §12 report reasons.
enum LoungeReportReason: String, Codable, CaseIterable, Identifiable {
    case minors, sales, dangerous, harassment, spam, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minors:     return "Minors in cannabis content"
        case .sales:      return "Buying, selling, or solicitation"
        case .dangerous:  return "Impaired driving or dangerous behavior"
        case .harassment: return "Harassment or hate"
        case .spam:       return "Spam"
        case .other:      return "Something else"
        }
    }
}

// MARK: - Layout hints (§11)

/// Cheap, precomputed presentation hints stored alongside content so the engine
/// never has to measure text or load media to lay out a feed.
struct LoungeLayoutHints: Codable, Hashable {
    var characterCount: Int = 0
    var primaryAspect: Double?
    var hasMedia: Bool = false
    /// Templates the content can tolerate. The engine picks from this set.
    var supportedTemplates: [LoungeTemplate] = []
    /// Stable for a delivered feed session so shapes never jump on refresh.
    var templateID: String?
}

/// §6.3 — a concrete presentation the engine may choose.
enum LoungeTemplate: String, Codable, Hashable, CaseIterable {
    case bubbleNarrow      // short high thought in a paired column
    case bubbleMedium      // short thought as a 55–75% single-bubble band
    case bubbleFull        // accessibility fallback for a thought
    case textCardWide      // rant in the wide slot of a paired band
    case textCardFull      // long rant / storytime, full width
    case mediaWide         // photo led card, wide slot
    case mediaFull         // photo / video, full width
    case playerMedium      // music player, paired column
    case playerFull        // music player, full width
    case pollMedium        // poll, paired column
    case pollFull          // poll with 4+ options or long labels
    case liveFeature       // featured live preview, full width
    case liveMedium        // live preview in a paired column
    case smallCard         // short status / check-in

    var width: LoungeWidthClass {
        switch self {
        case .bubbleFull, .textCardFull, .mediaFull, .playerFull, .pollFull, .liveFeature:
            return .full
        case .textCardWide, .mediaWide:
            return .wide
        case .bubbleMedium:
            return .medium
        case .bubbleNarrow, .playerMedium, .pollMedium, .liveMedium, .smallCard:
            return .narrow
        }
    }
}

enum LoungeWidthClass: String, Codable, Hashable {
    case full, wide, medium, narrow

    /// Only wide and narrow content may sit inside a paired band.
    var canPair: Bool { self == .wide || self == .narrow }
}

// MARK: - Post

struct LoungePost: Codable, Hashable, Identifiable {
    var id: String
    var author: LoungeAuthor
    var kind: LoungePostKind
    var createdAt: Date
    var text: String = ""
    var media: [LoungeMedia] = []
    var track: LoungeTrack?
    var poll: LoungePollContent?
    var live: LoungeLiveRoom?

    // Optional sesh context — field-level sharing per §12.
    var strainName: String?
    var method: String?
    var mood: String?
    var vibeTags: [String] = []

    // Engagement
    var reactionCount: Int = 0
    var commentCount: Int = 0
    var viewerHasReacted: Bool = false

    // Governance
    var visibility: LoungeVisibility = .publicFeed
    var moderation: LoungeModerationState = .ok

    var layout: LoungeLayoutHints = LoungeLayoutHints()
}

extension LoungePost {
    /// §Table 3 — "short high thought (<=180 chars)".
    static let shortTextLimit = 180
    /// Past this, text must get full width or a Read More rather than be squeezed.
    static let readMoreLimit = 280

    var characterCount: Int {
        layout.characterCount > 0 ? layout.characterCount : text.count
    }

    var isShortText: Bool { characterCount <= Self.shortTextLimit }
    var isLongForm: Bool { characterCount > Self.readMoreLimit }

    var primaryMedia: LoungeMedia? { media.first }
    var hasMedia: Bool { !media.isEmpty }

    var aspect: Double {
        layout.primaryAspect ?? primaryMedia?.aspectRatio ?? 1
    }

    /// Belt-and-braces: the Worker already filters at query level (§12), but a
    /// private or removed post must never render even if one slips through.
    var passesClientVisibility: Bool {
        moderation.isDisplayable && visibility != .privateLog
    }

    /// Short relative age, e.g. "3h".
    var ageText: String { LoungeAge.text(since: createdAt) }

    /// Age as a phrase safe to append to a sentence — avoids "now ago".
    var agePhrase: String { LoungeAge.phrase(since: createdAt) }
}

// MARK: - Shared relative-age formatting

enum LoungeAge {
    /// Short relative age, e.g. "3h" (or "now" under a minute).
    static func text(since date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// Sentence-safe phrase: "just now" or "3h ago" — never "now ago".
    static func phrase(since date: Date) -> String {
        let short = text(since: date)
        return short == "now" ? "just now" : "\(short) ago"
    }
}

// MARK: - Paging

/// One delivered page. `sessionID` keys template stability (§11): as long as the
/// session is unchanged, a post keeps the same shape across refreshes.
struct LoungeFeedPage: Codable, Hashable {
    var posts: [LoungePost]
    var nextCursor: String?
    var sessionID: String

    var hasMore: Bool { nextCursor != nil }
}

// MARK: - Comments (Phase 3)

struct LoungeComment: Codable, Hashable, Identifiable {
    var id: String
    var author: LoungeAuthor
    var text: String
    var createdAt: Date
    var reactionCount: Int = 0

    var ageText: String { LoungeAge.text(since: createdAt) }
}

struct LoungePostDetail: Codable, Hashable {
    var post: LoungePost
    var comments: [LoungeComment] = []
}
