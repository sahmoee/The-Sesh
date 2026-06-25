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

// Portions of the strain catalog are imported from the Kushy open cannabis
// dataset (https://github.com/kushyapp/cannabis-dataset), which is MIT licensed.
// Only structured factual fields (name, type, effects, flavor, lineage, THC/CBD)
// are used; original prose descriptions are not reproduced. Imported entries are
// attributed via sources: ["Kushy (MIT)"].

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

    private func invalidateCache() { cachedStrains = nil }

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
        // Single pass: bucket into prefix vs. contains matches. Using a Set of ids
        // to dedupe avoids the previous O(n^2) `prefix.contains(s)` array scan
        // (StrainProfile equality compares every field), which ran on each keystroke.
        var prefix: [StrainProfile] = []
        var contains: [StrainProfile] = []
        var prefixIDs = Set<String>()
        for s in all {
            let keys = s.matchKeys
            if keys.contains(where: { $0.hasPrefix(key) }) {
                prefix.append(s)
                prefixIDs.insert(s.id)
            } else if keys.contains(where: { $0.contains(key) }) {
                contains.append(s)
            }
        }
        let merged = prefix + contains.filter { !prefixIDs.contains($0.id) }
        return Array(merged.prefix(limit))
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
    /// Built-in strain catalog, loaded from the bundled `strains.json` rather than
    /// a compiled Swift literal. Decoding ~1,450 entries at first access keeps this
    /// data out of the type-checker entirely (the old literal added many seconds to
    /// every clean build). Loaded once, lazily, then cached for the process lifetime.
    static let all: [StrainProfile] = loadBundled()

    private static func loadBundled() -> [StrainProfile] {
        guard let url = Bundle.main.url(forResource: "strains", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("strains.json missing from app bundle — add it to Copy Bundle Resources")
            return []
        }
        do {
            return try JSONDecoder().decode([StrainProfile].self, from: data)
        } catch {
            assertionFailure("strains.json failed to decode: \(error)")
            return []
        }
    }
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
