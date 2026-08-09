//
//  LoungeLayoutEngine.swift
//  The SESH
//
//  (SESH-RL-001-R2 §6) Organized chaos, deterministically.
//
//  The feed must feel spontaneous because the *content* varies, not because the
//  interface is careless. So there is no randomness here: given the same ordered
//  posts and the same feed session id, this engine always returns the same
//  bands. Variation comes from content shape plus a stable hash of the post id,
//  which means a refresh or a re-render never reshuffles what the user is
//  already looking at (§11).
//
//  Hard rules enforced below:
//    • Reading order is top-to-bottom, left-then-right inside a paired band.
//    • Nothing overlaps; a band owns its row.
//    • Long text is never squeezed into a narrow column.
//    • Two dominant posts never share a row (that's how masonry creeps in).
//    • A full-width band recurs periodically to reset reading rhythm.
//

import Foundation
import CoreGraphics

// MARK: - Placement & bands

/// A post bound to the template the engine chose for it.
struct LoungePlacement: Identifiable, Hashable {
    var post: LoungePost
    var template: LoungeTemplate

    var id: String { post.id }
}

enum LoungeBubbleSide: String, Hashable {
    case leading, trailing
}

/// One horizontal band of the feed (§6.1).
enum LoungeBand: Identifiable, Hashable {
    case full(LoungePlacement)
    case wideNarrow(LoungePlacement, LoungePlacement)
    case narrowWide(LoungePlacement, LoungePlacement)
    case pairedShort(LoungePlacement, LoungePlacement)
    case singleBubble(LoungePlacement, side: LoungeBubbleSide, widthFraction: Double)

    /// In reading order.
    var placements: [LoungePlacement] {
        switch self {
        case .full(let p):                 return [p]
        case .wideNarrow(let a, let b):    return [a, b]
        case .narrowWide(let a, let b):    return [a, b]
        case .pairedShort(let a, let b):   return [a, b]
        case .singleBubble(let p, _, _):   return [p]
        }
    }

    var id: String { placements.map(\.id).joined(separator: "+") }
}

// MARK: - Metrics

/// Pure geometry constants. Explicitly `nonisolated` because the target builds
/// with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make
/// these MainActor-isolated — and `LoungeSplit: Layout` needs them in a
/// nonisolated context for its memberwise init's default value.
enum LoungeMetrics {
    nonisolated static let horizontalPadding: CGFloat = 14
    nonisolated static let gutter: CGFloat = 10
    nonisolated static let bandSpacing: CGFloat = 12
    /// Paired-band column split. Wide + narrow + gutter == available width.
    nonisolated static let wideFraction: CGFloat = 0.58
    nonisolated static let narrowFraction: CGFloat = 0.42
}

// MARK: - Engine

enum LoungeLayoutEngine {

    /// Paired/bubble bands allowed before a full-width reset (§6.1).
    static let fullWidthResetInterval = 3

    /// Deterministic band plan for an ordered page of posts.
    ///
    /// - Parameters:
    ///   - posts: feed order from the server. Never reordered here.
    ///   - sessionID: stable id of the delivered feed session.
    ///   - forceFullWidth: accessibility escape hatch — at large dynamic type
    ///     every post takes the full row so nothing gets truncated.
    static func plan(posts: [LoungePost],
                     sessionID: String,
                     forceFullWidth: Bool = false) -> [LoungeBand] {
        let visible = posts.filter(\.passesClientVisibility)
        var bands: [LoungeBand] = []
        var index = 0
        var sinceFullWidth = 0

        while index < visible.count {
            let post = visible[index]

            // 1. Content that must own the row, or a periodic rhythm reset.
            if forceFullWidth || requiresFullWidth(post) || sinceFullWidth >= fullWidthResetInterval {
                bands.append(.full(LoungePlacement(post: post, template: fullTemplate(for: post))))
                index += 1
                sinceFullWidth = 0
                continue
            }

            // 2. Try to pair with the next post.
            if index + 1 < visible.count,
               let band = pair(post, visible[index + 1], sessionID: sessionID) {
                bands.append(band)
                index += 2
                sinceFullWidth += 1
                continue
            }

            // 3. A lone concise post gets intentional breathing room (§6.1/6.2):
            //    55–75% width, alternating side, empty space left deliberately.
            if isConcise(post) {
                let h = stableHash("\(sessionID):\(post.id)")
                let side: LoungeBubbleSide = (h % 2 == 0) ? .leading : .trailing
                let fraction = 0.55 + Double(h % 21) / 100.0
                bands.append(.singleBubble(LoungePlacement(post: post, template: .bubbleMedium),
                                           side: side,
                                           widthFraction: fraction))
                index += 1
                sinceFullWidth += 1
                continue
            }

            // 4. Everything else takes the full row.
            bands.append(.full(LoungePlacement(post: post, template: fullTemplate(for: post))))
            index += 1
            sinceFullWidth = 0
        }

        return bands
    }

    // MARK: Pairing

