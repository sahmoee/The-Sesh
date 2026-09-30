import XCTest
import SwiftUI
import SowensKit
import SowensTestSupport
@testable import The_SESH_

@MainActor
final class SharedPresentationTests: XCTestCase {
    func testProductionSurface() throws {
        try assertSurfaceSnapshots(of: Fixture(), named: "surface")
    }

    private struct Fixture: View {
        @Environment(\.colorScheme) private var colorScheme
        var dark: Bool { colorScheme == .dark }
        var body: some View {
            DarkCard { SowensStatusView("No journal entries", detail: "Your saved entries appear here.", symbol: "book.closed") }
                .foregroundStyle(dark ? Color.white : Color.black)
                .background(dark ? Color(white: 0.075) : Color.white)
        }
    }
}
