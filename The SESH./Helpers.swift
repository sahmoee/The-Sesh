//
//  Helpers.swift
//  HighThoughts
//
//  Small cross-cutting utilities used by the improvements: haptics, consistent
//  formatting, a toast overlay, an empty-state view, and a tiny sparkline.
//

import SwiftUI
import UIKit

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Formatting

enum Fmt {
    // Cached formatters. DateFormatter/NumberFormatter allocation is expensive
    // (hundreds of microseconds each); creating one per call in list rows or
    // exports showed up as avoidable churn. These are created once and reused.
    private static let currencyFull: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2; return f
    }()
    private static let currencyWhole: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0; return f
    }()
    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "LLLL"; return f
    }()

    static func currency(_ value: Double) -> String {
        let whole = value.truncatingRemainder(dividingBy: 1) == 0
        let f = whole ? currencyWhole : currencyFull
        return f.string(from: value as NSNumber) ?? String(format: "$%.2f", value)
    }
    static func currency0(_ value: Double) -> String {
        currencyWhole.string(from: value as NSNumber) ?? String(format: "$%.0f", value)
    }
    static func rating(_ value: Double) -> String { String(format: "%.1f", value) }

    static func mediumDate(_ date: Date) -> String { mediumDateFormatter.string(from: date) }
    static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func monthName(_ date: Date) -> String { monthNameFormatter.string(from: date) }
}

// MARK: - Toast

/// Lightweight transient confirmation. Drive via `.toast($message)`.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var systemImage: String = "checkmark.circle.fill"

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: systemImage).foregroundStyle(Palette.greenBright)
                    Text(message).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(Palette.cardElevated))
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation(.easeOut(duration: 0.25)) { self.message = nil }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>, systemImage: String = "checkmark.circle.fill") -> some View {
        modifier(ToastModifier(message: message, systemImage: systemImage))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Layered, designed illustration instead of a flat icon.
                Circle()
                    .fill(LinearGradient(colors: [Palette.green.opacity(0.18), Palette.green.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 104, height: 104)
                Circle()
                    .stroke(Palette.green.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(Palette.field)
                    .frame(width: 68, height: 68)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Palette.greenBright, Palette.green],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
            }
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            Text(message)
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: { Haptics.tap(); action() }) {
                    Label(actionTitle, systemImage: actionIcon ?? "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.onGreen)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.green))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.top, 60)
    }
}

// MARK: - Sparkline

/// Minimal line chart for a series of ratings (1...10). No GeometryReader —
/// uses the Canvas API which provides its own size.
struct Sparkline: View {
    let values: [Double]
    var lineColor: Color = Palette.greenBright
    var height: CGFloat = 36

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maxV = 10.0, minV = 1.0
            let stepX = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                let v = (values[i] - minV) / (maxV - minV)
                return CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(v) * size.height)
            }
            var path = Path()
            path.move(to: point(0))
            for i in 1..<values.count { path.addLine(to: point(i)) }
            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // end dot
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)),
                         with: .color(lineColor))
        }
        .frame(height: height)
    }
}
