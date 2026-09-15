import SwiftUI

struct SeshWatchSettingsView: View {
    @State private var bridge = SeshPhoneWatchBridge.shared
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("The SESH. on your wrist").font(.title2.bold())
                    Text("Private logs, thoughts, timers, stash and personal goals. Your paired iPhone owns saved records. Apple Watch keeps a limited offline copy and queues changes until iPhone confirms its save.").font(.body)
                    Toggle("Allow paired Apple Watch", isOn: Binding(get: { bridge.enabled }, set: { bridge.setEnabled($0) }))
                    Label(bridge.connected ? "Apple Watch is reachable" : "Apple Watch is not currently reachable", systemImage: bridge.connected ? "checkmark.circle" : "applewatch.slash")
                    if let date = bridge.lastSync { Text("Last watch action: \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote) }
                    Button("Refresh watch copy") { bridge.refresh() }.buttonStyle(.borderedProminent).tint(Palette.green)
                    if let error = bridge.error { Text(error).foregroundStyle(.orange); Button("Retry loading watch settings") { bridge.retry() } }
                    Text("Recent records work offline. Browse-all and catalog search require reachable iPhone. Nothing is posted to Community; watch logs follow your existing iPhone journal/iCloud settings.").font(.footnote)
                    Text("Music accounts, media import, community and full journal editing remain in the iPhone app. Install The SESH. using the Watch app on iPhone. Both apps require version 26 or later of their operating system.").font(.footnote)
                    Text("Deleting the iPhone journal invalidates queued watch actions from that journal. The watch copy clears on its next successful sync; an offline watch cannot be erased remotely until it reconnects.").font(.footnote)
                }.padding().foregroundStyle(Palette.text)
            }
        }.navigationTitle("Apple Watch").navigationBarTitleDisplayMode(.inline)
    }
}
