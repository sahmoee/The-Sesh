//
//  AppRouter.swift
//  The SESH
//
//  (#14) Navigation coordinator. RootView previously juggled ~12 independent
//  sheet/cover booleans that could collide; the simple destinations now live
//  in ONE typed route per presentation style. Deep views can trigger
//  navigation through the environment instead of threading closures.
//
//  The sesh lifecycle presentations (start, active screen, chooser, log,
//  quick thought) keep their dedicated state in RootView because their
//  onDismiss chains encode real sequencing logic — collapsing those into an
//  enum would hide the flow, not simplify it.
//

import SwiftUI
import Observation

/// Sheet-style destinations (medium/large cards).
enum SheetRoute: String, Identifiable {
    case inbox, stash, strains, whatsNew, compare, addPurchase, seshLab
    var id: String { rawValue }
}

/// Full-screen destinations.
enum CoverRoute: String, Identifiable {
    case lounge, friends, badges, analytics
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppRouter {
    var sheet: SheetRoute?
    var cover: CoverRoute?

    func present(_ route: SheetRoute) { sheet = route }
    func present(_ route: CoverRoute) { cover = route }
    func dismiss() { sheet = nil; cover = nil }
}
