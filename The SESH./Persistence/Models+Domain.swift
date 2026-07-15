//
//  Models+Domain.swift
//  The SESH
//
//  Split out of Models.swift (#3 — file size). No code changes.
//

import SwiftUI

enum Mood: String, CaseIterable, Identifiable, Codable {
    case couchPotato = "Couch Potato"
    case energetic   = "Energetic"
    case errandReady = "Errand Ready"
    case productive  = "Productive"
    case chill       = "Chill"
    case other       = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .couchPotato: return "sofa"
        case .energetic:   return "bolt.fill"
        case .errandReady: return "cart"
        case .productive:  return "checkmark.square"
        case .chill:       return "leaf.fill"
        case .other:       return "plus"
        }
    }
}

// MARK: - Category / List

/// The Vault: where a strain lands after a sesh. Case names are kept stable for
/// code references; the labels/meaning are the new Vault taxonomy.
enum SeshCategory: String, CaseIterable, Identifiable, Codable {
    case personalFaves = "Favorites"     // 🏆 the best of the best
    case goodEnough    = "Reliable"      // 👍 consistently good, buy again
    case lastResort    = "Situational"   // 🤷 depends on mood/setting/time
    case neverAgain    = "Never Again"   // 🚫 poor experience

    var id: String { rawValue }

    /// Migrate a legacy stored rawValue to the current one. #vault migration
    /// nonisolated: pure string mapping, called from nonisolated SwiftData
    /// model conversions (SDJournalEntry.asStruct) under Swift 6's default
    /// MainActor isolation.
    nonisolated static func migrate(_ raw: String) -> String {
        switch raw {
        case "Personal Faves": return SeshCategory.personalFaves.rawValue
        case "Good Enough":    return SeshCategory.goodEnough.rawValue
        case "Last Resort":    return SeshCategory.lastResort.rawValue
        default:               return raw   // "Never Again" and current names unchanged
        }
    }

    /// Lenient decoding so entries saved under the old labels still load and are
    /// migrated to the new Vault names automatically.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let c = SeshCategory(rawValue: SeshCategory.migrate(raw)) {
            self = c
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown SeshCategory: \(raw)"))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    var emoji: String {
        switch self {
        case .personalFaves: return "🏆"
        case .goodEnough:    return "👍"
        case .lastResort:    return "🤷"
        case .neverAgain:    return "🚫"
        }
    }

    var blurb: String {
        switch self {
        case .personalFaves: return "The best of the best. Actively seek these out."
        case .goodEnough:    return "Consistently good. You'd buy again without hesitation."
        case .lastResort:    return "Depends on mood, setting, or time of day."
        case .neverAgain:    return "Poor experience — bad effects, taste, or anxiety."
        }
    }

    var symbol: String {
        switch self {
        case .personalFaves: return "trophy.fill"
        case .goodEnough:    return "hand.thumbsup.fill"
        case .lastResort:    return "questionmark.circle"
        case .neverAgain:    return "xmark.octagon"
        }
    }
}

enum SmokeAgain: String, CaseIterable, Identifiable, Codable {
    case definitely = "Definitely"
    case maybe      = "Maybe"
    case no         = "No"
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .definitely: return "✅"
        case .maybe:      return "🤔"
        case .no:         return "❌"
        }
    }

    /// Lenient decoding so older entries saved as "yes" still load.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "yes", "Yes", "Definitely": self = .definitely
        case "Maybe":                    self = .maybe
        default:                          self = .no
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

// MARK: - Entry

