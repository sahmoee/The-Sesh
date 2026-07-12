//
//  QuickActions.swift
//  The SESH
//
//  The personalizable Quick Actions system shown on the idle Home. Users pick
//  which actions appear, remove them, and reorder them — there's no cap. Each
//  action maps to a logical SeshIcon (so it follows the chosen icon style) and a
//  destination intent that RootView routes.
//
//  Quick Actions (idle) and Session Tools (active) are SEPARATE systems with
//  their own stored lists; this file is the Quick Actions half.
//

import SwiftUI

// MARK: - Action catalog

/// Every action that can be placed on the Home Quick Actions row. Raw values are
/// stable identifiers used for persistence — do not rename them.
enum HomeQuickAction: String, CaseIterable, Identifiable, Codable {
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
    case analytics
    case stash
    case lounge
    case strains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compareStrains: return "Compare Strains"
        case .addPurchase:    return "Add Purchase"
        case .logSession:     return "Log Session"
        case .logThought:     return "Log Thought"
        case .friends:        return "Friends"
        case .music:          return "Music"
        case .startCyph:      return "Start a Cyph"
        case .scanProduct:    return "Scan Product"
        case .viewBadges:     return "View Badges"
        case .setStatus:      return "Set Status"
        case .analytics:      return "Analytics"
        case .stash:          return "Stash"
        case .lounge:         return "Lounge"
        case .strains:        return "Strains"
        }
    }

    /// The logical icon used to render this action (follows the icon style).
    var icon: SeshIcon {
        switch self {
        case .compareStrains: return .compareStrains
        case .addPurchase:    return .addPurchase
        case .logSession:     return .logSession
        case .logThought:     return .logThought
        case .friends:        return .friends
        case .music:          return .music
        case .startCyph:      return .startCyph
        case .scanProduct:    return .scanProduct
        case .viewBadges:     return .viewBadges
        case .setStatus:      return .setStatus
        case .analytics:      return .logSession   // reuse a fitting illustration
        case .stash:          return .leaf
        case .lounge:         return .friends
        case .strains:        return .compareStrains
        }
    }

    /// SF Symbol fallback for contexts that don't use the illustrated packs
    /// (e.g. the editor list rows).
    var symbol: String {
        switch self {
        case .compareStrains: return "rectangle.on.rectangle.angled"
        case .addPurchase:    return "bag.badge.plus"
        case .logSession:     return "book.closed.fill"
        case .logThought:     return "brain.head.profile"
        case .friends:        return "person.2.fill"
        case .music:          return "music.note"
        case .startCyph:      return "flame.fill"
        case .scanProduct:    return "viewfinder"
        case .viewBadges:     return "rosette"
        case .setStatus:      return "moon.stars.fill"
        case .analytics:      return "chart.bar.fill"
        case .stash:          return "shippingbox.fill"
        case .lounge:         return "globe.americas.fill"
        case .strains:        return "leaf.fill"
        }
    }

    /// The default set shown before the user customizes anything.
    static let defaults: [HomeQuickAction] = [.addPurchase, .logSession, .friends, .analytics]
}

// MARK: - Home Quick Actions row

