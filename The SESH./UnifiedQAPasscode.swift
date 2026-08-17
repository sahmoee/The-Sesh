import SwiftUI

enum UnifiedQAPasscode {
    static let unlockedUntilKey = "unified.qa.unlockedUntil"
    static let window: TimeInterval = 10 * 60
    static var isUnlocked: Bool { UserDefaults.standard.double(forKey: unlockedUntilKey) > Date().timeIntervalSinceReferenceDate }
    @discardableResult static func unlock(_ value: String) -> Bool {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Joo") == .orderedSame else { return false }
        UserDefaults.standard.set(Date().addingTimeInterval(window).timeIntervalSinceReferenceDate, forKey: unlockedUntilKey)
        return true
    }
}

struct UnifiedQAPasscodeGate<Content: View>: View {
    @AppStorage(UnifiedQAPasscode.unlockedUntilKey) private var unlockedUntil = 0.0
    @State private var code = ""
    @State private var wrong = false
    @ViewBuilder let content: () -> Content
    private var unlocked: Bool { unlockedUntil > Date().timeIntervalSinceReferenceDate }
    var body: some View {
        Group {
            if unlocked { content() }
            else { NavigationStack { VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill").font(.largeTitle)
                Text("QA Access").font(.title2.bold())
                SecureField("Passcode", text: $code).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                if wrong { Text("Incorrect passcode").foregroundStyle(.red).font(.caption) }
                Button("Unlock") { wrong = !UnifiedQAPasscode.unlock(code); code = ""; unlockedUntil = UserDefaults.standard.double(forKey: UnifiedQAPasscode.unlockedUntilKey) }.buttonStyle(.borderedProminent)
            }.padding(24).navigationTitle("Quality Assurance") } }
        }
    }
}
