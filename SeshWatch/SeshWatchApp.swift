import SwiftUI

@main struct SeshWatchApp: App {
    @StateObject private var store = SeshWatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack { SeshWatchHome().environmentObject(store) }
                .id((store.state.snapshot?.epoch.uuidString ?? "unpaired") + (store.state.snapshot?.enabled == true ? "enabled" : "disabled"))
                .tint(Color(red: 0.48, green: 0.84, blue: 0.62)).preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    if value == .active { store.sync() } else { store.flushDraft() }
                }
        }
        .backgroundTask(.watchConnectivity) { await store.finishBackgroundDelivery() }
    }
}
