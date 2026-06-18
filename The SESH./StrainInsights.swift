//
//  StrainInsights.swift
//  The SESH
//
//  Derives subjective comparison fields (Typical Feel, Best Time, Couch Lock,
//  Socializing, Sleep Aid) from a strain's existing type + effects. This is
//  ORIGINAL computed logic based on the strain's own data — nothing is scraped
//  or copied. The ratings are heuristic guidance, not medical claims.
//

import Foundation

/// A 1–5 style qualitative level used for the comparison bars.
enum InsightLevel: Int {
    case veryLow = 1, low, medium, high, veryHigh

    var label: String {
        switch self {
        case .veryLow:  return "Very Low"
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .veryHigh: return "Very High"
        }
    }
    /// 0...1 for drawing a bar.
    var fraction: Double { Double(rawValue) / 5.0 }
}

/// Computes the derived comparison fields for a strain.
enum StrainInsights {

    /// Lowercased effect names for quick matching.
    private static func effectSet(_ s: StrainProfile) -> Set<String> {
        Set(s.effects.map { $0.name.lowercased() })
    }
    private static func has(_ s: StrainProfile, _ names: String...) -> Bool {
        let e = effectSet(s)
        return names.contains { e.contains($0) }
    }

    // MARK: Genetics (already in the model)

    static func genetics(_ s: StrainProfile) -> String {
        if let l = s.lineage, !l.isEmpty { return l }
        return "—"
    }

    // MARK: Flavor (already in the model)

    static func flavor(_ s: StrainProfile) -> String {
        let f = s.flavors.prefix(3).map(\.name)
        return f.isEmpty ? "—" : f.joined(separator: ", ")
    }

    // MARK: Typical Feel

    static func typicalFeel(_ s: StrainProfile) -> String {
        let relaxing = has(s, "relaxed", "sleepy", "calming")
        let upbeat   = has(s, "energetic", "focused", "creative", "uplifting")
        let euphoric = has(s, "euphoric", "happy", "giggly")
        switch (relaxing, upbeat) {
        case (true, false):  return euphoric ? "Calm & happy" : "Calm & heavy"
        case (false, true):  return euphoric ? "Bright & social" : "Clear & focused"
        case (true, true):   return "Balanced, mellow"
        default:
            switch s.type {
            case .indica:  return "Relaxing"
            case .sativa:  return "Uplifting"
            case .hybrid:  return "Balanced"
            case .unknown: return "—"
            }
        }
    }

    // MARK: Best Time

    static func bestTime(_ s: StrainProfile) -> String {
        if has(s, "sleepy") { return "Night" }
        if has(s, "energetic", "focused") && !has(s, "relaxed") { return "Daytime" }
        switch s.type {
        case .indica:  return "Evening"
        case .sativa:  return "Daytime"
        case .hybrid:  return "Anytime"
        case .unknown: return "Anytime"
        }
    }

    // MARK: Couch Lock (sedation / heaviness)

    static func couchLock(_ s: StrainProfile) -> InsightLevel {
        var score = 0
        if has(s, "sleepy")  { score += 2 }
        if has(s, "relaxed") { score += 1 }
        switch s.type {
        case .indica:  score += 2
        case .hybrid:  score += 0
        case .sativa:  score -= 1
        case .unknown: break
        }
        if has(s, "energetic", "focused") { score -= 1 }
        return clamp(score, base: 1)
    }

    // MARK: Socializing

    static func socializing(_ s: StrainProfile) -> InsightLevel {
        var score = 0
        if has(s, "happy", "giggly", "talkative") { score += 2 }
        if has(s, "energetic", "euphoric")        { score += 1 }
        if has(s, "creative", "focused")          { score += 1 }
        if has(s, "sleepy")                        { score -= 2 }
        switch s.type {
        case .sativa: score += 1
        case .indica: score -= 1
        default: break
        }
        return clamp(score, base: 2)
    }

    // MARK: Sleep Aid

    static func sleepAid(_ s: StrainProfile) -> InsightLevel {
        var score = 0
        if has(s, "sleepy")  { score += 3 }
        if has(s, "relaxed") { score += 1 }
        if has(s, "calming") { score += 1 }
        switch s.type {
        case .indica:  score += 1
        case .sativa:  score -= 2
        default: break
        }
        if has(s, "energetic", "focused") { score -= 2 }
        return clamp(score, base: 1)
    }

    // MARK: helpers

    /// Map a raw score to a 1–5 level. `base` is where a neutral (0) score lands.
    private static func clamp(_ score: Int, base: Int) -> InsightLevel {
        let v = max(1, min(5, base + score))
        return InsightLevel(rawValue: v) ?? .medium
    }
}
