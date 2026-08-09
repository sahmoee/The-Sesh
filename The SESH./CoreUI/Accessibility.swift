//
//  Accessibility.swift
//  The SESH
//
//  (#App10) Accessibility primitives. The app's typography is fixed-size
//  `.system(size:)` throughout; these helpers are the migration path:
//    - .seshScaled(size:weight:design:) — same look, but scales with the user's
//      Dynamic Type setting (relative to .body), capped at accessibility2 so
//      dense cards degrade gracefully instead of exploding.
//    - .minimumTapTarget() — enforces the 44×44pt HIG minimum.
//    - withMotion { } — wraps animations; becomes a no-op when Reduce Motion
//      is on.
//  New code should use these; existing screens can adopt view-by-view.
//

import SwiftUI

extension View {
    /// 44×44pt minimum touch target (App 10).
    func minimumTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

extension Font {
    /// A system font that participates in Dynamic Type. Drop-in for
    /// `.system(size:weight:design:)`.
    static func seshScaled(_ size: CGFloat, weight: Font.Weight = .regular,
                           design: Font.Design = .default) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size),
                weight: weight, design: design)
    }
}

extension View {
    /// Scales with Dynamic Type but caps at accessibility2 so layouts hold.
    func seshDynamicType() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Run an animation unless the user has Reduce Motion enabled (App 10).
@MainActor
func withMotion<Result>(_ animation: Animation? = .default,
                        _ body: () throws -> Result) rethrows -> Result {
    if UIAccessibility.isReduceMotionEnabled {
        var t = Transaction(); t.disablesAnimations = true
        return try withTransaction(t, body)
    }
    return try withAnimation(animation, body)
}
