import SwiftUI

enum UnifiedQAPasscode {
    static let unlockedUntilKey = "unified.qa.unlockedUntil"
    static let window: TimeInterval = 10 * 60
    static var isUnlocked: Bool { UserDefaults.standard.double(forKey: unlockedUntilKey) > Date().timeIntervalSinceReferenceDate }
    @discardableResult static func unlock(_ value: String) -> Bool {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines) == "6352" else { return false }
        UserDefaults.standard.set(Date().addingTimeInterval(window).timeIntervalSinceReferenceDate, forKey: unlockedUntilKey)
        return true
    }
}

struct UnifiedQAPasscodeGate<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnifiedQAPasscode.unlockedUntilKey) private var unlockedUntil = 0.0
    @State private var code = ""
    @State private var wrong = false
    @State private var shake = false
    @ViewBuilder let content: () -> Content
    private var unlocked: Bool { unlockedUntil > Date().timeIntervalSinceReferenceDate }
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    var body: some View {
        Group {
            if unlocked { content() }
            else {
                VStack(spacing: 0) {
                    Spacer()
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("QA Access").font(.system(size: 22, weight: .semibold)).padding(.top, 18)
                    Text("The Sesh · \(appVersion) (\(buildNumber))")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 8)
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle().fill(index < code.count ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 14, height: 14)
                        }
                    }
                    .padding(.top, 48)
                    .offset(x: shake ? -8 : 0)
                    .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(4) : .default, value: shake)
                    Text("Enter your four-digit access code").font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
                    if wrong { Text("Incorrect code").font(.caption).foregroundStyle(.red).padding(.top, 6) }
                    keypad.padding(.top, 36)
                    Spacer()
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary).padding(.bottom, 32)
                }
                .padding(.horizontal, 32)
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 16) {
            ForEach([[1,2,3], [4,5,6], [7,8,9], [0]], id: \.self) { row in
                HStack(spacing: 24) {
                    if row == [0] { Color.clear.frame(width: 72, height: 72) }
                    ForEach(row, id: \.self) { digit in
                        Button {
                            guard code.count < 4 else { return }
                            code.append(String(digit))
                            if code.count == 4 { attempt() }
                        } label: {
                            Text("\(digit)").font(.system(size: 28, weight: .light)).frame(width: 72, height: 72)
                                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                    }
                    if row == [0] {
                        Button { if !code.isEmpty { code.removeLast() } } label: {
                            Image(systemName: "delete.left").font(.system(size: 20)).frame(width: 72, height: 72)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func attempt() {
        if UnifiedQAPasscode.unlock(code) {
            wrong = false
            unlockedUntil = UserDefaults.standard.double(forKey: UnifiedQAPasscode.unlockedUntilKey)
        } else {
            wrong = true; code = ""; shake = true
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); shake = false }
        }
    }
}
