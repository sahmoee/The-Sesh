//
//  Theme.swift
//  The SESH
//
//  Switchable design system. Two themes — "Olive" (the original look) and
//  "Navy" (the deep blue-black mockup) — share one token set (ThemePalette).
//  `Palette.x` stays the exact same call site everywhere; it just reads the
//  currently-active theme, so a switch re-tints the whole app instantly.
//

import SwiftUI

// MARK: - Hex helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Theme token set

/// Every color the app uses. Two concrete themes fill these in.
struct ThemePalette {
    var bgTop, bgBottom, heroTop, heroBottom: Color
    var card, cardElevated, field, stroke, strokeSoft: Color
    var cream, creamElevated, creamStroke, onCream, onCreamSoft: Color
    var text, textSecondary, textTertiary: Color
    var green, greenBright, greenDeep, onGreen: Color
    var gold, goldSoft, goldDeep, goldRing: Color
    var purple, purpleStroke: Color
    var ratingPill, tabBar: Color
    var moodAngry, moodMeh, moodNeutral, moodGood, moodGreat: Color
}

extension ThemePalette {
    /// The original desaturated-olive theme.
    static let olive = ThemePalette(
        bgTop: Color(hex: "20271B"), bgBottom: Color(hex: "161B12"),
        heroTop: Color(hex: "232A1E"), heroBottom: Color(hex: "10140D"),
        card: Color(hex: "2A3122"), cardElevated: Color(hex: "323A27"),
        field: Color(hex: "1C2117"), stroke: Color(hex: "3C442F"), strokeSoft: Color(hex: "323A27"),
        cream: Color(hex: "EBE2CE"), creamElevated: Color(hex: "F3ECDC"), creamStroke: Color(hex: "D8CDB4"),
        onCream: Color(hex: "2E3320"), onCreamSoft: Color(hex: "6E6A55"),
        text: Color(hex: "ECE7D8"), textSecondary: Color(hex: "9AA088"), textTertiary: Color(hex: "6E7459"),
        green: Color(hex: "5C6B41"), greenBright: Color(hex: "6E8049"), greenDeep: Color(hex: "47542F"),
        onGreen: Color(hex: "F3ECDC"),
        gold: Color(hex: "C9A24B"), goldSoft: Color(hex: "D8B968"), goldDeep: Color(hex: "8A6E33"), goldRing: Color(hex: "B8924A"),
        purple: Color(hex: "3E3753"), purpleStroke: Color(hex: "554B70"),
        ratingPill: Color(hex: "313A24"), tabBar: Color(hex: "12160E"),
        moodAngry: Color(hex: "C2562F"), moodMeh: Color(hex: "C9A24B"), moodNeutral: Color(hex: "C9A24B"),
        moodGood: Color(hex: "9BAE5C"), moodGreat: Color(hex: "6E8049"))

    /// The deep blue-black mockup theme: navy surfaces, warm gold, soft green pills.
    static let navy = ThemePalette(
        bgTop: Color(hex: "0E1422"), bgBottom: Color(hex: "080C16"),
        heroTop: Color(hex: "121A2C"), heroBottom: Color(hex: "070A12"),
        card: Color(hex: "141C2E"), cardElevated: Color(hex: "1B2438"),
        field: Color(hex: "10182A"), stroke: Color(hex: "263149"), strokeSoft: Color(hex: "1E2740"),
        // "cream" surfaces become deep elevated navy panels in this theme
        cream: Color(hex: "182134"), creamElevated: Color(hex: "1E2840"), creamStroke: Color(hex: "2C3958"),
        onCream: Color(hex: "EAEFF8"), onCreamSoft: Color(hex: "9DA9C2"),
        text: Color(hex: "ECF0F8"), textSecondary: Color(hex: "97A2BC"), textTertiary: Color(hex: "606C86"),
        green: Color(hex: "5E7148"), greenBright: Color(hex: "8BA05C"), greenDeep: Color(hex: "47562F"),
        onGreen: Color(hex: "F4F1E6"),
        gold: Color(hex: "D2A95A"), goldSoft: Color(hex: "E0BC72"), goldDeep: Color(hex: "9A7838"), goldRing: Color(hex: "C49A4E"),
        purple: Color(hex: "2B2A4A"), purpleStroke: Color(hex: "473F6B"),
        ratingPill: Color(hex: "1A2236"), tabBar: Color(hex: "0A0F1A"),
        moodAngry: Color(hex: "D06A3C"), moodMeh: Color(hex: "D2A95A"), moodNeutral: Color(hex: "D2A95A"),
        moodGood: Color(hex: "9BAE5C"), moodGreat: Color(hex: "8BA05C"))

