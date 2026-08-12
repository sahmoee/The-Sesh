import SwiftUI
import UIKit
import Combine
import Darwin

extension Notification.Name {
    static let unifiedQAQuickReport = Notification.Name("unifiedQA.quickReport")
}

struct UnifiedQAEvent: Identifiable {
    let id = UUID()
    let date: Date
    let kind: String
    let detail: String
}

@MainActor
final class UnifiedQAAutonomy: ObservableObject {
    static let shared = UnifiedQAAutonomy()

    @Published private(set) var events: [UnifiedQAEvent] = []
    @Published private(set) var memoryMB = 0
    @Published private(set) var longestHitchMS = 0
    @Published private(set) var accessibilityFindings: [String] = []

    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var sampleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard displayLink == nil else { return }
        record("lifecycle", "QA monitoring started")
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        sample()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.record("lifecycle", "App became active") }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.record("lifecycle", "App entered background") }
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.record("memory", "System memory warning") }
            }
        ]
    }

    func record(_ kind: String, _ detail: String) {
        events.insert(UnifiedQAEvent(date: Date(), kind: kind, detail: detail), at: 0)
        if events.count > 250 { events.removeLast(events.count - 250) }
    }

    func runAccessibilityAudit() {
        guard let window = keyWindow else {
            accessibilityFindings = ["No active window was available."]
            return
        }
        var findings: [String] = []
        inspect(window, path: "Window", findings: &findings)
        accessibilityFindings = Array(findings.prefix(100))
        record("audit", findings.isEmpty ? "Accessibility sweep passed" : "Accessibility sweep found \(findings.count) issue(s)")
    }

    var evidence: [String: String] {
        let process = ProcessInfo.processInfo
        let disk = ((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) / 1_048_576
        return [
            "memoryMB": "\(memoryMB)",
            "longestFrameHitchMS": "\(longestHitchMS)",
            "thermalState": thermalName(process.thermalState),
            "lowPowerMode": process.isLowPowerModeEnabled ? "yes" : "no",
            "freeDiskMB": "\(disk)",
            "locale": Locale.current.identifier,
            "contentSize": UIApplication.shared.preferredContentSizeCategory.rawValue
        ]
    }

    @objc private func frame(_ link: CADisplayLink) {
        defer { lastFrame = link.timestamp }
        guard lastFrame > 0 else { return }
        let delay = max(0, Int((link.timestamp - lastFrame - link.duration) * 1000))
        guard delay >= 250, delay < 10_000 else { return }
        longestHitchMS = max(longestHitchMS, delay)
        record("hang", "Main thread frame delayed \(delay) ms")
    }

    private func sample() {
        memoryMB = residentMemoryMB()
        if memoryMB >= 750 { record("memory", "High resident memory: \(memoryMB) MB") }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            record("thermal", "Device thermal pressure is \(thermalName(ProcessInfo.processInfo.thermalState))")
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private func inspect(_ view: UIView, path: String, findings: inout [String]) {
        guard !view.isHidden, view.alpha > 0.01 else { return }
        let name = String(describing: type(of: view))
        let next = path + "/" + name
        if view.isAccessibilityElement {
            let label = view.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if label.isEmpty { findings.append("\(next): interactive element has no accessibility label") }
            if (view is UIControl || view.gestureRecognizers?.isEmpty == false),
               (view.bounds.width < 44 || view.bounds.height < 44) {
                findings.append("\(next): touch target is smaller than 44 points")
            }
        }
        for child in view.subviews { inspect(child, path: next, findings: &findings) }
    }

    private func residentMemoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : 0
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

struct UnifiedQAGestureObserver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.install() }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.install() }
    }

    final class Coordinator: NSObject {
        weak var window: UIWindow?
        func install() {
            guard let target = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
                  window !== target else { return }
            window = target
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            target.addGestureRecognizer(tap)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 1.4
            hold.cancelsTouchesInView = false
            hold.delegate = self
            target.addGestureRecognizer(hold)
        }
        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard UserDefaults.standard.object(forKey: "sesh.qa.touches") as? Bool ?? true else { return }
            let point = gesture.location(in: window)
            Task { @MainActor in UnifiedQAAutonomy.shared.record("touch", "Tap at \(Int(point.x)), \(Int(point.y))") }
        }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let point = gesture.location(in: window)
            Task { @MainActor in
                UnifiedQAAutonomy.shared.record("touch", "Report gesture at \(Int(point.x)), \(Int(point.y))")
                NotificationCenter.default.post(name: .unifiedQAQuickReport, object: nil)
            }
        }
    }
}

extension UnifiedQAGestureObserver.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
