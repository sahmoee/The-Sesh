//
//  StrainCatalog.swift
//  HighThoughts
//
//  Local strain database. Reference data ships bundled in the app (no network,
//  no scraping, no server). Users can add their own custom strains, which are
//  persisted to UserDefaults and merged with the built-in list. The same
//  StrainStore API (strain(named:), suggestions(for:), filtered(by:), sorted())
//  is used everywhere, so the UI doesn't care where a strain came from.
//

import SwiftUI

// MARK: - Model

enum StrainType: String, Codable, CaseIterable, Identifiable {
    case indica = "Indica"
    case sativa = "Sativa"
    case hybrid = "Hybrid"
    case unknown = "Unknown"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .indica:  return Color(hex: "7C6FA8")   // calm purple
        case .sativa:  return Color(hex: "C9A24B")   // bright gold
        case .hybrid:  return Palette.greenBright
        case .unknown: return Palette.textSecondary
        }
    }
}

/// A single named effect/flavor/terpene with an optional 0...1 intensity.
struct StrainTrait: Codable, Hashable, Identifiable {
    var name: String
    var intensity: Double?      // 0...1 when ranked
    var id: String { name }
}

/// The app's canonical strain shape.
struct StrainProfile: Codable, Identifiable, Hashable {
    var id: String              // stable slug, e.g. "gelato-33"
    var name: String            // display name, e.g. "Gelato #33"
    var type: StrainType
    var thc: Double?            // percent
    var cbd: Double?            // percent
    var effects: [StrainTrait]
    var flavors: [StrainTrait]
    var terpenes: [StrainTrait]
    var aka: [String]           // alternate names for matching
    var summary: String?
    var sources: [String]       // attribution, e.g. ["Built-in"] or ["My strains"]
    var isCustom: Bool          // user-added vs. bundled
    var photoName: String?      // optional user photo (custom strains)
    var breeder: String?        // seed bank / origin, e.g. "DNA Genetics"
    var lineage: String?        // genetic heritage, e.g. "OG Kush x Sour Diesel"
    var floweringTime: String?  // e.g. "56-63 days"

    enum CodingKeys: String, CodingKey {
        case id, name, type, thc, cbd, effects, flavors, terpenes, aka, summary, sources, isCustom, photoName, breeder, lineage, floweringTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = (try? c.decode(StrainType.self, forKey: .type)) ?? .unknown
        thc = try? c.decodeIfPresent(Double.self, forKey: .thc)
        cbd = try? c.decodeIfPresent(Double.self, forKey: .cbd)
        effects = (try? c.decodeIfPresent([StrainTrait].self, forKey: .effects)) ?? []
        flavors = (try? c.decodeIfPresent([StrainTrait].self, forKey: .flavors)) ?? []
        terpenes = (try? c.decodeIfPresent([StrainTrait].self, forKey: .terpenes)) ?? []
        aka = (try? c.decodeIfPresent([String].self, forKey: .aka)) ?? []
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        sources = (try? c.decodeIfPresent([String].self, forKey: .sources)) ?? []
        isCustom = (try? c.decodeIfPresent(Bool.self, forKey: .isCustom)) ?? false
        photoName = try? c.decodeIfPresent(String.self, forKey: .photoName)
        breeder = try? c.decodeIfPresent(String.self, forKey: .breeder)
        lineage = try? c.decodeIfPresent(String.self, forKey: .lineage)
        floweringTime = try? c.decodeIfPresent(String.self, forKey: .floweringTime)
    }

    init(id: String, name: String, type: StrainType, thc: Double? = nil, cbd: Double? = nil,
         effects: [StrainTrait] = [], flavors: [StrainTrait] = [], terpenes: [StrainTrait] = [],
         aka: [String] = [], summary: String? = nil, sources: [String] = [], isCustom: Bool = false,
         photoName: String? = nil, breeder: String? = nil, lineage: String? = nil, floweringTime: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.thc = thc; self.cbd = cbd
        self.effects = effects; self.flavors = flavors; self.terpenes = terpenes
        self.aka = aka; self.summary = summary; self.sources = sources; self.isCustom = isCustom
        self.photoName = photoName; self.breeder = breeder; self.lineage = lineage; self.floweringTime = floweringTime
    }

    /// All names this strain can be matched against (lowercased).
    var matchKeys: [String] {
        ([name] + aka).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    }

    static func slug(from name: String) -> String {
        let base = name.lowercased()
            .replacingOccurrences(of: "#", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return base.isEmpty ? "strain-\(UUID().uuidString.prefix(8))" : base
    }
}

// MARK: - Store (local, observable)

/// Holds the bundled library plus any user-added custom strains, and exposes
/// lookup/search. Custom strains persist to UserDefaults.
@Observable
final class StrainStore {
    /// User-added strains (persisted). Bundled strains live in `BundledStrains`.
    private(set) var customStrains: [StrainProfile] = []

    private let customKey = "ht.customStrains.v1"

    /// Cached deduped catalog + lowercased search index, rebuilt only when the
    /// custom strains change (not on every access). The bundled list is 627+
    /// strains, so rebuilding per keystroke was wasteful.
    @ObservationIgnored private var cachedStrains: [StrainProfile]?
    @ObservationIgnored private var searchIndex: [(profile: StrainProfile, keys: [String])]?

    private func invalidateCache() { cachedStrains = nil; searchIndex = nil }

    init() {
        loadCustom()
    }

    /// Full catalog: custom first (so user edits win on name clashes), then bundled.
    var strains: [StrainProfile] {
        if let cachedStrains { return cachedStrains }
        let built = buildStrains()
        cachedStrains = built
        return built
    }