    /// Rastafarian: the classic red / gold / green over a warm near-black base.
    /// Green is the primary action color, gold the accent, red the alert/energy.
    static let rasta = ThemePalette(
        bgTop: Color(hex: "1A1310"), bgBottom: Color(hex: "100B09"),
        heroTop: Color(hex: "1E1611"), heroBottom: Color(hex: "0C0807"),
        card: Color(hex: "241A14"), cardElevated: Color(hex: "2D211A"),
        field: Color(hex: "1A1210"), stroke: Color(hex: "3E2D22"), strokeSoft: Color(hex: "2D211A"),
        // "cream" surfaces become warm dark panels here
        cream: Color(hex: "211912"), creamElevated: Color(hex: "2A1F17"), creamStroke: Color(hex: "402E20"),
        onCream: Color(hex: "F5E9D0"), onCreamSoft: Color(hex: "B59B7C"),
        text: Color(hex: "F6ECD8"), textSecondary: Color(hex: "C0A98C"), textTertiary: Color(hex: "8A7252"),
        // Rasta green
        green: Color(hex: "2E8B2E"), greenBright: Color(hex: "3FB23F"), greenDeep: Color(hex: "1F6B1F"),
        onGreen: Color(hex: "FFF8E8"),
        // Rasta gold
        gold: Color(hex: "F2C53D"), goldSoft: Color(hex: "FAD75F"), goldDeep: Color(hex: "B8901F"), goldRing: Color(hex: "E0B233"),
        // "purple" highlight slot repurposed as the Rasta red
        purple: Color(hex: "5C1A12"), purpleStroke: Color(hex: "8A2B1E"),
        ratingPill: Color(hex: "241A14"), tabBar: Color(hex: "0C0807"),
        moodAngry: Color(hex: "D52B1E"), moodMeh: Color(hex: "F2C53D"), moodNeutral: Color(hex: "F2C53D"),
        moodGood: Color(hex: "3FB23F"), moodGreat: Color(hex: "2E8B2E"))

    /// "Apothecary": the dark vintage-dispensary mockup. Deep near-black olive
    /// base, warm cream type, antique gold, burnt-orange energy, leaf green.
    /// Tuned to match the illustrated tile assets (transparent vintage art).
    static let apothecary = ThemePalette(
        bgTop: Color(hex: "171C14"), bgBottom: Color(hex: "0E120C"),
        heroTop: Color(hex: "1B2117"), heroBottom: Color(hex: "0A0D08"),
        card: Color(hex: "202A1B"), cardElevated: Color(hex: "2A3624"),
        field: Color(hex: "171C14"), stroke: Color(hex: "3A472D"), strokeSoft: Color(hex: "2A3624"),
        // warm dark panels stand in for the "cream" surface slots
        cream: Color(hex: "1E2616"), creamElevated: Color(hex: "27331D"), creamStroke: Color(hex: "3E4E2C"),
        onCream: Color(hex: "F1E4C9"), onCreamSoft: Color(hex: "B6A985"),
        text: Color(hex: "F1E4C9"), textSecondary: Color(hex: "B6A985"), textTertiary: Color(hex: "877A52"),
        green: Color(hex: "5C6B3F"), greenBright: Color(hex: "86A957"), greenDeep: Color(hex: "3A472D"),
        onGreen: Color(hex: "F4F1E6"),
        gold: Color(hex: "B99045"), goldSoft: Color(hex: "D0AE6A"), goldDeep: Color(hex: "5B4827"), goldRing: Color(hex: "C49A4E"),
        purple: Color(hex: "372B42"), purpleStroke: Color(hex: "574868"),
        ratingPill: Color(hex: "202A1B"), tabBar: Color(hex: "0C0F09"),
        moodAngry: Color(hex: "C46A2D"), moodMeh: Color(hex: "B99045"), moodNeutral: Color(hex: "B99045"),
        moodGood: Color(hex: "9BAE5C"), moodGreat: Color(hex: "86A957"))