/// Renders the user's chosen Quick Actions as a grid of tiles, plus an Edit
/// affordance. Tapping a tile emits its action to the parent for routing.
struct HomeQuickActionsRow: View {
    @Environment(AppSession.self) private var session
    @Environment(ThemeManager.self) private var theme
    let onAction: (HomeQuickAction) -> Void
    @State private var showEditor = false

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Actions")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                Button { showEditor = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                        Text("Edit").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Palette.greenBright)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(session.quickActions) { action in
                    tile(action)
                }
            }
        }
        .padding(.horizontal, 18)
        .sheet(isPresented: $showEditor) { QuickActionsEditor() }
    }

    private func tile(_ action: HomeQuickAction) -> some View {
        Button { Haptics.tap(); onAction(action) } label: {
            VStack(spacing: 8) {
                // In Minimal (SF Symbols) mode, render the ACTION's own distinct
                // symbol. Routing through the shared illustrated SeshIcon mapping
                // collapses several actions onto the same glyph in Minimal mode
                // (e.g. Analytics→logSession, Stash→leaf, Lounge→friends,
                // Strains→compareStrains), because those SeshIcons each resolve to
                // a single symbol. Each HomeQuickAction already carries a unique
                // `symbol`, so use it directly. Illustrated styles are unaffected.
                if theme.iconStyle.usesSymbols {
                    Image(systemName: action.symbol)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Palette.text)
                        .frame(height: 46)
                } else {
                    SeshIconView(icon: action.icon, size: 46)
                        .frame(height: 46)
                }
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Tools (active Home — separate from Quick Actions)

/// The in-sesh toolkit shown while a sesh is active. This is a SEPARATE system
/// from HomeQuickAction with its own pool and its own stored list, though the two
/// can overlap (e.g. Music appears in both). Each tool routes into the active
/// session screen via a SessionQuickAction.
enum SessionTool: String, CaseIterable, Identifiable, Codable {
    case addSong
    case updateMood
    case logThought
    case invite
    case addProduct
    case changeMethod
    case notes
    case endSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addSong:      return "Add Song"
        case .updateMood:   return "Update Mood"
        case .logThought:   return "Log Thought"
        case .invite:       return "Invite"
        case .addProduct:   return "Add Product"
        case .changeMethod: return "Change Method"
        case .notes:        return "Notes"
        case .endSession:   return "End Session"
        }
    }

    var symbol: String {
        switch self {
        case .addSong:      return "music.note"
        case .updateMood:   return "face.smiling"
        case .logThought:   return "brain.head.profile"
        case .invite:       return "person.crop.circle.badge.plus"
        case .addProduct:   return "bag.badge.plus"
        case .changeMethod: return "arrow.triangle.2.circlepath"
        case .notes:        return "note.text"
        case .endSession:   return "stop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .endSession: return Palette.moodAngry
        case .addSong:    return Palette.greenBright
        case .updateMood: return Palette.gold
        default:          return Palette.purple
        }
    }

    /// How this tool routes into the active session screen.
    var route: SessionQuickAction {
        switch self {
        case .addSong:      return .addSong
        case .updateMood:   return .mood
        case .logThought:   return .logThought
        case .endSession:   return .end
        case .notes:        return .notes
        case .changeMethod: return .changeMethod
        // Not-yet-built in-sesh flows open the active screen, where these
        // controls will live; they don't claim a feature that isn't there.
        case .invite, .addProduct: return .none
        }
    }

    /// Default in-sesh tools before the user customizes.
    static let defaults: [SessionTool] = [.addSong, .updateMood, .logThought, .endSession]
}

// MARK: - Session Tools editor

struct SessionToolsEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var available: [SessionTool] {
        SessionTool.allCases.filter { !session.sessionTools.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.sessionTools.isEmpty {
                        Text("No Session Tools yet — add some below.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(session.sessionTools) { tool in
                        row(tool, inUse: true)
                    }
                    .onMove { from, to in session.moveSessionTool(from: from, to: to) }
                    .onDelete { idx in session.removeSessionTools(at: idx) }
                } header: {
                    Text("Your Session Tools — drag to reorder, swipe to remove")
                }
                Section {
                    if available.isEmpty {
                        Text("Everything's added.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(available) { tool in
                        Button { session.addSessionTool(tool) } label: { row(tool, inUse: false) }
                    }
                } header: {
                    Text("Add more")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Session Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func row(_ tool: SessionTool, inUse: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.symbol).font(.system(size: 16)).foregroundStyle(tool.tint).frame(width: 26)
            Text(tool.title).font(.system(size: 15)).foregroundStyle(Palette.text)
            Spacer()
            if !inUse {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.greenBright)
            }
        }
    }
}

// MARK: - Editor (choose / remove / reorder)

struct QuickActionsEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var available: [HomeQuickAction] {
        HomeQuickAction.allCases.filter { !session.quickActions.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.quickActions.isEmpty {
                        Text("No Quick Actions yet — add some below.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(session.quickActions) { action in
                        row(action, inUse: true)
                    }
                    .onMove { from, to in
                        session.moveQuickAction(from: from, to: to)
                    }
                    .onDelete { idx in
                        session.removeQuickActions(at: idx)
                    }
                } header: {
                    Text("Your Quick Actions — drag to reorder, swipe to remove")
                }

                Section {
                    if available.isEmpty {
                        Text("Everything's added.")
                            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(available) { action in
                        Button { session.addQuickAction(action) } label: {
                            row(action, inUse: false)
                        }
                    }
                } header: {
                    Text("Add more")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func row(_ action: HomeQuickAction, inUse: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 16)).foregroundStyle(Palette.greenBright).frame(width: 26)
            Text(action.title).font(.system(size: 15)).foregroundStyle(Palette.text)
            Spacer()
            if !inUse {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.greenBright)
            }
        }
    }
}
