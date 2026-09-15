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
    /// OpenTHC variety ID (universally-unique), for cross-system interop/dedup.
    var openthcID: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, thc, cbd, effects, flavors, terpenes, aka, summary, sources, isCustom, photoName, breeder, lineage, floweringTime, openthcID
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
        openthcID = try? c.decodeIfPresent(String.self, forKey: .openthcID)
    }

    init(id: String, name: String, type: StrainType, thc: Double? = nil, cbd: Double? = nil,
         effects: [StrainTrait] = [], flavors: [StrainTrait] = [], terpenes: [StrainTrait] = [],
         aka: [String] = [], summary: String? = nil, sources: [String] = [], isCustom: Bool = false,
         photoName: String? = nil, breeder: String? = nil, lineage: String? = nil, floweringTime: String? = nil,
         openthcID: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.thc = thc; self.cbd = cbd
        self.effects = effects; self.flavors = flavors; self.terpenes = terpenes
        self.aka = aka; self.summary = summary; self.sources = sources; self.isCustom = isCustom
        self.photoName = photoName; self.breeder = breeder; self.lineage = lineage; self.floweringTime = floweringTime
        self.openthcID = openthcID
    }

    /// All names this strain can be matched against (lowercased).
    var matchKeys: [String] {
        ([name] + aka).map(Self.normalizedSearchText)
    }

    static func normalizedSearchText(_ value: String) -> String { CatalogSearchIndex.normalize(value) }

    /// Factual field coverage, used to favor informative profiles without
    /// inventing ratings or popularity.
    var completenessScore: Int {
        var score = type == .unknown ? 0 : 1
        score += thc == nil ? 0 : 1; score += cbd == nil ? 0 : 1
        score += effects.isEmpty ? 0 : 2; score += flavors.isEmpty ? 0 : 1
        score += terpenes.isEmpty ? 0 : 2; score += breeder == nil ? 0 : 1
        score += lineage == nil ? 0 : 1
        return score
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
/// lookup/search. Custom strains commit to a protected local file before mirroring legacy defaults.
@MainActor
@Observable
final class StrainStore {
    private(set) var customStrains: [StrainProfile] = []
    private(set) var storageError: String?
    private var catalogRevision = 0
    private let customKey = "ht.customStrains.v1"
    @ObservationIgnored private let persistence = ProtectedCollectionStore<StrainProfile>(url: ProtectedCollectionStore<StrainProfile>.applicationURL("custom-strains-v1.json"))
    @ObservationIgnored private var cachedStrains: [StrainProfile]?
    @ObservationIgnored private var searchIndex: CatalogSearchIndex?
    @ObservationIgnored private var byID: [String: StrainProfile] = [:]
    private struct Query: Hashable { let term: String; let type: String?; let detailed: Bool }
    @ObservationIgnored private var searchCache: [Query: [String]] = [:]
    var canEdit: Bool { !persistence.blocked }

    init() { loadCustom() }
    func retryLoading() { loadCustom() }

    private func invalidateCache() {
        cachedStrains = nil; searchIndex = nil; byID = [:]; searchCache = [:]
        catalogRevision += 1
    }

    /// Custom names override the bundled reference. Distinct IDs protect SwiftUI row identity.
    var strains: [StrainProfile] {
        _ = catalogRevision // Cached reads still subscribe to custom catalog changes.
        if let cachedStrains { return cachedStrains }
        var names = Set<String>(), ids = Set<String>()
        let result = (customStrains + BundledStrains.all).filter {
            let key = StrainProfile.normalizedSearchText($0.name)
            guard !names.contains(key), !ids.contains($0.id) else { return false }
            names.insert(key); ids.insert($0.id); return true
        }
        cachedStrains = result
        byID = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        searchIndex = CatalogSearchIndex(result.map { CatalogSearchDocument(id: $0.id, name: $0.name,
            type: $0.type.rawValue, aliases: $0.aka,
            traits: ($0.effects + $0.flavors + $0.terpenes).map(\.name), breeder: $0.breeder ?? "", coverage: $0.completenessScore) })
        return result
    }

    private var index: CatalogSearchIndex { _ = strains; return searchIndex ?? CatalogSearchIndex([]) }

    func strain(named query: String) -> StrainProfile? {
        let index = self.index
        if let id = index.exactID(query) { return byID[id] }
        return index.prefixID(query).flatMap { byID[$0] }
    }
    func suggestions(for query: String, limit: Int = 6) -> [StrainProfile] {
        index.suggestions(query, limit: limit).compactMap { byID[$0] }
    }
    func search(_ query: String, type: StrainType? = nil, detailedOnly: Bool = false) -> [StrainProfile] {
        let index = self.index
        let request = Query(term: CatalogSearchIndex.normalize(query), type: type?.rawValue, detailed: detailedOnly)
        if let cached = searchCache[request] { return cached.compactMap { byID[$0] } }
        let ids = index.search(request.term, type: request.type, detailedOnly: detailedOnly)
        if searchCache.count >= 16 { searchCache.removeAll(keepingCapacity: true) }
        searchCache[request] = ids
        return ids.compactMap { byID[$0] }
    }
    func isUnknown(_ name: String) -> Bool {
        !CatalogSearchIndex.normalize(name).isEmpty && index.exactID(name) == nil
    }
    func sorted() -> [StrainProfile] { index.alphabeticIDs.compactMap { byID[$0] } }
    func filtered(by type: StrainType?) -> [StrainProfile] { sorted().filter { type == nil || $0.type == type } }

    @discardableResult
    func upsertCustom(_ strain: StrainProfile, replacing expected: StrainProfile? = nil, creating: Bool = false) throws -> StrainProfile {
        var value = strain
        value.name = JournalInputPolicy.trimmed(value.name)
        guard !CatalogSearchIndex.normalize(value.name).isEmpty else { throw EditError.message("Enter a strain name.") }
        for number in [value.thc, value.cbd].compactMap({ $0 }) {
            guard CatalogValuePolicy.percentage(number) != nil else { throw EditError.message("THC and CBD must be between 0 and 100 percent.") }
        }
        if let expected {
            guard let current = customStrains.first(where: { $0.id == expected.id }) else { throw EditError.message("This strain was removed while you were editing. Your draft has been kept.") }
            guard current == expected else { throw EditError.message("This strain changed while you were editing. Reopen it before saving over those changes.") }
        }
        if creating { value.id = "custom-" + UUID().uuidString.lowercased() }
        let nameKey = CatalogSearchIndex.normalize(value.name)
        guard !customStrains.contains(where: { $0.id != value.id && CatalogSearchIndex.normalize($0.name) == nameKey }) else {
            throw EditError.message("A custom strain with this name already exists. Edit its existing profile instead.")
        }
        value.isCustom = true
        if value.sources.isEmpty { value.sources = ["My strains"] }
        var candidate = customStrains
        if let i = candidate.firstIndex(where: { $0.id == value.id }) { candidate[i] = value }
        else { candidate.insert(value, at: 0) }
        try commit(candidate)
        return value
    }

    @discardableResult
    func addCustom(name: String, type: StrainType = .hybrid,
                   thc: Double? = nil, cbd: Double? = nil,
                   effects: [String] = [], flavors: [String] = [], summary: String? = nil) throws -> StrainProfile {
        let key = CatalogSearchIndex.normalize(name)
        if let existing = customStrains.first(where: { CatalogSearchIndex.normalize($0.name) == key }) { return existing }
        return try upsertCustom(StrainProfile(id: "", name: name, type: type, thc: thc, cbd: cbd,
            effects: effects.map { StrainTrait(name: $0, intensity: nil) },
            flavors: flavors.map { StrainTrait(name: $0, intensity: nil) }, summary: summary,
            sources: ["My strains"], isCustom: true), creating: true)
    }
    func deleteCustom(_ strain: StrainProfile) throws { try commit(customStrains.filter { $0.id != strain.id }) }
    func isCustom(_ strain: StrainProfile) -> Bool { customStrains.contains { $0.id == strain.id } }
    func clearCustom() throws {
        try persistence.reset()
        UserDefaults.standard.removeObject(forKey: customKey)
        customStrains = []; storageError = nil; invalidateCache()
    }
    private func commit(_ values: [StrainProfile]) throws {
        do {
            let data = try persistence.write(values)
            UserDefaults.standard.set(data, forKey: customKey)
            customStrains = values; storageError = nil; invalidateCache()
        } catch { storageError = error.localizedDescription; throw error }
    }
    private func loadCustom() {
        do {
            var values = try persistence.load(legacy: UserDefaults.standard.data(forKey: customKey))
            var ids = Set<String>(), repaired = false
            for i in values.indices {
                if values[i].id.isEmpty || !ids.insert(values[i].id).inserted {
                    values[i].id = "custom-" + UUID().uuidString.lowercased(); ids.insert(values[i].id); repaired = true
                }
            }
            if repaired { try commit(values) } else { customStrains = values; storageError = nil; invalidateCache() }
        } catch { storageError = "Custom strains could not be read. Original data is preserved. " + error.localizedDescription }
    }
    enum EditError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
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