    /// The "Elevated" moodboard: warm cream canvas, sage & forest greens, a
    /// lavender highlight, golden-amber gold, and a terracotta accent.
    /// Calming. Personal. Elevated. — a light theme.
    static let elevated = ThemePalette(
        // Warm cream backgrounds (the moodboard canvas)
        bgTop: Color(hex: "EDE0CE"), bgBottom: Color(hex: "E4D5BF"),
        heroTop: Color(hex: "3E4A2C"), heroBottom: Color(hex: "2B331D"),
        // Light raised surfaces
        card: Color(hex: "F5EFE2"), cardElevated: Color(hex: "FBF6EC"),
        field: Color(hex: "EAE0CF"), stroke: Color(hex: "D3C4A8"), strokeSoft: Color(hex: "DfD3BC"),
        // "cream" tokens stay light/elevated here
        cream: Color(hex: "F5EFE2"), creamElevated: Color(hex: "FBF6EC"), creamStroke: Color(hex: "D3C4A8"),
        onCream: Color(hex: "2C3320"), onCreamSoft: Color(hex: "6E6A55"),
        // Dark text on the cream canvas
        text: Color(hex: "2A3020"), textSecondary: Color(hex: "5E6450"), textTertiary: Color(hex: "8C8770"),
        // Greens from the swatches (sage / forest / olive)
        green: Color(hex: "5C6B3F"), greenBright: Color(hex: "7C8B52"), greenDeep: Color(hex: "2F3A20"),
        onGreen: Color(hex: "F7F2E7"),
        // Golden-amber + terracotta accents
        gold: Color(hex: "D4A84E"), goldSoft: Color(hex: "E0BC72"), goldDeep: Color(hex: "9A7838"), goldRing: Color(hex: "C49A4E"),
        // Lavender highlight (the purple/lilac swatches)
        purple: Color(hex: "9B86C4"), purpleStroke: Color(hex: "C9B6E0"),
        ratingPill: Color(hex: "E6DAC4"), tabBar: Color(hex: "EADDC9"),
        // Mood scale — terracotta for the low end, ambers and greens up
        moodAngry: Color(hex: "B4502F"), moodMeh: Color(hex: "D4A84E"), moodNeutral: Color(hex: "D4A84E"),
        moodGood: Color(hex: "9BAE5C"), moodGreat: Color(hex: "7C8B52"))
}

// MARK: - Theme selection

enum ThemeChoice: String, CaseIterable, Identifiable {
    case olive, navy, apothecary, elevated, rasta
    var id: String { rawValue }
    var label: String {
        switch self {
        case .olive:      return "Olive"
        case .navy:       return "Navy"
        case .apothecary: return "Apothecary"
        case .elevated:   return "Elevated"
        case .rasta:      return "Rasta"
        }
    }
    var palette: ThemePalette {
        switch self {
        case .olive:      return .olive
        case .navy:       return .navy
        case .apothecary: return .apothecary
        case .elevated:   return .elevated
        case .rasta:      return .rasta
        }
    }
    /// Elevated is a light theme; the others are dark.
    var isDark: Bool { self != .elevated }
}

/// Observable holder for the active theme, persisted across launches.
/// Mutating `choice` also updates the global `ActiveTheme.current` so the
/// static `Palette` façade re-tints the whole app.
@Observable
final class ThemeManager {
    var choice: ThemeChoice {
        didSet {
            ActiveTheme.current = choice.palette
            CloudSync.set(choice.rawValue, forKey: key)
        }
    }
    /// Icon/art style — separate from the color theme. Controls whether actions
    /// and avatars draw as illustrations (vintage/midnight) or SF Symbols.
    var iconStyle: IconStyle {
        didSet { CloudSync.set(iconStyle.rawValue, forKey: iconKey) }
    }
    private let key = "sesh.theme.v1"
    private let iconKey = "sesh.iconStyle.v1"