    private func buildStrains() -> [StrainProfile] {
        var seen = Set<String>()
        var out: [StrainProfile] = []
        for s in customStrains + BundledStrains.all {
            let key = s.name.lowercased().trimmingCharacters(in: .whitespaces)
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }

    // MARK: Lookup & search

    func strain(named query: String) -> StrainProfile? {
        let key = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let exact = strains.first(where: { $0.matchKeys.contains(key) }) { return exact }
        return strains.first { $0.matchKeys.contains { $0.hasPrefix(key) } }
    }

    /// Ranked type-ahead suggestions: prefix matches first, then contains.
    func suggestions(for query: String, limit: Int = 6) -> [StrainProfile] {
        let key = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return [] }
        let all = strains
        let prefix = all.filter { $0.matchKeys.contains { $0.hasPrefix(key) } }
        let contains = all.filter { s in
            !prefix.contains(s) && s.matchKeys.contains { $0.contains(key) }
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// True if no strain (bundled or custom) matches the name exactly.
    func isUnknown(_ name: String) -> Bool {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return false }
        return !strains.contains { $0.matchKeys.contains(key) }
    }

    func sorted() -> [StrainProfile] {
        strains.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func filtered(by type: StrainType?) -> [StrainProfile] {
        let base = sorted()
        guard let type else { return base }
        return base.filter { $0.type == type }
    }

    // MARK: Custom strain CRUD

    /// Add or update a custom strain (matched by id). Returns the saved profile.
    @discardableResult
    func upsertCustom(_ strain: StrainProfile) -> StrainProfile {
        var s = strain
        s.isCustom = true
        if s.sources.isEmpty { s.sources = ["My strains"] }
        if let i = customStrains.firstIndex(where: { $0.id == s.id }) {
            customStrains[i] = s
        } else {
            customStrains.insert(s, at: 0)
        }
        saveCustom()
        return s
    }

    /// Convenience: create a custom strain from a name (+ optional fields).
    @discardableResult
    func addCustom(name: String, type: StrainType = .hybrid,
                   thc: Double? = nil, cbd: Double? = nil,
                   effects: [String] = [], flavors: [String] = [],
                   summary: String? = nil) -> StrainProfile {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let profile = StrainProfile(
            id: StrainProfile.slug(from: trimmed),
            name: trimmed,
            type: type,
            thc: thc, cbd: cbd,
            effects: effects.map { StrainTrait(name: $0, intensity: nil) },
            flavors: flavors.map { StrainTrait(name: $0, intensity: nil) },
            summary: (summary?.isEmpty ?? true) ? nil : summary,
            sources: ["My strains"],
            isCustom: true
        )
        return upsertCustom(profile)
    }

    func deleteCustom(_ strain: StrainProfile) {
        customStrains.removeAll { $0.id == strain.id }
        saveCustom()
    }

    func isCustom(_ strain: StrainProfile) -> Bool {
        customStrains.contains { $0.id == strain.id }
    }

    /// Clears user-added strains (used by full reset).
    func clearCustom() {
        customStrains.removeAll()
        saveCustom()
    }

    // MARK: Persistence

    private func saveCustom() {
        invalidateCache()
        if let data = try? JSONEncoder().encode(customStrains) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    private func loadCustom() {
        if let data = UserDefaults.standard.data(forKey: customKey),
           let v = try? JSONDecoder().decode([StrainProfile].self, from: data) {
            customStrains = v
        }
        invalidateCache()
    }
}

// MARK: - Bundled local library

/// The built-in strain reference data shipped with the app. Curated,
/// license-clean placeholder values. Extend freely.
enum BundledStrains {
    static let all: [StrainProfile] = [
        StrainProfile(
            id: "sexbud", name: "SexBud", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78)],
            flavors: [.init(name: "Sweet"), .init(name: "Pineapple"), .init(name: "Peach")],
            terpenes: [],
            summary: "Sweet pineapple, peach, highly stimulating active high",
            sources: ["SeedFinder"], breeder: "Female Seeds",
            lineage: "White Grapefruit selection", floweringTime: "50-56 days"),
        StrainProfile(
            id: "shaman", name: "Shaman", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78), .init(name: "Creative", intensity: 0.72)],
            flavors: [.init(name: "Sweet"), .init(name: "Spicy"), .init(name: "Woody"), .init(name: "Mint")],
            terpenes: [],
            summary: "Sweet spice, mint wood, purple outdoor performance master",
            sources: ["SeedFinder"], breeder: "Dutch Passion",
            lineage: "Purple #1 x Skunk selection", floweringTime: "50-56 days"),
        StrainProfile(
            id: "shining-silver-haze", name: "Shining Silver Haze", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Uplifted", intensity: 0.74)],
            flavors: [.init(name: "Sweet"), .init(name: "Lemon"), .init(name: "Pine")],
            terpenes: [],
            summary: "Sweet pine, bright lemon, high speed long day high",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Haze x (Skunk x Northern Lights)", floweringTime: "65-75 days"),
        StrainProfile(
            id: "silver-rocket", name: "Silver Rocket", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78), .init(name: "Uplifted", intensity: 0.74)],
            flavors: [.init(name: "Spicy"), .init(name: "Chemical")],
            terpenes: [],
            summary: "Spicy, chemical, immediate bright energetic jump",
            sources: ["SeedFinder"], breeder: "Local Cross",
            lineage: "Silver Haze x Fast Hybrid", floweringTime: "60-65 days"),
        StrainProfile(
            id: "sin-tra-bajo", name: "Sin Tra Bajo", type: .indica, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Hash")],
            terpenes: [],
            summary: "Sweet earth, heavy hash, short stealth architecture stone",
            sources: ["SeedFinder"], breeder: "Barneys Farm",
            lineage: "Mazari x Lowrider", floweringTime: "50-55 days"),
        StrainProfile(
            id: "skywalker-kush", name: "Skywalker Kush", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Woody"), .init(name: "Lemon"), .init(name: "Pine"), .init(name: "Diesel")],
            terpenes: [],
            summary: "Fuel, pine wood, lemon, exceptional extract yield sedative",
            sources: ["SeedFinder"], breeder: "DNA Genetics",
            lineage: "Skywalker OG backcross", floweringTime: "60-65 days"),
        StrainProfile(
            id: "solomatic-cbd", name: "Solomatic CBD", type: .hybrid, thc: 6, cbd: 8.0,
            effects: [.init(name: "Relaxed", intensity: 0.75), .init(name: "Focused", intensity: 0.6)],
            flavors: [.init(name: "Sweet"), .init(name: "Lemon"), .init(name: "Ginger")],
            terpenes: [],
            summary: "Sweet ginger, lemon, near-zero THC pure functional relief",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Diesel CBD x Asia CBD Auto", floweringTime: "50-55 days"),
        StrainProfile(
            id: "sogouda", name: "SoGouda", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.82), .init(name: "Happy", intensity: 0.8)],
            flavors: [.init(name: "Spicy"), .init(name: "Cheese"), .init(name: "Creamy"), .init(name: "Fruity")],
            terpenes: [],
            summary: "Creamy fruit cheese, spice, deep cheerful body ease",
            sources: ["SeedFinder"], breeder: "Soma Seeds",
            lineage: "Blueberry x Cheese x G13 Haze", floweringTime: "60-65 days"),
        StrainProfile(
            id: "sour-cream", name: "Sour Cream", type: .sativa, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8), .init(name: "Energetic", intensity: 0.78), .init(name: "Euphoric", intensity: 0.7)],
            flavors: [.init(name: "Earthy"), .init(name: "Diesel"), .init(name: "Sour")],
            terpenes: [],
            summary: "Sour diesel, earth, heavy psychoactive shifting wave",
            sources: ["SeedFinder"], breeder: "DNA Genetics",
            lineage: "G13 x Sour Diesel", floweringTime: "70-75 days"),
        StrainProfile(
            id: "sour-power", name: "Sour Power", type: .sativa, thc: 22, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78), .init(name: "Creative", intensity: 0.72)],
            flavors: [.init(name: "Citrus"), .init(name: "Diesel"), .init(name: "Sour")],
            terpenes: [],
            summary: "Intense sour fuel, sharp citrus, clear multi-cup winner",
            sources: ["SeedFinder"], breeder: "Hortilab",
            lineage: "Star Sour x East Coast Sour Diesel", floweringTime: "60-65 days"),
        StrainProfile(
            id: "sour-tangie", name: "Sour Tangie", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78)],
            flavors: [.init(name: "Chemical"), .init(name: "Diesel"), .init(name: "Orange")],
            terpenes: [],
            summary: "Orange fuel, chemical, immediate high energy lift",
            sources: ["SeedFinder"], breeder: "DawgLocal Hybrid",
            lineage: "Sour Tangie x Chemdawg", floweringTime: "60-65 days"),
        StrainProfile(
            id: "space-cookies", name: "Space Cookies", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.82), .init(name: "Happy", intensity: 0.8), .init(name: "Euphoric", intensity: 0.7)],
            flavors: [.init(name: "Sweet"), .init(name: "Pine")],
            terpenes: [],
            summary: "Sweet bakery dough, pine, deep smiling cosmic relaxation",
            sources: ["SeedFinder"], breeder: "Paradise Seeds",
            lineage: "Girl Scout Cookies selection x secret hybrid", floweringTime: "60-65 days"),
        StrainProfile(
            id: "special-kush-1", name: "Special Kush #1", type: .indica, thc: 16, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.8), .init(name: "Sleepy", intensity: 0.7)],
            flavors: [.init(name: "Spicy"), .init(name: "Earthy"), .init(name: "Hash")],
            terpenes: [],
            summary: "Earthy hash, spicy, budget-friendly high commercial weight",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Afghan x Kush landraces", floweringTime: "45-50 days"),
        StrainProfile(
            id: "special-queen-1", name: "Special Queen #1", type: .hybrid, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.7), .init(name: "Happy", intensity: 0.7)],
            flavors: [.init(name: "Sweet")],
            terpenes: [],
            summary: "Sweet, skunky, robust forgiving plant high daytime value",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Power Plant x Skunk", floweringTime: "50-55 days"),
        StrainProfile(
            id: "speed-queen", name: "Speed Queen", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.82), .init(name: "Energetic", intensity: 0.78)],
            flavors: [.init(name: "Woody"), .init(name: "Licorice")],
            terpenes: [],
            summary: "Wood, dark licorice, grounding balanced active calm",
            sources: ["SeedFinder"], breeder: "Mandala Seeds",
            lineage: "North Indian Landrace (Himachal Pradesh)", floweringTime: "50-55 days"),
        StrainProfile(
            id: "sssdh", name: "SSSDH", type: .sativa, thc: 22, cbd: 0.5,
            effects: [.init(name: "Energetic", intensity: 0.78)],
            flavors: [.init(name: "Pine"), .init(name: "Diesel"), .init(name: "Citrus"), .init(name: "Sour")],
            terpenes: [], aka: ["Super Sour Diesel Haze"],
            summary: "Pine fuel, sour lime haze, soaring high power energy",
            sources: ["SeedFinder"], breeder: "Reservoir",
            lineage: "Super Silver Haze x Sour Diesel", floweringTime: "75-85 days"),
        StrainProfile(
            id: "star-99", name: "Star 99", type: .sativa, thc: 22, cbd: 0.5,
            effects: [.init(name: "Creative", intensity: 0.8), .init(name: "Focused", intensity: 0.72)],
            flavors: [.init(name: "Pineapple"), .init(name: "Chemical")],
            terpenes: [],
            summary: "Pineapple gas, chemical, intense cerebral focus",
            sources: ["SeedFinder"], breeder: "Clone Only",
            lineage: "Stardawg x Cinderella 99", floweringTime: "56-63 days"),
        StrainProfile(
            id: "sterling-haze", name: "Sterling Haze", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Focused", intensity: 0.72)],
            flavors: [.init(name: "Sweet"), .init(name: "Lemon"), .init(name: "Sour")],
            terpenes: [],
            summary: "Sweet sweet haze, sour lemon, high mental clarity shift",
            sources: ["SeedFinder"], breeder: "Nirvana Seeds",
            lineage: "Haze x Northern Lights", floweringTime: "70-80 days"),
        StrainProfile(
            id: "strawberry-cheesecake", name: "Strawberry Cheesecake", type: .indica, thc: 16, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.75)],
            flavors: [.init(name: "Cheese"), .init(name: "Creamy"), .init(name: "Strawberry")],
            terpenes: [],
            summary: "Strawberry cream, savory cheese, comforting muscle soft",
            sources: ["SeedFinder"], breeder: "Seedsman",
            lineage: "Chronic x White Widow x Cheese", floweringTime: "56-63 days"),
        StrainProfile(
            id: "stress-killer", name: "Stress Killer", type: .sativa, thc: 6, cbd: 8.0,
            effects: [.init(name: "Focused", intensity: 0.72)],
            flavors: [.init(name: "Lemon"), .init(name: "Citrus")],
            terpenes: [],
            summary: "Lemon citrus, high-CBD clear anti-anxiety function focus",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Lemon Haze x Juanita la Lagrimosa x Ruderalis", floweringTime: "50-55 days"),
        StrainProfile(
            id: "super-critical-auto", name: "Super Critical Auto", type: .indica, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Sweet"), .init(name: "Spicy"), .init(name: "Skunk")],
            terpenes: [],
            summary: "Spicy, sweet skunk, rapid setup dense target heavy",
            sources: ["SeedFinder"], breeder: "Greenhouse",
            lineage: "Critical x Big Bud x Skunk x Auto", floweringTime: "50-55 days"),
        StrainProfile(
            id: "sweet-cheese", name: "Sweet Cheese", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Creative", intensity: 0.8), .init(name: "Relaxed", intensity: 0.75)],
            flavors: [.init(name: "Sweet"), .init(name: "Cheese"), .init(name: "Incense")],
            terpenes: [],
            summary: "Musky cheese, sweet incense, long creative physical wave",
            sources: ["SeedFinder"], breeder: "Sweet Seeds",
            lineage: "Cheese x Black Jack", floweringTime: "63 days"),
        StrainProfile(
            id: "sweet-purple", name: "Sweet Purple", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.8), .init(name: "Sleepy", intensity: 0.7)],
            flavors: [.init(name: "Sweet"), .init(name: "Strawberry"), .init(name: "Herbal")],
            terpenes: [],
            summary: "Sweet strawberry, herbal, purple colors cold climate master",
            sources: ["SeedFinder"], breeder: "Paradise Seeds",
            lineage: "Purple strain x Dutch Sativa", floweringTime: "50-55 days"),
        StrainProfile(
            id: "tahoe-og", name: "Tahoe OG", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Lemon"), .init(name: "Pine"), .init(name: "Diesel")],
            terpenes: [],
            summary: "Lemon fuel, crisp pine, immediate rainy day couch lock",
            sources: ["SeedFinder"], breeder: "Cali Connection",
            lineage: "OG Kush Tahoe Cut", floweringTime: "60-65 days"),
        StrainProfile(
            id: "the-gorgon", name: "The Gorgon", type: .indica, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Chemical"), .init(name: "Diesel")],
            terpenes: [],
            summary: "Chemical, heavy fuel, dark color sleep enhancer",
            sources: ["SeedFinder"], breeder: "Rare Cross",
            lineage: "Secret Indica line", floweringTime: "55-60 days"),
        StrainProfile(
            id: "the-true-og", name: "The True OG", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8), .init(name: "Relaxed", intensity: 0.75)],
            flavors: [.init(name: "Pine"), .init(name: "Diesel")],
            terpenes: [],
            summary: "Rich fuel, pine tree, long-running deep body recovery stone",
            sources: ["SeedFinder"], breeder: "Clone Only",
            lineage: "OG Kush selected line", floweringTime: "60-65 days"),
        StrainProfile(
            id: "toko", name: "Toko", type: .hybrid, thc: 16, cbd: 0.5,
            effects: [.init(name: "Focused", intensity: 0.6)],
            flavors: [.init(name: "Spicy"), .init(name: "Woody")],
            terpenes: [],
            summary: "Spicy, cedar wood, light balancing functional properties",
            sources: ["SeedFinder"], breeder: "Japanese Line",
            lineage: "East Asian Landrace x Western Hybrid", floweringTime: "60-65 days"),
        StrainProfile(
            id: "trance", name: "Trance", type: .indica, thc: 16, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Skunk")],
            terpenes: [],
            summary: "Earthy skunk, sweet, stable outdoor option soft drop",
            sources: ["SeedFinder"], breeder: "Dutch Passion",
            lineage: "Skunk x Indica selection", floweringTime: "50-55 days"),
        StrainProfile(
            id: "triple-g", name: "Triple G", type: .indica, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8), .init(name: "Relaxed", intensity: 0.75)],
            flavors: [.init(name: "Diesel"), .init(name: "Chocolate")],
            terpenes: [],
            summary: "Rich dark chocolate, heavy fuel, highly intense physical zone",
            sources: ["SeedFinder"], breeder: "Royal Queen",
            lineage: "Gorilla Glue #4 x Gelato #33", floweringTime: "56-63 days"),
        StrainProfile(
            id: "tundra", name: "Tundra", type: .indica, thc: 16, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.8), .init(name: "Sleepy", intensity: 0.7)],
            flavors: [.init(name: "Citrus"), .init(name: "Earthy"), .init(name: "Fruity")],
            terpenes: [],
            summary: "Citrus fruit, soft earth, robust northern latitude auto",
            sources: ["SeedFinder"], breeder: "Dutch Passion",
            lineage: "Passion #1 x Ruderalis", floweringTime: "50-55 days"),
        StrainProfile(
            id: "utopia-haze", name: "Utopia Haze", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Happy", intensity: 0.8)],
            flavors: [.init(name: "Citrus"), .init(name: "Mint")],
            terpenes: [],
            summary: "Fresh mint, citrus, long joyful laughing clear high",
            sources: ["SeedFinder"], breeder: "Barneys Farm",
            lineage: "Brazilian Landrace", floweringTime: "70-75 days"),
        StrainProfile(
            id: "velvet-moon", name: "Velvet Moon", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Fruity")],
            terpenes: [],
            summary: "Sweet fruit, pungent earth, smooth velvety evening rest",
            sources: ["SeedFinder"], breeder: "Greenhouse",
            lineage: "Dosidos x Holy Punch", floweringTime: "56-63 days"),
        StrainProfile(
            id: "white-diesel", name: "White Diesel", type: .hybrid, thc: 18, cbd: 0.5,
            effects: [.init(name: "Focused", intensity: 0.72)],
            flavors: [.init(name: "Citrus"), .init(name: "Diesel"), .init(name: "Sour")],
            terpenes: [],
            summary: "Red grapefruit, sour diesel, glistening white trichome focus",
            sources: ["SeedFinder"], breeder: "White Label",
            lineage: "White Widow x NYC Diesel", floweringTime: "50-65 days"),
        StrainProfile(
            id: "white-ice", name: "White Ice", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Relaxed", intensity: 0.8), .init(name: "Sleepy", intensity: 0.7)],
            flavors: [.init(name: "Spicy"), .init(name: "Woody"), .init(name: "Hash")],
            terpenes: [],
            summary: "Spicy wood, grey hash, dense white crystal armor sheets",
            sources: ["SeedFinder"], breeder: "White Label",
            lineage: "Hindu Kush x Dutch Skunk x Northern Lights", floweringTime: "45-55 days"),
        StrainProfile(
            id: "white-russian", name: "White Russian", type: .indica, thc: 22, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8), .init(name: "Focused", intensity: 0.6)],
            flavors: [.init(name: "Sweet"), .init(name: "Woody"), .init(name: "Skunk")],
            terpenes: [],
            summary: "Pungent skunk, sweet wood, high-crystal long functional heavy",
            sources: ["SeedFinder"], breeder: "Serious Seeds",
            lineage: "AK-47 x White Widow", floweringTime: "56-63 days"),
        StrainProfile(
            id: "x-18-pakistani", name: "X-18 Pakistani", type: .indica, thc: 18, cbd: 0.5,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            flavors: [.init(name: "Apple"), .init(name: "Plum")],
            terpenes: [],
            summary: "Crisp apple, blue plum, dense hard traditional medicinal stone",
            sources: ["SeedFinder"], breeder: "DNA Genetics",
            lineage: "Pure Pakistani Landrace", floweringTime: "50-55 days"),
        StrainProfile(
            id: "yabba-dabba-diesel", name: "Yabba Dabba Diesel", type: .sativa, thc: 18, cbd: 0.5,
            effects: [.init(name: "Creative", intensity: 0.8), .init(name: "Energetic", intensity: 0.78), .init(name: "Focused", intensity: 0.72)],
            flavors: [.init(name: "Diesel"), .init(name: "Citrus")],
            terpenes: [],
            summary: "Kerosene, lime, rapid creative morning starter focus",
            sources: ["SeedFinder"], breeder: "Local Cross",
            lineage: "Sour Diesel x Fast Sativa", floweringTime: "60-65 days"),
        StrainProfile(
            id: "gelato-33", name: "Gelato #33", type: .hybrid, thc: 21, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.92), .init(name: "Happy", intensity: 0.84),
                      .init(name: "Creative", intensity: 0.76), .init(name: "Euphoric", intensity: 0.7)],
            flavors: [.init(name: "Sweet"), .init(name: "Citrus"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene", intensity: 0.8), .init(name: "Limonene", intensity: 0.7),
                       .init(name: "Humulene", intensity: 0.5)],
            aka: ["Gelato 33", "Larry Bird"],
            summary: "A balanced hybrid known for a relaxed, giggly, creative high.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-dream", name: "Blue Dream", type: .hybrid, thc: 18, cbd: 0.2,
            effects: [.init(name: "Relaxed", intensity: 0.8), .init(name: "Uplifted", intensity: 0.72),
                      .init(name: "Happy", intensity: 0.78), .init(name: "Sleepy", intensity: 0.6)],
            flavors: [.init(name: "Berry"), .init(name: "Sweet"), .init(name: "Herbal")],
            terpenes: [.init(name: "Myrcene", intensity: 0.85), .init(name: "Pinene", intensity: 0.55),
                       .init(name: "Caryophyllene", intensity: 0.5)],
            aka: ["Blueberry Haze"],
            summary: "A sativa-leaning hybrid with gentle full-body relaxation and a berry nose.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "og-kush", name: "OG Kush", type: .hybrid, thc: 23, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.88), .init(name: "Happy", intensity: 0.7),
                      .init(name: "Euphoric", intensity: 0.66), .init(name: "Sleepy", intensity: 0.55)],
            flavors: [.init(name: "Earthy"), .init(name: "Pine"), .init(name: "Woody")],
            terpenes: [.init(name: "Myrcene", intensity: 0.8), .init(name: "Limonene", intensity: 0.65),
                       .init(name: "Caryophyllene", intensity: 0.6)],
            aka: ["OGK", "Premium OG"],
            summary: "A classic, potent hybrid with a heavy, stress-melting body high.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "northern-lights", name: "Northern Lights", type: .indica, thc: 18, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.95), .init(name: "Sleepy", intensity: 0.85),
                      .init(name: "Happy", intensity: 0.6)],
            flavors: [.init(name: "Earthy"), .init(name: "Pine"), .init(name: "Sweet")],
            terpenes: [.init(name: "Myrcene", intensity: 0.9), .init(name: "Caryophyllene", intensity: 0.55)],
            aka: ["NL"],
            summary: "A pure indica famous for deeply relaxing, sleepy effects.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "green-crack", name: "Green Crack", type: .sativa, thc: 20, cbd: 0.1,
            effects: [.init(name: "Energetic", intensity: 0.9), .init(name: "Focused", intensity: 0.82),
                      .init(name: "Uplifted", intensity: 0.8), .init(name: "Happy", intensity: 0.75)],
            flavors: [.init(name: "Citrus"), .init(name: "Mango"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene", intensity: 0.7), .init(name: "Pinene", intensity: 0.6),
                       .init(name: "Caryophyllene", intensity: 0.5)],
            aka: ["Green Cush", "Mango Crack"],
            summary: "An energizing daytime sativa great for focus and productivity.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "wedding-cake", name: "Wedding Cake", type: .hybrid, thc: 24, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.88), .init(name: "Happy", intensity: 0.8),
                      .init(name: "Euphoric", intensity: 0.72), .init(name: "Hungry", intensity: 0.6)],
            flavors: [.init(name: "Sweet"), .init(name: "Vanilla"), .init(name: "Earthy")],
            terpenes: [.init(name: "Limonene", intensity: 0.75), .init(name: "Caryophyllene", intensity: 0.7),
                       .init(name: "Myrcene", intensity: 0.55)],
            aka: ["Triangle Mints #23", "Pink Cookies"],
            summary: "A rich, tangy indica-leaning hybrid that's deeply relaxing.",
            sources: ["Built-in"], breeder: "Seed Junky", lineage: "Cherry Pie x Girl Scout Cookies", floweringTime: "56-63 days"),
        StrainProfile(
            id: "sour-diesel", name: "Sour Diesel", type: .sativa, thc: 22, cbd: 0.1,
            effects: [.init(name: "Energetic", intensity: 0.85), .init(name: "Uplifted", intensity: 0.84),
                      .init(name: "Creative", intensity: 0.74), .init(name: "Focused", intensity: 0.7)],
            flavors: [.init(name: "Diesel"), .init(name: "Pungent"), .init(name: "Citrus")],
            terpenes: [.init(name: "Caryophyllene", intensity: 0.75), .init(name: "Limonene", intensity: 0.7),
                       .init(name: "Myrcene", intensity: 0.55)],
            aka: ["Sour D", "Sour Deez"],
            summary: "A fast-acting, dreamy and energizing sativa with a pungent fuel nose.",
            sources: ["Built-in"], breeder: "East Coast", lineage: "Chemdawg x Super Skunk / Northern Lights", floweringTime: "65-75 days"),
        StrainProfile(
            id: "granddaddy-purple", name: "Granddaddy Purple", type: .indica, thc: 19, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.93), .init(name: "Sleepy", intensity: 0.82),
                      .init(name: "Happy", intensity: 0.65), .init(name: "Hungry", intensity: 0.55)],
            flavors: [.init(name: "Grape"), .init(name: "Berry"), .init(name: "Sweet")],
            terpenes: [.init(name: "Myrcene", intensity: 0.88), .init(name: "Pinene", intensity: 0.5),
                       .init(name: "Caryophyllene", intensity: 0.5)],
            aka: ["GDP", "Grand Daddy Purp", "Grandaddy Purple"],
            summary: "A famous purple indica delivering heavy relaxation and a grape-berry nose.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "girl-scout-cookies", name: "Girl Scout Cookies", type: .hybrid, thc: 25, cbd: 0.1,
            effects: [.init(name: "Euphoric", intensity: 0.86), .init(name: "Relaxed", intensity: 0.8),
                      .init(name: "Happy", intensity: 0.78), .init(name: "Creative", intensity: 0.6)],
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Mint")],
            terpenes: [.init(name: "Caryophyllene", intensity: 0.8), .init(name: "Limonene", intensity: 0.6),
                       .init(name: "Humulene", intensity: 0.5)],
            aka: ["GSC", "Cookies"],
            summary: "A potent, sweet hybrid with strong euphoria and full-body relaxation.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "jack-herer", name: "Jack Herer", type: .sativa, thc: 20, cbd: 0.1,
            effects: [.init(name: "Focused", intensity: 0.85), .init(name: "Creative", intensity: 0.82),
                      .init(name: "Uplifted", intensity: 0.8), .init(name: "Energetic", intensity: 0.7)],
            flavors: [.init(name: "Pine"), .init(name: "Citrus"), .init(name: "Spice")],
            terpenes: [.init(name: "Terpinolene", intensity: 0.8), .init(name: "Pinene", intensity: 0.65),
                       .init(name: "Caryophyllene", intensity: 0.5)],
            aka: ["JH", "The Jack"],
            summary: "A clear-headed, creative sativa beloved for daytime focus.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-punch", name: "Purple Punch", type: .indica, thc: 19, cbd: 0.1,
            effects: [.init(name: "Relaxed", intensity: 0.9), .init(name: "Sleepy", intensity: 0.8),
                      .init(name: "Happy", intensity: 0.7), .init(name: "Hungry", intensity: 0.55)],
            flavors: [.init(name: "Grape"), .init(name: "Berry"), .init(name: "Sweet")],
            terpenes: [.init(name: "Caryophyllene", intensity: 0.7), .init(name: "Limonene", intensity: 0.6),
                       .init(name: "Myrcene", intensity: 0.6)],
            aka: ["PP"],
            summary: "A dessert indica with a candy-grape nose and a sleepy, soothing finish.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pineapple-express", name: "Pineapple Express", type: .hybrid, thc: 20, cbd: 0.1,
            effects: [.init(name: "Happy", intensity: 0.82), .init(name: "Energetic", intensity: 0.76),
                      .init(name: "Uplifted", intensity: 0.78), .init(name: "Creative", intensity: 0.62)],
            flavors: [.init(name: "Pineapple"), .init(name: "Citrus"), .init(name: "Pine")],
            terpenes: [.init(name: "Caryophyllene", intensity: 0.7), .init(name: "Limonene", intensity: 0.7),
                       .init(name: "Myrcene", intensity: 0.5)],
            aka: ["PE"],
            summary: "A lively tropical hybrid with an uplifting, productive buzz.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-widow", name: "White Widow", type: .hybrid, thc: 19,
            flavors: [.init(name: "Earthy"), .init(name: "Woody"), .init(name: "Pungent")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Earthy, woody, pungent aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Green House", lineage: "Brazilian Sativa x South Indian Indica", floweringTime: "55-60 days"),
        StrainProfile(
            id: "amnesia-haze", name: "Amnesia Haze", type: .sativa, thc: 22,
            flavors: [.init(name: "Citrus"), .init(name: "Lemon"), .init(name: "Earthy")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Beta-Caryophyllene")],
            summary: "Citrus, lemon, earthy aromas. Flowers in roughly 10-12 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gorilla-glue-4", name: "Gorilla Glue #4", type: .indica, thc: 26,
            flavors: [.init(name: "Pungent"), .init(name: "Fuel"), .init(name: "Earthy"), .init(name: "Chemical")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Pungent, fuel, earthy, chemical aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "blueberry", name: "Blueberry", type: .indica, thc: 16,
            flavors: [.init(name: "Sweet"), .init(name: "Blueberry"), .init(name: "Fruit")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Linalool")],
            summary: "Sweet, blueberry, fruity aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "skunk-1", name: "Skunk #1", type: .hybrid, thc: 16,
            flavors: [.init(name: "Pungent"), .init(name: "Skunk"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Pinene"), .init(name: "Caryophyllene")],
            summary: "Pungent, skunky, musky aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Sacred Seeds", lineage: "Afghan x Colombian Gold x Acapulco Gold", floweringTime: "50-55 days"),
        StrainProfile(
            id: "super-silver-haze", name: "Super Silver Haze", type: .sativa, thc: 22,
            flavors: [.init(name: "Skunk"), .init(name: "Spice"), .init(name: "Citrus")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Skunky, spicy, citrus aromas. Flowers in roughly 10-11 weeks, experienced to grow.",
            sources: ["Built-in"], breeder: "Mr. Nice", lineage: "Skunk x Northern Lights x Haze", floweringTime: "65-75 days"),
        StrainProfile(
            id: "durban-poison", name: "Durban Poison", type: .sativa, thc: 19,
            flavors: [.init(name: "Sweet"), .init(name: "Anise"), .init(name: "Licorice"), .init(name: "Spice")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Ocimene")],
            summary: "Sweet, anise, licorice, spicy aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chemdawg", name: "Chemdawg", type: .hybrid, thc: 26,
            flavors: [.init(name: "Chemical"), .init(name: "Fuel"), .init(name: "Diesel"), .init(name: "Pine")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Chemical, fuel, diesel, pine aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "bubba-kush", name: "Bubba Kush", type: .indica, thc: 19,
            flavors: [.init(name: "Coffee"), .init(name: "Chocolate"), .init(name: "Earthy"), .init(name: "Sweet")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Coffee, chocolate, earthy, sweet aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "ak-47", name: "AK-47", type: .sativa, thc: 22,
            flavors: [.init(name: "Earthy"), .init(name: "Woody"), .init(name: "Sour"), .init(name: "Pungent")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Earthy, woody, sour, pungent aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "trainwreck", name: "Trainwreck", type: .sativa, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Menthol"), .init(name: "Lemon"), .init(name: "Spice")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Pinene")],
            summary: "Pine, menthol, lemon, spicy aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"], breeder: "Arcata Cut", lineage: "Mexican x Thai x Afghani", floweringTime: "60-65 days"),
        StrainProfile(
            id: "maui-wowie", name: "Maui Wowie", type: .sativa, thc: 16,
            flavors: [.init(name: "Tropical"), .init(name: "Sweet"), .init(name: "Pineapple")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Pinene")],
            summary: "Tropical, sweet, pineapple aromas. Flowers in roughly 9-11 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "afghan-kush", name: "Afghan Kush", type: .indica, thc: 16,
            flavors: [.init(name: "Hash"), .init(name: "Earthy"), .init(name: "Woody"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Hash, earthy, woody, spice aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "hindu-kush", name: "Hindu Kush", type: .indica, thc: 16,
            flavors: [.init(name: "Earthy"), .init(name: "Sandalwood"), .init(name: "Incense")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Earthy, sandalwood, incense aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "master-kush", name: "Master Kush", type: .indica, thc: 19,
            flavors: [.init(name: "Citrus"), .init(name: "Earthy"), .init(name: "Hash")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Citrus, earthy, traditional hash aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "acapulco-gold", name: "Acapulco Gold", type: .sativa, thc: 19,
            flavors: [.init(name: "Toffee"), .init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Chestnut")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Toffee, sweet, earthy, chestnut aromas. Flowers in roughly 10-11 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "panama-red", name: "Panama Red", type: .sativa, thc: 16,
            flavors: [.init(name: "Herbal"), .init(name: "Woody"), .init(name: "Spice"), .init(name: "Tropical")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Herbal, woody, spicy, tropical aromas. Flowers in roughly 11-13 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "mazar-i-sharif", name: "Mazar-i-Sharif", type: .indica, thc: 16,
            flavors: [.init(name: "Sweet"), .init(name: "Spice"), .init(name: "Hash")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sweet, heavy spice, pungent hash aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "thai-sativa", name: "Thai Sativa", type: .sativa, thc: 19,
            flavors: [.init(name: "Citrus"), .init(name: "Woody"), .init(name: "Spice")],
            terpenes: [.init(name: "Pinene"), .init(name: "Myrcene"), .init(name: "Terpinolene")],
            summary: "Citrus, clean wood, heavy spice aromas. Flowers in roughly 12-14 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "colombia-gold", name: "Colombia Gold", type: .sativa, thc: 16,
            flavors: [.init(name: "Skunk"), .init(name: "Lime"), .init(name: "Fruit")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Sabinene")],
            summary: "Skunky, sweet lime, tropical fruit aromas. Flowers in roughly 11-13 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lsd", name: "LSD", type: .indica, thc: 26,
            flavors: [.init(name: "Earthy"), .init(name: "Chestnut"), .init(name: "Musk"), .init(name: "Sweet")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Earthy, chestnut, musky, sweet aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "super-skunk", name: "Super Skunk", type: .indica, thc: 16,
            flavors: [.init(name: "Pungent"), .init(name: "Skunk"), .init(name: "Sweet"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Pungent, skunky, sweet, earthy aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Sensi Seeds", lineage: "Skunk #1 x Afghani Landrace", floweringTime: "45-50 days"),
        StrainProfile(
            id: "shiva-skunk", name: "Shiva Skunk", type: .indica, thc: 22,
            flavors: [.init(name: "Sweet"), .init(name: "Citrus"), .init(name: "Musk"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet, citrus, heavy musk, fuel aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "g13", name: "G13", type: .indica, thc: 22,
            flavors: [.init(name: "Earthy"), .init(name: "Pine"), .init(name: "Woody")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Earthy, heavy pine, sweet wood aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "la-confidential", name: "LA Confidential", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Spice"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Pine, spicy, sweet earthy aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chocolope", name: "Chocolope", type: .sativa, thc: 22,
            flavors: [.init(name: "Chocolate"), .init(name: "Coffee"), .init(name: "Sweet"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Chocolate, coffee, sweet, earthy aromas. Flowers in roughly 10-12 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "strawberry-cough", name: "Strawberry Cough", type: .sativa, thc: 19,
            flavors: [.init(name: "Sweet"), .init(name: "Strawberry"), .init(name: "Herbal"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet, fresh strawberry, herbal, skunk aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "agent-orange", name: "Agent Orange", type: .hybrid, thc: 16,
            flavors: [.init(name: "Citrus"), .init(name: "Orange"), .init(name: "Fuel")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Citrus, sweet orange, sharp fuel aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cinderella-99", name: "Cinderella 99", type: .sativa, thc: 22,
            flavors: [.init(name: "Sweet"), .init(name: "Pineapple"), .init(name: "Tropical"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Sweet, pineapple, tropical, earthy aromas. Flowers in roughly 7-8 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-skunk", name: "Lemon Skunk", type: .hybrid, thc: 19,
            flavors: [.init(name: "Skunk"), .init(name: "Lemon"), .init(name: "Citrus")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Skunk, sharp lemon, citrus sour aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "kush-mints", name: "Kush Mints", type: .indica, thc: 26,
            flavors: [.init(name: "Mint"), .init(name: "Herbal"), .init(name: "Gas"), .init(name: "Dough")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Linalool")],
            summary: "Minty, herbal, sweet gas, doughy aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sunset-sherbert", name: "Sunset Sherbert", type: .indica, thc: 22,
            flavors: [.init(name: "Berry"), .init(name: "Citrus")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet berry, orange zest, skunky citrus aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Mr. Sherbinski", lineage: "Girl Scout Cookies x Pink Panties", floweringTime: "56-63 days"),
        StrainProfile(
            id: "zkittlez", name: "Zkittlez", type: .indica, thc: 16,
            flavors: [.init(name: "Sweet"), .init(name: "Fruit"), .init(name: "Citrus")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Humulene"), .init(name: "Limonene")],
            summary: "Sweet, candy fruit, tropical citrus aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"], breeder: "Terp Hogz", lineage: "Grape Ape x Grapefruit x Secret Strain", floweringTime: "56-63 days"),
        StrainProfile(
            id: "runtz", name: "Runtz", type: .hybrid, thc: 26,
            flavors: [.init(name: "Candy"), .init(name: "Syrup"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Fruity candy, sweet syrup, light fuel aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "mac-1", name: "Mac 1", type: .hybrid, thc: 26,
            flavors: [.init(name: "Cherry"), .init(name: "Citrus"), .init(name: "Dough"), .init(name: "Musk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sour cherry, citrus, creamy dough, musk aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gmo-cookies", name: "GMO Cookies", type: .indica, thc: 26,
            flavors: [.init(name: "Garlic"), .init(name: "Mushroom"), .init(name: "Onion"), .init(name: "Diesel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Garlic, mushroom, onion, heavy diesel aromas. Flowers in roughly 10-11 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "motorbreath", name: "Motorbreath", type: .indica, thc: 26,
            flavors: [.init(name: "Fuel"), .init(name: "Chemical")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Heavy fuel, chemical, citrus cleaner aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "wedding-crashers", name: "Wedding Crashers", type: .sativa, thc: 22,
            flavors: [.init(name: "Vanilla"), .init(name: "Berry"), .init(name: "Fuel"), .init(name: "Grape")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet vanilla, berry, fuel, grape aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "do-si-dos", name: "Do-Si-Dos", type: .indica, thc: 26,
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Floral"), .init(name: "Funk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sweet, earthy, floral, heavy funk aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "slurricane", name: "Slurricane", type: .indica, thc: 22,
            flavors: [.init(name: "Berry"), .init(name: "Grape"), .init(name: "Herbal")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet berry, grape, spicy herbal aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "animal-mints", name: "Animal Mints", type: .indica, thc: 26,
            flavors: [.init(name: "Mint"), .init(name: "Dough"), .init(name: "Diesel"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Mint, cookie dough, diesel, earthy aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "biscotti", name: "Biscotti", type: .indica, thc: 22,
            flavors: [.init(name: "Dough"), .init(name: "Vanilla"), .init(name: "Diesel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet cookie dough, vanilla, diesel aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sherblato", name: "Sherblato", type: .indica, thc: 22,
            flavors: [.init(name: "Gas"), .init(name: "Berry"), .init(name: "Vanilla")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet gas, skunky berry, citrus vanilla aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "ice-cream-cake", name: "Ice Cream Cake", type: .indica, thc: 26,
            flavors: [.init(name: "Vanilla"), .init(name: "Cheese"), .init(name: "Dough")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sweet vanilla, creamy cheese, nutty dough aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-runtz", name: "White Runtz", type: .hybrid, thc: 26,
            flavors: [.init(name: "Candy"), .init(name: "Fruit"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Linalool")],
            summary: "Sweet candy, fruit punch, earthy undertone aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "apple-fritter", name: "Apple Fritter", type: .hybrid, thc: 26,
            flavors: [.init(name: "Pastry"), .init(name: "Cinnamon"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Pinene")],
            summary: "Apple pastry, sweet cinnamon, herbal gas aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cereal-milk", name: "Cereal Milk", type: .hybrid, thc: 22,
            flavors: [.init(name: "Cream"), .init(name: "Cereal"), .init(name: "Fruit")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet cream, sugary cereal, light fruit aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gary-payton", name: "Gary Payton", type: .hybrid, thc: 22,
            flavors: [.init(name: "Diesel"), .init(name: "Pepper"), .init(name: "Herbal"), .init(name: "Sour")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Pinene")],
            summary: "Diesel, heavy pepper, herbal, sour kush aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cheetah-piss", name: "Cheetah Piss", type: .hybrid, thc: 22,
            flavors: [.init(name: "Ammonia"), .init(name: "Chemical"), .init(name: "Citrus"), .init(name: "Funk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Humulene")],
            summary: "Ammonia, sharp chemical, sour citrus, funk aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "jealousy", name: "Jealousy", type: .indica, thc: 26,
            flavors: [.init(name: "Cream"), .init(name: "Plum"), .init(name: "Gas"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet cream, heavy plum, gasoline, earth aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "permanent-marker", name: "Permanent Marker", type: .indica, thc: 26,
            flavors: [.init(name: "Chemical"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sharp ink, industrial chemical, sweet gas aromas. Flowers in roughly 8-9 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "super-boof", name: "Super Boof", type: .hybrid, thc: 22,
            flavors: [.init(name: "Citrus"), .init(name: "Gas"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Tangie citrus, cherry gas, sweet earth aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "tropicana-cookies", name: "Tropicana Cookies", type: .sativa, thc: 19,
            flavors: [.init(name: "Citrus"), .init(name: "Dough"), .init(name: "Fuel")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sharp orange zest, cookie dough, fuel aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Oni Seed Co", lineage: "Girl Scout Cookies x Tangie", floweringTime: "56-63 days"),
        StrainProfile(
            id: "tangie", name: "Tangie", type: .sativa, thc: 16,
            flavors: [.init(name: "Citrus"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Terpinolene")],
            summary: "Tangerine Peel, sweet citrus, skunk aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"], breeder: "DNA Genetics", lineage: "California Orange x Skunk hybrid", floweringTime: "63-70 days"),
        StrainProfile(
            id: "strawberry-banana", name: "Strawberry Banana", type: .indica, thc: 22,
            flavors: [.init(name: "Banana"), .init(name: "Cream")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Fruity banana, sweet strawberry cream aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "banana-kush", name: "Banana Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Banana"), .init(name: "Fruit"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Ripe banana, sweet tree fruit, skunk kush aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "ghost-og", name: "Ghost OG", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Fuel"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Lemon pine, heavy fuel, earthy musk aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "triangle-kush", name: "Triangle Kush", type: .indica, thc: 26,
            flavors: [.init(name: "Fuel"), .init(name: "Earthy"), .init(name: "Citrus"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Deep fuel, swampy earth, sour citrus, spice aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sfv-og-kush", name: "SFV OG Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Chemical"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Harsh pine, lemon pledge, heavy gas aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "tahoe-og-kush", name: "Tahoe OG Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Lemon"), .init(name: "Earthy"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Earthy lemon, damp soil, strong fuel aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "headband", name: "Headband", type: .indica, thc: 22,
            flavors: [.init(name: "Fuel"), .init(name: "Earthy"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Lemon fuel, creamy earth, diesel gas aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "death-star", name: "Death Star", type: .indica, thc: 22,
            flavors: [.init(name: "Rubber"), .init(name: "Fuel"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Skunky rubber, sour fuel, heavy musk aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sensi-star", name: "Sensi Star", type: .indica, thc: 22,
            flavors: [.init(name: "Metallic"), .init(name: "Pine"), .init(name: "Herbal")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Metallic, pungent pine, minty herbal aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Paradise Seeds", lineage: "Afghani x secret parentage", floweringTime: "50-55 days"),
        StrainProfile(
            id: "kosher-kush", name: "Kosher Kush", type: .indica, thc: 26,
            flavors: [.init(name: "Earthy"), .init(name: "Pine"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Rich earth, sweet pine, heavy fruit gas aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "skywalker-og", name: "Skywalker OG", type: .indica, thc: 22,
            flavors: [.init(name: "Herbal"), .init(name: "Fuel"), .init(name: "Berry")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Spicy herbal, jet fuel, sweet berry aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "mazar", name: "Mazar", type: .indica, thc: 19,
            flavors: [.init(name: "Hash"), .init(name: "Incense"), .init(name: "Citrus")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet hash, earthy incense, citrus pop aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "critical-mass", name: "Critical Mass", type: .indica, thc: 16,
            flavors: [.init(name: "Sweet"), .init(name: "Earthy"), .init(name: "Honey"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sweet, earthy, honey, light fruit skunk aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "critical-kush", name: "Critical Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Citrus"), .init(name: "Spice"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Earthy pine, sweet citrus, spice, gas aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-rhino", name: "White Rhino", type: .indica, thc: 22,
            flavors: [.init(name: "Woody"), .init(name: "Hash"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Woody, sweet hash, skunk musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Green House", lineage: "Afghan x Brazilian x South Indian", floweringTime: "55-60 days"),
        StrainProfile(
            id: "great-white-shark", name: "Great White Shark", type: .indica, thc: 19,
            flavors: [.init(name: "Fruit"), .init(name: "Musk"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sweet fruit, intense musk, skunky earth aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "el-nino", name: "El Nino", type: .indica, thc: 19,
            flavors: [.init(name: "Spice"), .init(name: "Herbal"), .init(name: "Incense"), .init(name: "Woody")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Spicy, herbal, sharp incense, wood aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "kali-mist", name: "Kali Mist", type: .sativa, thc: 22,
            flavors: [.init(name: "Spice"), .init(name: "Herbal"), .init(name: "Woody"), .init(name: "Incense")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Pinene")],
            summary: "Spicy, clean herbal, wood, incense aromas. Flowers in roughly 11-13 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "bubble-gum", name: "Bubble Gum", type: .hybrid, thc: 19,
            flavors: [.init(name: "Bubblegum"), .init(name: "Fruit"), .init(name: "Sugar")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Sweet pink bubblegum, fruit, sugar aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chronic", name: "Chronic", type: .hybrid, thc: 22,
            flavors: [.init(name: "Honey"), .init(name: "Floral"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sweet honey, floral, deep skunk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "g13-haze", name: "G13 Haze", type: .sativa, thc: 26,
            flavors: [.init(name: "Spice"), .init(name: "Fruit"), .init(name: "Woody"), .init(name: "Gas")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Spicy sour, tropical fruit, clean wood, gas aromas. Flowers in roughly 10-11 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "laughing-buddha", name: "Laughing Buddha", type: .sativa, thc: 22,
            flavors: [.init(name: "Banana"), .init(name: "Spice"), .init(name: "Nutty"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Terpinolene"), .init(name: "Caryophyllene")],
            summary: "Sweet banana, spice, toasted nuts, earth aromas. Flowers in roughly 10-12 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "liberty-haze", name: "Liberty Haze", type: .hybrid, thc: 26,
            flavors: [.init(name: "Citrus"), .init(name: "Herbal"), .init(name: "Fuel")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Lime citrus, classic herbal haze, diesel fuel aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "acapulco-gold-x-cinderella-99", name: "Acapulco Gold x Cinderella 99", type: .sativa, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Terpinolene"), .init(name: "Limonene")],
            summary: "Sweet tropical fruit, dynamic wood spice aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "william-s-wonder", name: "William's Wonder", type: .indica, thc: 22,
            flavors: [.init(name: "Candy"), .init(name: "Apple"), .init(name: "Hash")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Citrus candy, sour apple, deep hash resin aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-cheese", name: "Blue Cheese", type: .indica, thc: 19,
            flavors: [.init(name: "Cream"), .init(name: "Cheese"), .init(name: "Musk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Blueberry cream, sharp blue cheese, musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "u-k-cheese", name: "U.K. Cheese", type: .hybrid, thc: 16,
            flavors: [.init(name: "Cheese"), .init(name: "Funk"), .init(name: "Grease")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Ocimene")],
            summary: "Sharp dairy cheese, sour funk, skunk grease aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "dairy-queen", name: "Dairy Queen", type: .hybrid, thc: 19,
            flavors: [.init(name: "Cherry"), .init(name: "Cheese"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Sweet cherry, sour curd, vanilla musk aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "space-queen", name: "Space Queen", type: .hybrid, thc: 22,
            flavors: [.init(name: "Pineapple"), .init(name: "Cherry"), .init(name: "Funk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Pineapple, sweet cherry, sharp resin funk aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "romulan", name: "Romulan", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Woody"), .init(name: "Pepper")],
            terpenes: [.init(name: "Pinene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Pungent pine, dense woods, spicy pepper aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "timewreck", name: "Timewreck", type: .sativa, thc: 26,
            flavors: [.init(name: "Lime"), .init(name: "Fruit"), .init(name: "Gas")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sour lime, rotten fruit, sandalwood gas aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chernobyl", name: "Chernobyl", type: .sativa, thc: 22,
            flavors: [.init(name: "Cream"), .init(name: "Chemical"), .init(name: "Fuel")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Lime sherbet, citrus cleaner, chemical fuel aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "jtr-jack-the-ripper", name: "JTR (Jack the Ripper)", type: .sativa, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Pine"), .init(name: "Chemical")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Limonene"), .init(name: "Pinene")],
            summary: "Lemon juice, pine tree, resin cleaner aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "vortex", name: "Vortex", type: .sativa, thc: 22,
            flavors: [.init(name: "Mango"), .init(name: "Citrus"), .init(name: "Gas")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Rotting mango, sour citrus, sweet cheese gas aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "apollo-13", name: "Apollo 13", type: .sativa, thc: 22,
            flavors: [.init(name: "Fuel"), .init(name: "Pepper"), .init(name: "Funk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Sour fuel, spicy pepper, rubber funk aromas. Flowers in roughly 7-8 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "querkle", name: "Querkle", type: .indica, thc: 19,
            flavors: [.init(name: "Hash"), .init(name: "Musk"), .init(name: "Berry")],
            terpenes: [.init(name: "Linalool"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Grape hash, musk, sweet berry wine aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "the-third-dimension", name: "The Third Dimension", type: .sativa, thc: 22,
            flavors: [.init(name: "Coconut"), .init(name: "Pineapple"), .init(name: "Candy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Terpinolene")],
            summary: "Coconut, pineapple, tropical fruit candy aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-ape", name: "Grape Ape", type: .indica, thc: 19,
            flavors: [.init(name: "Soda"), .init(name: "Musk"), .init(name: "Berry")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Grape soda, sweet musk, dark berry aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "mendocino-purps", name: "Mendocino Purps", type: .indica, thc: 19,
            flavors: [.init(name: "Caramel"), .init(name: "Coffee"), .init(name: "Grape")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Linalool"), .init(name: "Caryophyllene")],
            summary: "Caramel, coffee, sweet dark grape aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-urkle", name: "Purple Urkle", type: .indica, thc: 19,
            flavors: [.init(name: "Grape"), .init(name: "Berry"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Linalool"), .init(name: "Caryophyllene")],
            summary: "Skunky grape, sweet berry, wood spice aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "casey-jones", name: "Casey Jones", type: .sativa, thc: 22,
            flavors: [.init(name: "Diesel"), .init(name: "Citrus"), .init(name: "Woody")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Earthy diesel, sweet citrus, floral wood aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "super-lemon-haze", name: "Super Lemon Haze", type: .sativa, thc: 26,
            flavors: [.init(name: "Citrus"), .init(name: "Grapefruit"), .init(name: "Spice")],
            terpenes: [.init(name: "Limonene"), .init(name: "Terpinolene"), .init(name: "Myrcene")],
            summary: "Lemon zest, pink grapefruit, sweet haze spice aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"], breeder: "Greenhouse", lineage: "Lemon Skunk x Super Silver Haze", floweringTime: "65-70 days"),
        StrainProfile(
            id: "wappa", name: "Wappa", type: .indica, thc: 22,
            flavors: [.init(name: "Cherry"), .init(name: "Gas"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet cherry, strawberry gas, deep skunk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Paradise Seeds", lineage: "Sweet Indica selection", floweringTime: "55-60 days"),
        StrainProfile(
            id: "delahaze", name: "Delahaze", type: .sativa, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Citrus"), .init(name: "Cedar")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Mango fruit, sweet citrus haze, clean cedar aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "nebula", name: "Nebula", type: .hybrid, thc: 22,
            flavors: [.init(name: "Honey"), .init(name: "Perfume"), .init(name: "Fruit")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet honey, intense floral perfume, fruity kush aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sensi-star-x-chronic", name: "Sensi Star x Chronic", type: .indica, thc: 22,
            flavors: [.init(name: "Honey"), .init(name: "Musk"), .init(name: "Woody")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Metallic honey, pungent sweet musk, wood aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "belladonna", name: "Belladonna", type: .sativa, thc: 19,
            flavors: [.init(name: "Skunk"), .init(name: "Berry"), .init(name: "Pepper")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Fruity skunk, sweet berry, spicy pepper aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "allkush", name: "Allkush", type: .indica, thc: 19,
            flavors: [.init(name: "Musk"), .init(name: "Hash"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Sweet musk, traditional hash, deep forest earth aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "spoetnik-1", name: "Spoetnik #1", type: .indica, thc: 16,
            flavors: [.init(name: "Grape"), .init(name: "Earthy"), .init(name: "Hash")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sour grape, dark earth, deep resin hash aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "ice-cream", name: "Ice Cream", type: .indica, thc: 22,
            flavors: [.init(name: "Cream"), .init(name: "Sugar"), .init(name: "Skunk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Vanilla cream, sweet sugar paste, light skunk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "durga-mata", name: "Durga Mata", type: .indica, thc: 16,
            flavors: [.init(name: "Sweet"), .init(name: "Perfume"), .init(name: "Hash")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Linalool")],
            summary: "Turkish delight, perfume, rich incense hash aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "opium", name: "Opium", type: .hybrid, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Grape"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Creamy tropical fruit, sour grape, light musk aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pandora", name: "Pandora", type: .indica, thc: 19,
            flavors: [.init(name: "Fruit"), .init(name: "Herbal"), .init(name: "Spice")],
            terpenes: [],
            summary: "Sweet fruit, intense green vegetation, spice aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "acid", name: "Acid", type: .indica, thc: 22,
            flavors: [.init(name: "Grapefruit"), .init(name: "Diesel"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sour grapefruit, chemical diesel, metallic gas aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "automaria-ii", name: "Automaria II", type: .sativa, thc: 16,
            flavors: [.init(name: "Floral"), .init(name: "Spice"), .init(name: "Herbal")],
            terpenes: [],
            summary: "Floral, sweet spice, fresh cut herbs aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "jack-flash", name: "Jack Flash", type: .sativa, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Mint"), .init(name: "Skunk")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Pungent pine, sharp mint, sweet citrus skunk aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "shiva-shanti", name: "Shiva Shanti", type: .indica, thc: 16,
            flavors: [.init(name: "Garlic"), .init(name: "Onion"), .init(name: "Musk"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Garlic, raw onion, chemical musk, earth aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"], breeder: "Sensi Seeds", lineage: "Garlic Bud x Skunk x Afghan", floweringTime: "50-55 days"),
        StrainProfile(
            id: "maple-leaf-indica", name: "Maple Leaf Indica", type: .indica, thc: 16,
            flavors: [.init(name: "Syrup"), .init(name: "Sugar"), .init(name: "Oil")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Linalool")],
            summary: "Sweet maple syrup, brown sugar, heavy hash oil aromas. Flowers in roughly 6-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "americano", name: "Americano", type: .indica, thc: 22,
            flavors: [.init(name: "Coffee"), .init(name: "Hash"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Roasted coffee beans, sweet hash, deep musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-domina", name: "Black Domina", type: .indica, thc: 22,
            flavors: [.init(name: "Blackberry"), .init(name: "Pepper"), .init(name: "Hash"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Blackberry, dark pepper, incense hash, fuel aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "hash-plant", name: "Hash Plant", type: .indica, thc: 19,
            flavors: [.init(name: "Hash"), .init(name: "Cedar"), .init(name: "Earthy"), .init(name: "Smoke")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Spicy hash, rich cedar, damp clay, smoke aromas. Flowers in roughly 6-7 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "ortega", name: "Ortega", type: .indica, thc: 16,
            flavors: [.init(name: "Tobacco"), .init(name: "Woody"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet berry tobacco, spicy wood, earth aromas. Flowers in roughly 6-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "early-girl", name: "Early Girl", type: .indica, thc: 16,
            flavors: [.init(name: "Hash"), .init(name: "Earthy"), .init(name: "Citrus")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Pinene"), .init(name: "Caryophyllene")],
            summary: "Hashish, fresh mountain turf, light lime zest aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "early-skunk", name: "Early Skunk", type: .indica, thc: 16,
            flavors: [.init(name: "Skunk"), .init(name: "Herbal"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Pinene"), .init(name: "Caryophyllene")],
            summary: "Sweet skunk, raw vegetation, pungent spice aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "early-pearl", name: "Early Pearl", type: .sativa, thc: 16,
            flavors: [.init(name: "Straw"), .init(name: "Woody"), .init(name: "Musk")],
            terpenes: [.init(name: "Pinene"), .init(name: "Myrcene"), .init(name: "Terpinolene")],
            summary: "Straw, clean wood, sweet dynamic musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "big-bud", name: "Big Bud", type: .indica, thc: 16,
            flavors: [.init(name: "Grape"), .init(name: "Skunk"), .init(name: "Syrup")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Pinene"), .init(name: "Caryophyllene")],
            summary: "Sweet grape, light skunk, earthy syrup aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "silver-haze", name: "Silver Haze", type: .sativa, thc: 22,
            flavors: [.init(name: "Pepper"), .init(name: "Pine"), .init(name: "Metallic"), .init(name: "Gas")],
            terpenes: [.init(name: "Terpinolene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Spicy pepper, silver pine, sharp metal, gas aromas. Flowers in roughly 10-11 weeks, experienced to grow.",
            sources: ["Built-in"], breeder: "Sensi Seeds", lineage: "Silver Haze backcross line", floweringTime: "65-75 days"),
        StrainProfile(
            id: "fruity-juice", name: "Fruity Juice", type: .hybrid, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Mango"), .init(name: "Hash")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Pinene")],
            summary: "Tropical juice, sweet mango, pungent hash back aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "marley-s-collie", name: "Marley's Collie", type: .sativa, thc: 22,
            flavors: [.init(name: "Herbal"), .init(name: "Fuel"), .init(name: "Sugar"), .init(name: "Smoke")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Terpinolene"), .init(name: "Caryophyllene")],
            summary: "Sweet grass, sharp fuel, maple sugar, smoke aromas. Flowers in roughly 9-11 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "nyc-diesel", name: "NYC Diesel", type: .sativa, thc: 19,
            flavors: [.init(name: "Grapefruit"), .init(name: "Lime"), .init(name: "Oil")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Red grapefruit, chemical lime, diesel oil aromas. Flowers in roughly 10-11 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "soma-skunk-v", name: "Soma Skunk V+", type: .indica, thc: 22,
            flavors: [.init(name: "Skunk"), .init(name: "Spice"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet citrus skunk, raw spice, earth musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "somango", name: "Somango", type: .indica, thc: 22,
            flavors: [.init(name: "Mango"), .init(name: "Syrup"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Ripe mango, tropical fruit syrup, chalky gas aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "buddha-s-sister", name: "Buddha's Sister", type: .indica, thc: 22,
            flavors: [.init(name: "Cherry"), .init(name: "Candy"), .init(name: "Pine"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Tart cherry, sour candy, clean pine, earth aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "reclining-buddha", name: "Reclining Buddha", type: .indica, thc: 16,
            flavors: [.init(name: "Cherry"), .init(name: "Straw"), .init(name: "Skunk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Sweet cherry, dry straw, earth skunk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "holland-s-hope", name: "Holland's Hope", type: .indica, thc: 16,
            flavors: [.init(name: "Plum"), .init(name: "Woody"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Pinene"), .init(name: "Caryophyllene")],
            summary: "Plum, sweet wood, heavy damp moss aromas. Flowers in roughly 7-8 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lavender", name: "Lavender", type: .indica, thc: 22,
            flavors: [.init(name: "Floral"), .init(name: "Hash"), .init(name: "Spice")],
            terpenes: [.init(name: "Linalool"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Fresh lavender flowers, dark hash, spice aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "rock-bud", name: "Rock Bud", type: .indica, thc: 19,
            flavors: [.init(name: "Cedar"), .init(name: "Hash"), .init(name: "Pepper")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Spicy cedar, intense traditional hash, pepper aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "amnesia-lemon", name: "Amnesia Lemon", type: .sativa, thc: 22,
            flavors: [.init(name: "Candy"), .init(name: "Haze"), .init(name: "Pine")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Sharp lemon drops, sweet haze, crisp pine aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pineapple-chunk", name: "Pineapple Chunk", type: .indica, thc: 26,
            flavors: [.init(name: "Candy"), .init(name: "Cheese"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Pineapple candy, sharp sour curd, funk gas aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pineapple", name: "Pineapple", type: .indica, thc: 19,
            flavors: [.init(name: "Pineapple"), .init(name: "Sugar"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Sweet pineapple paste, tropical sugar, gas aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "violator-kush", name: "Violator Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Earthy"), .init(name: "Grease"), .init(name: "Spice")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Musty earth, intense charas grease, spice aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "acme-kush", name: "Acme Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Wax"), .init(name: "Earthy"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Lemon floor wax, swamp mud, heavy petroleum aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gloom", name: "Gloom", type: .indica, thc: 22,
            flavors: [.init(name: "Coffee"), .init(name: "Cacao"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Linalool")],
            summary: "Dark roast coffee, dark cacao, pepper musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pound-cake", name: "Pound Cake", type: .indica, thc: 26,
            flavors: [.init(name: "Dough"), .init(name: "Citrus"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet vanilla batter, lemon zest, light gas aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chemdawg-91", name: "Chemdawg '91", type: .hybrid, thc: 26,
            flavors: [.init(name: "Fuel"), .init(name: "Skunk"), .init(name: "Chemical")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Chemical fuel, skunk spray, lemon cleaner aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-diesel-v3", name: "Sour Diesel v3", type: .sativa, thc: 22,
            flavors: [.init(name: "Fuel"), .init(name: "Lime"), .init(name: "Musk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Petroleum fuel, rank sour lime, deep musk aromas. Flowers in roughly 10-11 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "east-coast-sour-diesel", name: "East Coast Sour Diesel", type: .sativa, thc: 26,
            flavors: [.init(name: "Fuel"), .init(name: "Citrus"), .init(name: "Grease")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Raw diesel fuel, chemical citrus, rank grease aromas. Flowers in roughly 10-12 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "stardawg", name: "Stardawg", type: .sativa, thc: 26,
            flavors: [.init(name: "Chemical"), .init(name: "Oil"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Chemical cleaner, garlic oil, diesel fuel aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "tres-dawg", name: "Tres Dawg", type: .indica, thc: 22,
            flavors: [.init(name: "Skunk"), .init(name: "Garlic"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Pungent skunk, raw garlic, deep oil gas aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "chem-4", name: "Chem 4", type: .hybrid, thc: 22,
            flavors: [.init(name: "Chemical"), .init(name: "Gas"), .init(name: "Funk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Citrus cleaner, heavy gasoline, chemical funk aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "albert-walker", name: "Albert Walker", type: .indica, thc: 22,
            flavors: [.init(name: "Tangerine"), .init(name: "Skunk"), .init(name: "Citrus")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Rotting tangerine, chemical skunk, lemon peel aromas. Flowers in roughly 8-9 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-afghani", name: "Sour Afghani", type: .indica, thc: 22,
            flavors: [.init(name: "Fuel"), .init(name: "Hash"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sour fuel, rich hashish, thick earth musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "giger", name: "Giger", type: .indica, thc: 26,
            flavors: [.init(name: "Oil"), .init(name: "Pepper"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Garlic oil, white pepper, earthy wood gas aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "the-white", name: "The White", type: .hybrid, thc: 26,
            flavors: [.init(name: "Woody"), .init(name: "Earthy"), .init(name: "Pine")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Faint sweet wood, light earth, subtle pine aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-fire-og-wifi-og", name: "White Fire OG (WiFi OG)", type: .sativa, thc: 26,
            flavors: [.init(name: "Pepper"), .init(name: "Fuel"), .init(name: "Oil")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Pungent pepper, burning fuel, lemon oil aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "fire-og", name: "Fire OG", type: .indica, thc: 22,
            flavors: [.init(name: "Woody"), .init(name: "Chemical"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Burning wood, lemon pledge, intense spice fuel aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "mamba", name: "Mamba", type: .indica, thc: 22,
            flavors: [.init(name: "Grape"), .init(name: "Earthy"), .init(name: "Berry")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Linalool"), .init(name: "Caryophyllene")],
            summary: "Sweet grape wine, rich clay earth, dark berry aromas. Flowers in roughly 7-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "alien-kush", name: "Alien Kush", type: .indica, thc: 22,
            flavors: [.init(name: "Herbal"), .init(name: "Tea"), .init(name: "Earthy")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Spicy herbal, red tea, sweet dark soil aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "alien-technology", name: "Alien Technology", type: .indica, thc: 16,
            flavors: [.init(name: "Spice"), .init(name: "Woody"), .init(name: "Vanilla")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Pinene")],
            summary: "Dry spice, cedar wood, light vanilla powder aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lvpk-las-vegas-purple-kush", name: "LVPK (Las Vegas Purple Kush)", type: .indica, thc: 19,
            flavors: [.init(name: "Grape"), .init(name: "Pine"), .init(name: "Musk")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Linalool"), .init(name: "Caryophyllene")],
            summary: "Sweet dark grape, damp pine needles, musk aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "alien-dawg", name: "Alien Dawg", type: .indica, thc: 22,
            flavors: [.init(name: "Fuel"), .init(name: "Spice"), .init(name: "Skunk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Chemical fuel, dry wood spice, rank skunk aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "animal-cookies", name: "Animal Cookies", type: .indica, thc: 26,
            flavors: [.init(name: "Sugar"), .init(name: "Grease"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet brown sugar, cherry grease, heavy fuel aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "forum-cookies", name: "Forum Cookies", type: .indica, thc: 22,
            flavors: [.init(name: "Dough"), .init(name: "Earthy"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Humulene")],
            summary: "Sweet baker's dough, earth spices, vanilla fuel aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "thin-mint-cookies", name: "Thin Mint Cookies", type: .indica, thc: 26,
            flavors: [.init(name: "Peppermint"), .init(name: "Chocolate"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sharp peppermint, dark chocolate, sweet gas aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "platinum-cookies", name: "Platinum Cookies", type: .indica, thc: 22,
            flavors: [.init(name: "Berry"), .init(name: "Dough"), .init(name: "Resin")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet berry, musky fruit dough, heavy resin aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cherry-pie", name: "Cherry Pie", type: .indica, thc: 22,
            flavors: [.init(name: "Cake"), .init(name: "Berry"), .init(name: "Earthy")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Toasted cherry crust, tart berry, light earth aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-pie", name: "Grape Pie", type: .indica, thc: 22,
            flavors: [.init(name: "Jelly"), .init(name: "Flour"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Linalool"), .init(name: "Myrcene")],
            summary: "Sweet grape jelly, baked flour, gas undertone aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-stomper", name: "Grape Stomper", type: .hybrid, thc: 22,
            flavors: [.init(name: "Candy"), .init(name: "Chemical"), .init(name: "Diesel")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Grape candy, sweet chemical, sour diesel pop aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "sundae-driver", name: "Sundae Driver", type: .hybrid, thc: 22,
            flavors: [.init(name: "Cream"), .init(name: "Cereal"), .init(name: "Grape")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sweet cream, fruity cereal, light grape skin aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "fruity-pebbles-og", name: "Fruity Pebbles OG", type: .indica, thc: 22,
            flavors: [.init(name: "Fruit"), .init(name: "Citrus"), .init(name: "Gas")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Tropical berry fruit, sugary citrus, light gas aromas. Flowers in roughly 8-9 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "green-ribbon", name: "Green Ribbon", type: .hybrid, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Cedar"), .init(name: "Fruit")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Caryophyllene"), .init(name: "Limonene")],
            summary: "Sweet pine, fresh cedar shavings, light fruit aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "wedding-gelato", name: "Wedding Gelato", type: .indica, thc: 26,
            flavors: [.init(name: "Vanilla"), .init(name: "Syrup"), .init(name: "Cream")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Vanilla frosting, sweet berry syrup, minty cream aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelato-41", name: "Gelato #41", type: .indica, thc: 26,
            flavors: [.init(name: "Lavender"), .init(name: "Fuel"), .init(name: "Cream")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Linalool")],
            summary: "Heavy lavender, sweet fuel, berry cream fudge aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelato-45", name: "Gelato #45", type: .indica, thc: 22,
            flavors: [.init(name: "Dough"), .init(name: "Citrus"), .init(name: "Fruit")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet sugar dough, heavy pine zest, citrus fruit aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "pink-panties", name: "Pink Panties", type: .indica, thc: 19,
            flavors: [.init(name: "Citrus"), .init(name: "Musk"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Tart chemical citrus, herbal musk, light fuel aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "london-pound-cake-75", name: "London Pound Cake #75", type: .indica, thc: 26,
            flavors: [.init(name: "Cake"), .init(name: "Oil"), .init(name: "Berry")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Lemon zest cake, heavy diesel oil, vanilla berry aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelonade", name: "Gelonade", type: .sativa, thc: 22,
            flavors: [.init(name: "Citrus"), .init(name: "Candy"), .init(name: "Gas")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sharp lemon peel, fizzy citrus candy, sweet gas aromas. Flowers in roughly 9-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-tree", name: "Lemon Tree", type: .hybrid, thc: 22,
            flavors: [.init(name: "Wax"), .init(name: "Fuel"), .init(name: "Earthy")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sharp lemon floor wax, industrial fuel, wet earth aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-runtz-s1", name: "White Runtz S1", type: .hybrid, thc: 26,
            flavors: [.init(name: "Candy"), .init(name: "Resin"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Linalool")],
            summary: "Sugary syrup fruit candy, heavy resin coating, gas aromas. Flowers in roughly 8-9 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "red-velvet", name: "Red Velvet", type: .hybrid, thc: 22,
            flavors: [.init(name: "Cake"), .init(name: "Oil"), .init(name: "Citrus")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sweet chocolate cake, cherry oil, citrus peel aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-cherry-gelato", name: "Lemon Cherry Gelato", type: .indica, thc: 26,
            flavors: [.init(name: "Syrup"), .init(name: "Gas"), .init(name: "Musk")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Sour cherry syrup, sweet citrus gas, wood musk aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "oreoz", name: "Oreoz", type: .indica, thc: 26,
            flavors: [.init(name: "Chocolate"), .init(name: "Smoky"), .init(name: "Fuel")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Chocolate cookies, campfire s'mores, sweet fuel aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cookies-cream", name: "Cookies & Cream", type: .hybrid, thc: 22,
            flavors: [.init(name: "Vanilla"), .init(name: "Dairy"), .init(name: "Sugar")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Vanilla paste, sweet cream dairy, nutty sugar aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "starfighter", name: "Starfighter", type: .indica, thc: 22,
            flavors: [.init(name: "Pine"), .init(name: "Chemical"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Sweet pine needles, lemon floor polish, fuel aromas. Flowers in roughly 8-9 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "secret-weapon", name: "Secret Weapon", type: .sativa, thc: 22,
            flavors: [.init(name: "Skunk"), .init(name: "Pepper"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Pungent cheese skunk, white pepper, cedar gas aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-cream-cake", name: "Grape Cream Cake", type: .indica, thc: 22,
            flavors: [.init(name: "Yogurt"), .init(name: "Vanilla"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Linalool")],
            summary: "Grape yogurt, vanilla bean, smooth cake gas aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "tropicana-cherry", name: "Tropicana Cherry", type: .sativa, thc: 22,
            flavors: [.init(name: "Orange"), .init(name: "Candy"), .init(name: "Funk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Myrcene"), .init(name: "Caryophyllene")],
            summary: "Sharp blood orange, sour cherry candy, fuel funk aromas. Flowers in roughly 8-10 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cherry-cookies", name: "Cherry Cookies", type: .indica, thc: 19,
            flavors: [.init(name: "Cherry"), .init(name: "Dough"), .init(name: "Spice")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Sweet cherry glaze, flour dough, earthy spice aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cadillac-rainbows", name: "Cadillac Rainbows", type: .indica, thc: 26,
            flavors: [.init(name: "Funk"), .init(name: "Gas"), .init(name: "Fruit")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Garlic funk, fuel gas, sweet sugary fruit blend aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "modified-grapes", name: "Modified Grapes", type: .indica, thc: 26,
            flavors: [.init(name: "Garlic"), .init(name: "Grape"), .init(name: "Gas")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Limonene"), .init(name: "Myrcene")],
            summary: "Garlic bulb, rotten grape skin, deep chemical gas aromas. Flowers in roughly 9-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "hans-solo-burger", name: "Hans Solo Burger", type: .indica, thc: 26,
            flavors: [.init(name: "Musk"), .init(name: "Oil"), .init(name: "Wax")],
            terpenes: [.init(name: "Caryophyllene"), .init(name: "Myrcene"), .init(name: "Limonene")],
            summary: "Rank chemical musk, heavy fuel oil, pine floor wax aromas. Flowers in roughly 9-11 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "larry-og", name: "Larry OG", type: .indica, thc: 22,
            flavors: [.init(name: "Oil"), .init(name: "Earthy"), .init(name: "Fuel")],
            terpenes: [.init(name: "Myrcene"), .init(name: "Limonene"), .init(name: "Caryophyllene")],
            summary: "Fresh lemon oil, damp earth turf, pungent gas fuel aromas. Flowers in roughly 8-9 weeks, easy to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "spritzer", name: "Spritzer", type: .sativa, thc: 22,
            flavors: [.init(name: "Soda"), .init(name: "Chemical"), .init(name: "Gas")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Fizzy grape soda, cherry chemical cleaner, sour gas aromas. Flowers in roughly 8-10 weeks, moderate to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "cap-junkie", name: "Cap Junkie", type: .hybrid, thc: 26,
            flavors: [.init(name: "Fuel"), .init(name: "Citrus"), .init(name: "Musk")],
            terpenes: [.init(name: "Limonene"), .init(name: "Caryophyllene"), .init(name: "Myrcene")],
            summary: "Sharp pungent fuel, sweet creamy rind, chemical musk aromas. Flowers in roughly 9-10 weeks, experienced to grow.",
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelato", name: "Gelato", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gsc", name: "GSC", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gg4", name: "GG4", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-haze", name: "Purple Haze", type: .sativa,
            effects: [.init(name: "Euphoric", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "the-original-z", name: "The Original Z", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hash-burger", name: "Hash Burger", type: .hybrid,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dosidos", name: "Dosidos", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-truffle", name: "White Truffle", type: .hybrid,
            effects: [.init(name: "Tingly", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "unicorn-poop", name: "Unicorn Poop", type: .hybrid,
            effects: [.init(name: "Tingly", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "alaskan-thunder-fuck", name: "Alaskan Thunder Fuck", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "berry-white", name: "Berry White", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blackberry-kush", name: "Blackberry Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cannatonic", name: "Cannatonic", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "diamond-og", name: "Diamond OG", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dirty-taxi", name: "Dirty Taxi", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "donny-burger", name: "Donny Burger", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dutch-treat", name: "Dutch Treat", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "el-chivo", name: "El Chivo", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "eurban-kush", name: "Eurban Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "forbidden-fruit", name: "Forbidden Fruit", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fruit-loops", name: "Fruit Loops", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fruity-pebbles", name: "Fruity Pebbles", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "garlic-cocktail", name: "Garlic Cocktail", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gastro-pop", name: "Gastro Pop", type: .hybrid,
            effects: [.init(name: "Tingly", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ghost-train-haze", name: "Ghost Train Haze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "glitter-bomb", name: "Glitter Bomb", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "god-s-gift", name: "God's Gift", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gorilla-wreck", name: "Gorilla Wreck", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "grapefruit", name: "Grapefruit", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gumbo", name: "Gumbo", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "harlequin", name: "Harlequin", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "incredible-bulk", name: "Incredible Bulk", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jemini", name: "Jemini", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jet-fuel", name: "Jet Fuel", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jokerz", name: "Jokerz", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "juicy-j", name: "Juicy J", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "key-lime-pie", name: "Key Lime Pie", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "la-kush-cake", name: "LA Kush Cake", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lamb-s-bread", name: "Lamb's Bread", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-banana-sherbet", name: "Lemon Banana Sherbet", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-garlic-og", name: "Lemon Garlic OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-haze", name: "Lemon Haze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lizard-burger", name: "Lizard Burger", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mandarin-cookies", name: "Mandarin Cookies", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mango-kush", name: "Mango Kush", type: .hybrid,
            effects: [.init(name: "Giggly", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mendo-breath", name: "Mendo Breath", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mimosa", name: "Mimosa", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "moon-dog", name: "Moon Dog", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mt-hood-magic", name: "Mt. Hood Magic", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "obba-kush", name: "Obba Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "orange-bud", name: "Orange Bud", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "orange-cookies", name: "Orange Cookies", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "papaya", name: "Papaya", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "peanut-butter-breath", name: "Peanut Butter Breath", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pennywise", name: "Pennywise", type: .indica,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pink-kush", name: "Pink Kush", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pink-runtz", name: "Pink Runtz", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "platinum-og", name: "Platinum OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pluto-kush", name: "Pluto Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pre-98-bubba-kush", name: "Pre-98 Bubba Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "presidential-og", name: "Presidential OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "quantum-kush", name: "Quantum Kush", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "red-congolese", name: "Red Congolese", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "runtz-muffin", name: "Runtz Muffin", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sage-n-sour", name: "Sage N Sour", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "schrom", name: "Schrom", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sensistar", name: "Sensistar", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sherbert", name: "Sherbert", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "silver-spoon", name: "Silver Spoon", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "snoop-dogg-og", name: "Snoop Dogg OG", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "snowcap", name: "Snowcap", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-banana-sherbet", name: "Sour Banana Sherbet", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-og", name: "Sour OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-tsunami", name: "Sour Tsunami", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "stank-breath", name: "Stank Breath", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "strawberry-lemonade", name: "Strawberry Lemonade", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "strawberry-og", name: "Strawberry OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sugar-black-rose", name: "Sugar Black Rose", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"], breeder: "Delicious Seeds", lineage: "Critical Mass x Black Domina", floweringTime: "50-55 days"),
        StrainProfile(
            id: "super-jack", name: "Super Jack", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sweet-tooth", name: "Sweet Tooth", type: .indica,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"], breeder: "Barney's Farm", lineage: "Afghani x Hawaiian x Nepali", floweringTime: "55-60 days"),
        StrainProfile(
            id: "thai", name: "Thai", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "the-soap", name: "The Soap", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "thin-mint-gsc", name: "Thin Mint GSC", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"], breeder: "Cookie Fam", lineage: "Girl Scout Cookies phenotype selection", floweringTime: "56-63 days"),
        StrainProfile(
            id: "three-kings", name: "Three Kings", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "tropicanna-cookies", name: "Tropicanna Cookies", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "uk-cheese", name: "UK Cheese", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "vanilla-frosting", name: "Vanilla Frosting", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "venom-og", name: "Venom OG", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "waffle-bites", name: "Waffle Bites", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "walter-white", name: "Walter White", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "watermelon-zkittlez", name: "Watermelon Zkittlez", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "whitethorn-rose", name: "Whitethorn Rose", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "wi-fi-og", name: "Wi-Fi OG", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "xj-13", name: "XJ-13", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "y-griega", name: "Y Griega", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "zkittlez-pie", name: "Zkittlez Pie", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "zlucee", name: "Zlucee", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "9-lb-hammer", name: "9 lb Hammer", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "animal-face", name: "Animal Face", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "alien-og", name: "Alien OG", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "apples-and-bananas", name: "Apples and Bananas", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "banana-og", name: "Banana OG", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bio-diesel", name: "Bio-Diesel", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-diamond", name: "Black Diamond", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-jack", name: "Black Jack", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-magic-kush", name: "Black Magic Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blueberry-kush", name: "Blueberry Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-diamond", name: "Blue Diamond", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-gelato", name: "Blue Gelato", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-og", name: "Blue OG", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cap-junky", name: "Cap Junky", type: .hybrid,
            effects: [.init(name: "Tingly", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "candy-cake", name: "Candy Cake", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "candy-runtz", name: "Candy Runtz", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "carbon-fiber", name: "Carbon Fiber", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cat-piss", name: "Cat Piss", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "chem-i95", name: "Chem I95", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "chemango-kush", name: "Chemango Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cherry-punch", name: "Cherry Punch", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "chocolate-kush", name: "Chocolate Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cold-creek-kush", name: "Cold Creek Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cookies-and-cream", name: "Cookies and Cream", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dark-matter", name: "Dark Matter", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dirty-girl", name: "Dirty Girl", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "donkey-butter", name: "Donkey Butter", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "double-dream", name: "Double Dream", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dynamite", name: "Dynamite", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "earthquake", name: "Earthquake", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "electric-shock", name: "Electric Shock", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ewok", name: "Ewok", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fat-banana", name: "Fat Banana", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fuel-biscuits", name: "Fuel Biscuits", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "frosted-guava", name: "Frosted Guava", type: .hybrid,
            effects: [.init(name: "Euphoric", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "frosted-pancakes", name: "Frosted Pancakes", type: .hybrid,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "garlic-icing", name: "Garlic Icing", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelatti", name: "Gelatti", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gelato-dream", name: "Gelato Dream", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "georgia-pie", name: "Georgia Pie", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ghost-wreck-haze", name: "Ghost Wreck Haze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "glookies", name: "Glookies", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "golden-goat", name: "Golden Goat", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "green-gelato", name: "Green Gelato", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "grey-goose", name: "Grey Goose", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gushers", name: "Gushers", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hawaiian", name: "Hawaiian", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "haze", name: "Haze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "heir-heads", name: "Heir Heads", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "high-octane-mintz", name: "High Octane Mintz", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "holy-grail-kush", name: "Holy Grail Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "huckleberry", name: "Huckleberry", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hypothermia", name: "Hypothermia", type: .hybrid,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ice-cream-man", name: "Ice Cream Man", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "inzane-in-the-membrane", name: "Inzane in the Membrane", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "island-sweet-skunk", name: "Island Sweet Skunk", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jacks-cleaner", name: "Jacks Cleaner", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jean-guy", name: "Jean Guy", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jet-fuel-gelato", name: "Jet Fuel Gelato", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "juicy-fruit", name: "Juicy Fruit", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "kryptonite", name: "Kryptonite", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "kush-cookies", name: "Kush Cookies", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "la-bomba", name: "La Bomba", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "liquid-gold", name: "Liquid Gold", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lodi-dodi", name: "Lodi Dodi", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "london-pound-cake", name: "London Pound Cake", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mac-daddy", name: "Mac Daddy", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mango-haze", name: "Mango Haze", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "marionberry-kush", name: "Marionberry Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mars-og", name: "Mars OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "medicine-man", name: "Medicine Man", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "moby-dick", name: "Moby Dick", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "nevil-s-haze", name: "Nevil's Haze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "northern-lights-5", name: "Northern Lights #5", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "oaxacan-kush", name: "Oaxacan Kush", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "omfg", name: "OMFG", type: .hybrid,
            effects: [.init(name: "Giggly", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "orange-velvet", name: "Orange Velvet", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "paris-og", name: "Paris OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "phantom-cookies", name: "Phantom Cookies", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pineapple-kush", name: "Pineapple Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pink-diesel", name: "Pink Diesel", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "platinum-garlic", name: "Platinum Garlic", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pluto-mintz", name: "Pluto Mintz", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pure-power-plant", name: "Pure Power Plant", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-diesel", name: "Purple Diesel", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-kush", name: "Purple Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "qleaner", name: "Qleaner", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "redwood-kush", name: "Redwood Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "royal-kush", name: "Royal Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "russian-cream", name: "Russian Cream", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "scooby-snacks", name: "Scooby Snacks", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "shark-shock", name: "Shark Shock", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "skywalker", name: "Skywalker", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "snow-white", name: "Snow White", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-blueberry", name: "Sour Blueberry", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-chem", name: "Sour Chem", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "space-cake", name: "Space Cake", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "squirt", name: "Squirt", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "strawberry-cake", name: "Strawberry Cake", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sugar-cookie", name: "Sugar Cookie", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sunset-sherbet", name: "Sunset Sherbet", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "super-sour-diesel", name: "Super Sour Diesel", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "supreme-cbd", name: "Supreme CBD", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sweet-skunk", name: "Sweet Skunk", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "tangerine-dream", name: "Tangerine Dream", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "texas-resin", name: "Texas Resin", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "the-third-eye", name: "The Third Eye", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "tom-ford-pink-kush", name: "Tom Ford Pink Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "trap-fuel", name: "Trap Fuel", type: .hybrid,
            effects: [.init(name: "Calming", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "trinity", name: "Trinity", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "tsunami", name: "Tsunami", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ultra-sour", name: "Ultra Sour", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "vader-og", name: "Vader OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "vanilla-kush", name: "Vanilla Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "white-slipper", name: "White Slipper", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "willy-s-wonder", name: "Willy's Wonder", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "wonder-woman", name: "Wonder Woman", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "zombie-kush", name: "Zombie Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "zoom-pie", name: "Zoom Pie", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "abusive-og", name: "Abusive OG", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "afgoo", name: "Afgoo", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "alien-rock-candy", name: "Alien Rock Candy", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "allen-wrench", name: "Allen Wrench", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "apricot-jelly", name: "Apricot Jelly", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ashton-kutcher-kush", name: "Ashton Kutcher Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "atomic-northern-lights", name: "Atomic Northern Lights", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ayahuasca-purple", name: "Ayahuasca Purple", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "banana-bread", name: "Banana Bread", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "banana-punch", name: "Banana Punch", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bay-11", name: "Bay 11", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bedrocan", name: "Bedrocan", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bermuda-triangle-og", name: "Bermuda Triangle OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bio-jesus", name: "Bio-Jesus", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-cherry-soda", name: "Black Cherry Soda", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "black-84", name: "Black 84", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blackberry", name: "Blackberry", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-boy", name: "Blue Boy", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-dragon", name: "Blue Dragon", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-knight", name: "Blue Knight", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-magoo", name: "Blue Magoo", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-monster", name: "Blue Monster", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blue-velvet", name: "Blue Velvet", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blueberry-muffins", name: "Blueberry Muffins", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "blueberry-silly", name: "Blueberry Silly", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bogart-kush", name: "Bogart Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bootlegger", name: "Bootlegger", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "brainwreck", name: "Brainwreck", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "brooklyn-mango", name: "Brooklyn Mango", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bruce-banner", name: "Bruce Banner", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bubba-diagonal", name: "Bubba Diagonal", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "bubble-runtz", name: "Bubble Runtz", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "burmese-kush", name: "Burmese Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cabbage-patch", name: "Cabbage Patch", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cali-kush", name: "Cali Kush", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cali-sour", name: "Cali Sour", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "candy-jack", name: "Candy Jack", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "candy-land", name: "Candy Land", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "catfish", name: "Catfish", type: .sativa,
            effects: [.init(name: "Talkative", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "caviar-og", name: "Caviar OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "charlie-sheen", name: "Charlie Sheen", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cheese", name: "Cheese", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cherry-gar-see-ya", name: "Cherry Gar-See-Ya", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cherry-kola", name: "Cherry Kola", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "choco-bud", name: "Choco Bud", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "chocolate-rain", name: "Chocolate Rain", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "chocolope-kush", name: "Chocolope Kush", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "citradelic-sunset", name: "Citradelic Sunset", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "citrix", name: "Citrix", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cluster-bomb", name: "Cluster Bomb", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "comatose-og", name: "Comatose OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cotton-candy-kush", name: "Cotton Candy Kush", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "crypto-chronic", name: "Crypto Chronic", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "cuvee", name: "Cuvee", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dank-schrader", name: "Dank Schrader", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dark-star", name: "Dark Star", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "deep-purple", name: "Deep Purple", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "desert-gold", name: "Desert Gold", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "diablo-og", name: "Diablo OG", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "diesel-dough", name: "Diesel Dough", type: .hybrid,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dilithium", name: "Dilithium", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ditch-weed", name: "Ditch Weed", type: .hybrid,
            effects: [.init(name: "Calming", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "divided-sky", name: "Divided Sky", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dj-short-blueberry", name: "DJ Short Blueberry", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dogwalker-og", name: "Dogwalker OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "double-tangie-banana", name: "Double Tangie Banana", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dragon-s-breath", name: "Dragon's Breath", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "dream-queen", name: "Dream Queen", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "duke-nukem", name: "Duke Nukem", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "durban-cookies", name: "Durban Cookies", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ecto-cooler", name: "Ecto Cooler", type: .hybrid,
            effects: [.init(name: "Bright", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ed-rosenthal-super-bud", name: "Ed Rosenthal Super Bud", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "egyptian-gold", name: "Egyptian Gold", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "elmer-s-glue", name: "Elmer's Glue", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "emerald-jack", name: "Emerald Jack", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "endless-sky", name: "Endless Sky", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "evening-star", name: "Evening Star", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "exodus-cheese", name: "Exodus Cheese", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "face-off-og", name: "Face Off OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "flo", name: "Flo", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "frankenstein", name: "Frankenstein", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fruit-punch", name: "Fruit Punch", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "fucking-incredible", name: "Fucking Incredible", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "funky-monkey", name: "Funky Monkey", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "galactic-jack", name: "Galactic Jack", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "garlotti", name: "Garlotti", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "georgia-peach", name: "Georgia Peach", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ghost-ship-kush", name: "Ghost Ship Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "god-bud", name: "God Bud", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "godzilla-glue", name: "Godzilla Glue", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "golden-ticket", name: "Golden Ticket", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gooberry", name: "Gooberry", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gorilla-cookies", name: "Gorilla Cookies", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-god", name: "Grape God", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "grape-krush", name: "Grape Krush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "green-goblin", name: "Green Goblin", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "green-love-potion", name: "Green Love Potion", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "grimmdica", name: "Grimmdica", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "guava-kush", name: "Guava Kush", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "gummo", name: "Gummo", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hawaiian-snow", name: "Hawaiian Snow", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "heavy-duty-fruity", name: "Heavy Duty Fruity", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hell-s-angel-og", name: "Hell's Angel OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hifi-4g", name: "Hifi 4G", type: .hybrid,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "high-country-diesel", name: "High Country Diesel", type: .hybrid,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "himalayan-gold", name: "Himalayan Gold", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "hollywood-og", name: "Hollywood OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "honey-bananas", name: "Honey Bananas", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ingrid", name: "Ingrid", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "interstellar-kush", name: "Interstellar Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "irish-cream", name: "Irish Cream", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jack-skellington", name: "Jack Skellington", type: .sativa,
            effects: [.init(name: "Creative", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jedi-chem", name: "Jedi Chem", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jelly-donut", name: "Jelly Donut", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jesus-og", name: "Jesus OG", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jillybean", name: "Jillybean", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "johnny-blaze", name: "Johnny Blaze", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "jupiter-og", name: "Jupiter OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "k-train", name: "K-Train", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "kandahar", name: "Kandahar", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "katsu-bubba-kush", name: "Katsu Bubba Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "kaya-gold", name: "Kaya Gold", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ketchum-kush", name: "Ketchum Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "khufu", name: "Khufu", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "king-louis-xiii", name: "King Louis XIII", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "king-s-bread", name: "King's Bread", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "koko-puffs", name: "Koko Puffs", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "kraken", name: "Kraken", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "la-chocolate", name: "LA Chocolate", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-cake", name: "Lemon Cake", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-diesel", name: "Lemon Diesel", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lemon-kush", name: "Lemon Kush", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lime-skunk", name: "Lime Skunk", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "locomotion", name: "Locomotion", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "log-cabin-og", name: "Log Cabin OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "lollipop", name: "Lollipop", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mac-and-cheese", name: "Mac and Cheese", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "madman-og", name: "Madman OG", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "magenta-hash-plant", name: "Magenta Hash Plant", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "malawi-gold", name: "Malawi Gold", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "martian-mean-green", name: "Martian Mean Green", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "matanuska-thunder-fuck", name: "Matanuska Thunder Fuck", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "maui", name: "Maui", type: .sativa,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "meatbreath", name: "Meatbreath", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "melonade", name: "Melonade", type: .sativa,
            effects: [.init(name: "Uplifted", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mendo-purps", name: "Mendo Purps", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "mickey-kush", name: "Mickey Kush", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Terpinolene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "midnight", name: "Midnight", type: .hybrid,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "monster-cookies", name: "Monster Cookies", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "neon-kush", name: "Neon Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "nirvana-kush", name: "Nirvana Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "nuclear-cookies", name: "Nuclear Cookies", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "og-eddy-lepp", name: "OG Eddy Lepp", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ogre", name: "Ogre", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "orange-creamsicle", name: "Orange Creamsicle", type: .hybrid,
            effects: [.init(name: "Happy", intensity: 0.8)],
            terpenes: [.init(name: "Limonene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "orr-kush", name: "Orr Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "outer-space", name: "Outer Space", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pacific-frost", name: "Pacific Frost", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "peyote-cookies", name: "Peyote Cookies", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pink-champagne", name: "Pink Champagne", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "pot-of-gold", name: "Pot of Gold", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-afghan-kush", name: "Purple Afghan Kush", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-candy", name: "Purple Candy", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "purple-panty-dropper", name: "Purple Panty Dropper", type: .indica,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "red-velvet-juice", name: "Red Velvet Juice", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "ripped-bubba", name: "Ripped Bubba", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "royal-gorilla", name: "Royal Gorilla", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "satori", name: "Satori", type: .sativa,
            effects: [.init(name: "Focused", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"], breeder: "Mandala Seeds", lineage: "Nepal Landrace hybrid", floweringTime: "65-70 days"),
        StrainProfile(
            id: "scout-breath", name: "Scout Breath", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Caryophyllene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sensie-star", name: "Sensie Star", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sequoiya", name: "Sequoiya", type: .indica,
            effects: [.init(name: "Sleepy", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "shipwreck", name: "Shipwreck", type: .hybrid,
            effects: [.init(name: "Relaxed", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "silver-bubble", name: "Silver Bubble", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"]),
        StrainProfile(
            id: "sour-joker", name: "Sour Joker", type: .sativa,
            effects: [.init(name: "Energetic", intensity: 0.8)],
            terpenes: [.init(name: "Myrcene")],
            sources: ["Built-in"])
    ]
}

// MARK: - Terpene education (#12)

/// What a terpene smells like and is commonly associated with. Educational, not
/// medical advice. Keyed by lowercased terpene name.
struct TerpeneFact: Identifiable {
    var id: String { name }
    let name: String
    let aroma: String
    let effect: String
    let alsoIn: String
}

enum TerpeneLibrary {
    static let facts: [String: TerpeneFact] = [
        "myrcene": .init(name: "Myrcene", aroma: "Earthy, musky, clove",
                         effect: "The most common cannabis terpene — associated with relaxing, sedating \"couch-lock\" effects.",
                         alsoIn: "Mango, hops, thyme"),
        "limonene": .init(name: "Limonene", aroma: "Bright citrus, lemon",
                          effect: "Associated with elevated mood and stress relief.",
                          alsoIn: "Citrus rind, juniper"),
        "caryophyllene": .init(name: "Caryophyllene", aroma: "Peppery, spicy, woody",
                               effect: "The only terpene that also acts on the body's CB2 receptors; linked to calming, anti-inflammatory effects.",
                               alsoIn: "Black pepper, cloves, cinnamon"),
        "pinene": .init(name: "Pinene", aroma: "Fresh pine, herbal",
                        effect: "Associated with alertness and may offset some THC fogginess.",
                        alsoIn: "Pine needles, rosemary, basil"),
        "linalool": .init(name: "Linalool", aroma: "Floral, lavender",
                          effect: "Associated with calm and relaxation.",
                          alsoIn: "Lavender, mint"),
        "terpinolene": .init(name: "Terpinolene", aroma: "Fruity, floral, herbal",
                             effect: "Often found in uplifting, energetic strains.",
                             alsoIn: "Nutmeg, apples, cumin"),
        "humulene": .init(name: "Humulene", aroma: "Hoppy, earthy, woody",
                          effect: "Associated with appetite suppression and a grounded feel.",
                          alsoIn: "Hops, coriander"),
        "ocimene": .init(name: "Ocimene", aroma: "Sweet, herbal, woody",
                         effect: "Associated with uplifting, decongesting effects.",
                         alsoIn: "Mint, parsley, orchids"),
        "bisabolol": .init(name: "Bisabolol", aroma: "Soft floral, chamomile",
                           effect: "Associated with soothing, skin-calming effects.",
                           alsoIn: "Chamomile"),
    ]

    static func fact(for name: String) -> TerpeneFact? {
        facts[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }
}