    private static func pair(_ a: LoungePost, _ b: LoungePost, sessionID: String) -> LoungeBand? {
        guard !requiresFullWidth(a), !requiresFullWidth(b) else { return nil }

        // Two concise items side by side — only when both fit without truncating.
        if isConcise(a) && isConcise(b) {
            return .pairedShort(LoungePlacement(post: a, template: concisePairTemplate(a)),
                                LoungePlacement(post: b, template: concisePairTemplate(b)))
        }

        // One visually dominant post + one concise post. The slot order follows
        // the real feed order — posts are never swapped to fit a nicer shape,
        // which is what keeps reading order unambiguous.
        if isDominant(a) && isConcise(b) {
            return .wideNarrow(LoungePlacement(post: a, template: dominantPairTemplate(a)),
                               LoungePlacement(post: b, template: concisePairTemplate(b)))
        }
        if isConcise(a) && isDominant(b) {
            return .narrowWide(LoungePlacement(post: a, template: concisePairTemplate(a)),
                               LoungePlacement(post: b, template: dominantPairTemplate(b)))
        }

        // Two dominant posts never share a row.
        return nil
    }

    // MARK: Content predicates

    /// Content that must own the full row.
    static func requiresFullWidth(_ post: LoungePost) -> Bool {
        if post.kind == .video { return true }
        if post.kind == .live { return true }       // live previews are featured
        if post.kind == .review { return true }
        if post.isLongForm { return true }          // §6.2 long text is never narrow
        if let poll = post.poll, poll.needsFullWidth { return true }
        if let media = post.primaryMedia, media.isWideFormat { return true }
        return false
    }

    /// Short, text-only content that reads fine in a narrow column.
    static func isConcise(_ post: LoungePost) -> Bool {
        guard !post.hasMedia else { return false }
        switch post.kind {
        case .highThought, .checkIn, .rant: return post.isShortText
        default:                            return false
        }
    }

    /// Visually dominant content that deserves the wide slot.
    static func isDominant(_ post: LoungePost) -> Bool {
        if post.hasMedia { return true }
        switch post.kind {
        case .music, .poll, .munchies: return true
        default:                      return false
        }
    }

    // MARK: Template choice

    static func fullTemplate(for post: LoungePost) -> LoungeTemplate {
        switch post.kind {
        case .video, .photo, .munchies: return .mediaFull
        case .music:                    return .playerFull
        case .poll:                     return .pollFull
        case .live:                     return .liveFeature
        case .rant, .review:            return .textCardFull
        case .highThought, .checkIn:    return post.hasMedia ? .mediaFull : .bubbleFull
        }
    }

    private static func dominantPairTemplate(_ post: LoungePost) -> LoungeTemplate {
        if post.hasMedia { return .mediaWide }
        switch post.kind {
        case .music: return .playerMedium
        case .poll:  return .pollMedium
        case .live:  return .liveMedium
        default:     return .textCardWide
        }
    }

    private static func concisePairTemplate(_ post: LoungePost) -> LoungeTemplate {
        post.kind == .checkIn ? .smallCard : .bubbleNarrow
    }

    // MARK: Hints

    /// §6.3 — the template set a piece of content can tolerate, best first.
    static func supportedTemplates(for post: LoungePost) -> [LoungeTemplate] {
        switch post.kind {
        case .highThought:
            return post.isShortText
                ? [.bubbleNarrow, .bubbleMedium, .bubbleFull]
                : [.bubbleFull, .textCardFull]
        case .rant:
            return post.isLongForm ? [.textCardFull] : [.textCardWide, .textCardFull]
        case .photo, .munchies:
            return [.mediaWide, .mediaFull]
        case .video:
            return [.mediaFull]
        case .music:
            return [.playerMedium, .playerFull]
        case .poll:
            return (post.poll?.needsFullWidth ?? false) ? [.pollFull] : [.pollMedium, .pollFull]
        case .live:
            return [.liveFeature, .liveMedium]
        case .review:
            return [.textCardFull, .textCardWide]
        case .checkIn:
            return [.smallCard, .bubbleNarrow]
        }
    }

    /// Fills in layout hints for a post that arrived without them, and pins a
    /// stable templateID for this feed session (§11).
    static func hydrate(_ post: LoungePost, sessionID: String) -> LoungePost {
        var p = post
        if p.layout.characterCount == 0 { p.layout.characterCount = p.text.count }
        p.layout.hasMedia = p.hasMedia
        if p.layout.primaryAspect == nil { p.layout.primaryAspect = p.primaryMedia?.aspectRatio }
        if p.layout.supportedTemplates.isEmpty {
            p.layout.supportedTemplates = supportedTemplates(for: p)
        }
        if p.layout.templateID == nil {
            p.layout.templateID = "\(sessionID):\(p.id)"
        }
        return p
    }

    /// FNV-1a. Deterministic across launches and processes, unlike `Hasher`,
    /// whose seed is randomized per process — using it here would reshuffle
    /// the feed on every cold start.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