    init() {
        CloudSync.pullIntoDefaults(keys: ["sesh.theme.v1", "sesh.iconStyle.v1"])
        let saved = UserDefaults.standard.string(forKey: "sesh.theme.v1")
        let initial = ThemeChoice(rawValue: saved ?? "apothecary") ?? .apothecary
        self.choice = initial
        let savedIcon = UserDefaults.standard.string(forKey: "sesh.iconStyle.v1")
        self.iconStyle = IconStyle(rawValue: savedIcon ?? "apothecary") ?? .apothecary
        ActiveTheme.current = initial.palette
        CloudSync.startObserving(keys: ["sesh.theme.v1", "sesh.iconStyle.v1"]) { [weak self] in
            if let saved = UserDefaults.standard.string(forKey: "sesh.theme.v1"),
               let c = ThemeChoice(rawValue: saved), c != self?.choice {
                self?.choice = c
            }
            if let savedIcon = UserDefaults.standard.string(forKey: "sesh.iconStyle.v1"),
               let s = IconStyle(rawValue: savedIcon), s != self?.iconStyle {
                self?.iconStyle = s
            }
        }
    }
}

/// Global active palette, read by the static `Palette` façade. Defaults to
/// apothecary until the ThemeManager initializes (it always does at launch).
enum ActiveTheme {
    static var current: ThemePalette = .apothecary
}

// MARK: - Palette façade (unchanged call sites everywhere)

/// All app colors. Same `Palette.x` API as before, now reading the active theme.
enum Palette {
    static var bgTop: Color        { ActiveTheme.current.bgTop }
    static var bgBottom: Color     { ActiveTheme.current.bgBottom }
    static var heroTop: Color      { ActiveTheme.current.heroTop }
    static var heroBottom: Color   { ActiveTheme.current.heroBottom }

    static var card: Color         { ActiveTheme.current.card }
    static var cardElevated: Color { ActiveTheme.current.cardElevated }
    static var field: Color        { ActiveTheme.current.field }
    static var stroke: Color       { ActiveTheme.current.stroke }
    static var strokeSoft: Color   { ActiveTheme.current.strokeSoft }

    static var cream: Color         { ActiveTheme.current.cream }
    static var creamElevated: Color { ActiveTheme.current.creamElevated }
    static var creamStroke: Color   { ActiveTheme.current.creamStroke }
    static var onCream: Color       { ActiveTheme.current.onCream }
    static var onCreamSoft: Color   { ActiveTheme.current.onCreamSoft }

    static var text: Color          { ActiveTheme.current.text }
    static var textSecondary: Color { ActiveTheme.current.textSecondary }
    static var textTertiary: Color  { ActiveTheme.current.textTertiary }

    static var green: Color       { ActiveTheme.current.green }
    static var greenBright: Color { ActiveTheme.current.greenBright }
    static var greenDeep: Color   { ActiveTheme.current.greenDeep }
    static var onGreen: Color     { ActiveTheme.current.onGreen }

    static var gold: Color     { ActiveTheme.current.gold }
    static var goldSoft: Color { ActiveTheme.current.goldSoft }
    static var goldDeep: Color { ActiveTheme.current.goldDeep }
    static var goldRing: Color { ActiveTheme.current.goldRing }

    static var purple: Color       { ActiveTheme.current.purple }
    static var purpleStroke: Color { ActiveTheme.current.purpleStroke }

    static var ratingPill: Color { ActiveTheme.current.ratingPill }
    static var tabBar: Color     { ActiveTheme.current.tabBar }

    static var moodAngry: Color   { ActiveTheme.current.moodAngry }
    static var moodMeh: Color     { ActiveTheme.current.moodMeh }
    static var moodNeutral: Color { ActiveTheme.current.moodNeutral }
    static var moodGood: Color    { ActiveTheme.current.moodGood }
    static var moodGreat: Color   { ActiveTheme.current.moodGreat }
}

// MARK: - Corner radius tokens

enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let pill: CGFloat = 999
}