struct JournalEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var strain: String
    var extraStrains: [String]? = nil  // additional strains in the same sesh (#multi-strain)
    var method: String           // "Roll up / Method Used"
    var rating: Double           // 1...10
    var mood: Mood?
    var smokeAgain: SmokeAgain?
    var category: SeshCategory?
    var customCategory: String? = nil  // user-defined category name (#custom categories)
    var notes: String
    var price: Double?
    var photoName: String?       // optional asset reference (placeholder)

    // — Spec additions (all optional so older saved entries decode cleanly) —
    var sessionType: String?     // legacy single session type (kept for back-compat)
    var sessionTags: [String]? = nil   // multi-select Session Tags (#vault rebuild)
    var champion: String? = nil        // "Why are you saving this?" — only for Favorites
    var durationMinutes: Int?    // from a live Start Sesh
    var companions: [String]?    // "Smoked with Jessie & Sarah"
    var effects: [String]?       // multi-select effects from the spec
    var attachedThoughtID: UUID? // a thought captured during the sesh
    var moodBefore: Int?         // 0...4 (rough...great) — #6 mood shift
    var moodAfter: Int?          // 0...4
    var amount: Double?          // quantity consumed — #2/#3 dosage
    var amountUnit: String?      // "g", "hits", "mg" (edibles), etc.

    var isFavorite: Bool { category == .personalFaves }

    /// Mood change across the sesh (after − before), if both were recorded. #6
    var moodShift: Int? {
        guard let moodBefore, let moodAfter else { return nil }
        return moodAfter - moodBefore
    }

    /// "2.0 g" / "3 hits" / "10 mg", if recorded. #2/#3
    var amountLine: String? {
        guard let amount, let amountUnit, !amountUnit.isEmpty else { return nil }
        let n = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.1f", amount)
        return "\(n) \(amountUnit)"
    }

    /// "Smoked with Jessie & Sarah" or nil for solo.
    var companionLine: String? {
        guard let companions, !companions.isEmpty else { return nil }
        if companions.count == 1 { return "Smoked with \(companions[0])" }
        if companions.count == 2 { return "Smoked with \(companions[0]) & \(companions[1])" }
        let head = companions.dropLast().joined(separator: ", ")
        return "Smoked with \(head) & \(companions.last!)"
    }

    // Identity-based equality. Each entry has a stable `id`, so comparing by id
    // is both correct and far cheaper than the compiler-synthesized field-by-field
    // version (which was slow enough to trip the type-checker's budget).
    static func == (lhs: JournalEntry, rhs: JournalEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Shared 0...4 mood scale labels/faces (used by logs). #6
/// (Named *Info to avoid colliding with the MoodScale picker View in Components.)
enum MoodScaleInfo {
    static let faces = ["😣", "🙁", "😐", "🙂", "😄"]
    static let labels = ["Rough", "Meh", "Okay", "Good", "Great"]
    static func face(_ v: Int) -> String { faces[Swift.max(0, Swift.min(4, v))] }
    static func label(_ v: Int) -> String { labels[Swift.max(0, Swift.min(4, v))] }
}

/// A stash purchase: what you bought, when, how much, and what it cost. #stash
/// Sessions can draw down `amount` as you consume, so `remaining` reflects what's
/// left. Codable so it persists alongside entries.
struct Purchase: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var strain: String
    var amount: Double          // total bought, in `unit`
    var unit: String            // "g", "eighth", "oz", etc.
    var cost: Double            // what you paid
    var used: Double = 0        // amount consumed so far (drawn down by sessions)

    var remaining: Double { max(0, amount - used) }
    var isEmpty: Bool { remaining <= 0.0001 }
    /// Cost per unit, for value comparisons.
    var costPerUnit: Double { amount > 0 ? cost / amount : 0 }
    var amountLine: String {
        let r = remaining.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(remaining)) : String(format: "%.1f", remaining)
        let t = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.1f", amount)
        return "\(r) / \(t) \(unit)"
    }
}

/// A resumable in-progress live sesh. Persisted so leaving the Cyph tab doesn't
/// end the sesh. #persisted sessions
struct LiveSeshState: Codable {
    var startedAt: Date
    var stageRaw: String          // SeshStage.rawValue
    var sessionTypeRaw: String    // SessionType.rawValue
    var strainName: String
    var attachedThought: String
    var rollFinalSeconds: Int?
    var rollMethod: String
    var invited: [String]

    var stage: SeshStage { SeshStage(rawValue: stageRaw) ?? .pickingStrain }
    var sessionType: SessionType { SessionType(rawValue: sessionTypeRaw) ?? .relaxing }
    /// Elapsed time since the sesh began (live timers resume from here).
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }
}

/// A full "Your sesh Year" summary. #YearlyRecap
struct YearRecap {
    let year: Int
    let sessions: Int
    let favoriteStrain: String?
    let favoriteEffect: String?
    let mostActiveMonth: String?
    let thoughtOfYear: String?
    let moneySpent: Double
    let uniqueStrains: Int
    /// Top Cyph friend isn't tracked yet (no friend-interaction history).
    var topCyphFriend: String? { nil }
}

/// Reason a strain is saved to Favorites — powers "Your Current Champions" in
/// Insights. Only shown when adding to the Favorites vault. #champions
enum Champion: String, CaseIterable, Identifiable, Codable {
    case bestOverall    = "Best Overall"
    case bestRelaxation = "Best Relaxation"
    case bestCreativity = "Best Creativity"
    case bestGaming     = "Best Gaming"
    case bestMovies     = "Best Movies"
    case bestDeep       = "Best Deep Thoughts"
    case bestSocial     = "Best Social"
    case bestSleep      = "Best Sleep"
    case funniest       = "Funniest High"
    case bestBody       = "Best Body High"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .bestOverall:    return "🏆"
        case .bestRelaxation: return "😌"
        case .bestCreativity: return "🎨"
        case .bestGaming:     return "🎮"
        case .bestMovies:     return "🎬"
        case .bestDeep:       return "💭"
        case .bestSocial:     return "👥"
        case .bestSleep:      return "🌙"
        case .funniest:       return "😂"
        case .bestBody:       return "🔥"
        }
    }
}

