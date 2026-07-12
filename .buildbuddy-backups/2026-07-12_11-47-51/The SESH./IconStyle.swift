//
//  IconStyle.swift
//  The SESH
//
//  Appearance "icon style" — a dimension SEPARATE from the color theme. The color
//  theme (ThemeChoice) controls palette; the icon style controls whether the app
//  draws its actions/avatars with custom illustrations or Apple's SF Symbols.
//
//  Options:
//    - apothecary : the warm vintage illustrated set (roll_up_tile, etc.)
//    - midnight   : the dark neon illustrated set (…_midnight assets) — used when
//                   those assets are present; falls back to apothecary art if a
//                   given midnight asset hasn't been added yet.
//    - sfSymbols  : Apple's built-in symbols — no custom art required, always works.
//
//  A logical icon (e.g. .rollUp) resolves through `IconStyle` to either an Asset
//  Catalog image name or an SF Symbol name, so views ask for the icon by meaning
//  and the style decides how it's drawn.
//

import SwiftUI

/// The set of logical icons the app draws in a style-dependent way.
enum SeshIcon {
    case rollUp        // rolling a joint
    case smoking       // smoking a blunt or joint
    case bongRip       // taking a bong rip
    case highThoughts  // "high thoughts" / brain
    case moon          // status / away avatar
    case leaf          // generic cannabis leaf (feed)
    case blunt         // feed: smoking
    case bong          // feed: bong
    // Expanded icon pack (vintage / midnight / symbols variants supplied as
    // <name>_vintage, <name>_midnight, <name>_symbols assets).
    case compareStrains
    case addPurchase
    case logSession
    case logThought
    case friends
    case music
    case startCyph
    case scanProduct
    case viewBadges
    case setStatus

    /// Icons from the expanded pack resolve to <name>_<style> assets; the
    /// original eight use the legacy _tile / _midnight naming.
    var packBaseName: String? {
        switch self {
        case .compareStrains: return "compare_strains"
        case .addPurchase:    return "add_purchase"
        case .logSession:     return "log_session"
        case .logThought:     return "log_thought"
        case .friends:        return "friends"
        case .music:          return "music"
        case .startCyph:      return "start_cyph"
        case .scanProduct:    return "scan_product"
        case .viewBadges:     return "view_badges"
        case .setStatus:      return "set_status"
        default:              return nil
        }
    }
}

enum IconStyle: String, CaseIterable, Identifiable {
    case apothecary
    case midnight
    case sfSymbols

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apothecary: return "Illustrated · Vintage"
        case .midnight:   return "Illustrated · Midnight"
        case .sfSymbols:  return "Minimal"
        }
    }
    /// A short blurb shown under the name in the icon-style picker.
    var subtitle: String {
        switch self {
        case .apothecary: return "Warm, hand-drawn apothecary art"
        case .midnight:   return "Dark, neon-lit illustrations"
        case .sfSymbols:  return "Clean, simple system glyphs"
        }
    }

    /// True when this style draws with SF Symbols rather than image assets.
    var usesSymbols: Bool { self == .sfSymbols }

    // MARK: Resolution

    /// The Asset Catalog image name for a logical icon in this (illustrated)
    /// style. For .midnight we try a "_midnight" suffixed asset and the caller
    /// falls back to the apothecary name if it's missing.
    func assetName(for icon: SeshIcon) -> String {
        // Expanded pack icons use <name>_vintage / _midnight / _symbols.
        if let pack = icon.packBaseName {
            switch self {
            case .apothecary: return pack + "_vintage"
            case .midnight:   return pack + "_midnight"
            case .sfSymbols:  return pack + "_symbols"
            }
        }
        let base = Self.baseAsset(icon)
        switch self {
        case .midnight: return base + "_midnight"
        default:        return base
        }
    }

    /// The base (apothecary) asset name — also the fallback for midnight.
    static func baseAsset(_ icon: SeshIcon) -> String {
        // Expanded pack icons fall back to their vintage art.
        if let pack = icon.packBaseName { return pack + "_vintage" }
        switch icon {
        case .rollUp:       return "roll_up_tile"
        case .smoking:      return "smoking_tile"
        case .bongRip:      return "bong_rip_tile"
        case .highThoughts: return "high_thoughts_tile"
        case .moon:         return "moon_avatar"
        case .leaf:         return "icon_leaf"
        case .blunt:        return "icon_blunt"
        case .bong:         return "icon_bong"
        default:            return "icon_leaf"   // safe default
        }
    }

    /// The SF Symbol name for a logical icon (used in .sfSymbols style).
    static func symbolName(_ icon: SeshIcon) -> String {
        switch icon {
        case .rollUp:         return "flame.fill"
        case .smoking:        return "smoke.fill"
        case .bongRip:        return "humidity.fill"
        case .highThoughts:   return "brain.head.profile"
        case .moon:           return "moon.fill"
        case .leaf:           return "leaf.fill"
        case .blunt:          return "smoke.fill"
        case .bong:           return "humidity.fill"
        case .compareStrains: return "magnifyingglass"
        case .addPurchase:    return "bag.badge.plus"
        case .logSession:     return "book.closed.fill"
        case .logThought:     return "book.fill"
        case .friends:        return "person.2.fill"
        case .music:          return "music.note"
        case .startCyph:      return "flame.fill"
        case .scanProduct:    return "viewfinder"
        case .viewBadges:     return "rosette"
        case .setStatus:      return "moon.stars.fill"
        }
    }
}

/// A view that renders a logical icon in the user's chosen icon style. Use this
/// instead of a hardcoded Image("…") or Image(systemName:) wherever the art
/// should follow the appearance setting.
struct SeshIconView: View {
    @Environment(ThemeManager.self) private var theme
    let icon: SeshIcon
    var size: CGFloat = 96
    var symbolColor: Color? = nil   // tint for SF Symbol mode (defaults to text)

    var body: some View {
        switch theme.iconStyle {
        case .sfSymbols:
            // Pack icons ship a dedicated "_symbols" illustration; prefer it.
            // The original icons use a true SF Symbol.
            if let pack = icon.packBaseName, UIImage(named: pack + "_symbols") != nil {
                Image(pack + "_symbols").resizable().scaledToFit().frame(height: size)
            } else {
                Image(systemName: IconStyle.symbolName(icon))
                    .font(.system(size: size * 0.7, weight: .regular))
                    .foregroundStyle(symbolColor ?? Palette.text)
                    .frame(height: size)
            }
        case .apothecary, .midnight:
            illustrated
        }
    }

    /// Illustrated path: for midnight, prefer the "_midnight" asset but fall back
    /// to the base art if that asset isn't in the bundle yet, so the app never
    /// shows a blank tile.
    @ViewBuilder private var illustrated: some View {
        let name = theme.iconStyle.assetName(for: icon)
        let resolved = UIImage(named: name) != nil ? name : IconStyle.baseAsset(icon)
        Image(resolved)
            .resizable()
            .scaledToFit()
            .frame(height: size)
    }
}