/// Session vibe/type from the live Start Sesh flow and Log Sesh.
enum SessionType: String, CaseIterable, Identifiable, Codable {
    // The Session Tags from the spec — separate from the Vault and from Effects.
    case relaxing     = "Relaxing"
    case creative     = "Creative"
    case funny        = "Funny"
    case gaming       = "Gaming"
    case movieNight   = "Movie Night"
    case productive   = "Productive"
    case munchies     = "Munchies"
    case deepThinking = "Deep Thinking"
    case social       = "Social"
    case sleep        = "Sleep"
    case wakeBake     = "Wake & Bake"

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .relaxing:     return "😌"
        case .creative:     return "🎨"
        case .funny:        return "😂"
        case .gaming:       return "🎮"
        case .movieNight:   return "🎬"
        case .productive:   return "🧹"
        case .munchies:     return "🍕"
        case .deepThinking: return "💭"
        case .social:       return "👥"
        case .sleep:        return "🌙"
        case .wakeBake:     return "☀️"
        }
    }
}

/// The standard effects vocabulary from the spec (Log Sesh + Find My Vibe).
enum SeshEffect: String, CaseIterable, Identifiable, Codable {
    case happy = "Happy", giggly = "Giggly", relaxed = "Relaxed", creative = "Creative"
    case energetic = "Energetic", focused = "Focused", thoughtful = "Thoughtful"
    case hungry = "Hungry", sleepy = "Sleepy", couchLocked = "Couch Locked", anxious = "Anxious"

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .happy: return "😊"; case .giggly: return "😂"; case .relaxed: return "😌"
        case .creative: return "🎨"; case .energetic: return "⚡"; case .focused: return "🎯"
        case .thoughtful: return "💭"; case .hungry: return "🍕"; case .sleepy: return "😴"
        case .couchLocked: return "🛋"; case .anxious: return "😬"
        }
    }

    /// SF Symbol equivalent, for icon-based UI.
    var symbol: String {
        switch self {
        case .happy:       return "face.smiling"
        case .giggly:      return "face.smiling.inverse"
        case .relaxed:     return "leaf"
        case .creative:    return "paintpalette"
        case .energetic:   return "bolt.fill"
        case .focused:     return "scope"
        case .thoughtful:  return "brain.head.profile"
        case .hungry:      return "fork.knife"
        case .sleepy:      return "moon.zzz.fill"
        case .couchLocked: return "sofa.fill"
        case .anxious:     return "exclamationmark.triangle"
        }
    }

    /// A tint color for the effect's icon/chip.
    var tint: Color {
        switch self {
        case .happy, .giggly:      return Palette.gold
        case .relaxed, .sleepy, .couchLocked: return Palette.green
        case .creative, .thoughtful: return Palette.greenBright
        case .energetic, .focused: return Palette.goldDeep
        case .hungry:              return Palette.gold
        case .anxious:             return Palette.moodAngry
        }
    }
}

// MARK: - High Thought

enum ThoughtTag: String, CaseIterable, Identifiable, Codable {
    case deep = "Deep"
    case funny = "Funny"
    case questions = "Questions"
    case rant = "Rant"

    var id: String { rawValue }
}

/// Who can see a posted thought or rant. #post visibility
enum PostVisibility: String, CaseIterable, Identifiable, Codable {
    case privatePost  = "Private"
    case closeFriends = "Close Friends"
    case friends      = "Friends"
    case publicPost   = "Public"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .privatePost:  return "🔒"
        case .closeFriends: return "⭐️"
        case .friends:      return "👥"
        case .publicPost:   return "🌍"
        }
    }
    var symbol: String {
        switch self {
        case .privatePost:  return "lock.fill"
        case .closeFriends: return "star.fill"
        case .friends:      return "person.2.fill"
        case .publicPost:   return "globe"
        }
    }
}

struct HighThought: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    var isFavorite: Bool = false
    var tag: ThoughtTag?
    var highlighted: Bool = false   // purple card treatment
    var visibilityRaw: String? = nil   // PostVisibility.rawValue (#post visibility)

    var visibility: PostVisibility {
        get { visibilityRaw.flatMap(PostVisibility.init(rawValue:)) ?? .privatePost }
        set { visibilityRaw = newValue.rawValue }
    }
}


// MARK: - Strain insight (aggregated)

struct StrainInsight: Identifiable {
    var id: String { name }
    let name: String
    let sessions: Int
    let averageRating: Double
}
