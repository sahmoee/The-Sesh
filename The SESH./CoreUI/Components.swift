//
//  Components.swift
//  HighThoughts
//
//  Shared building blocks rebuilt to match the mockup: dark/cream cards,
//  fields with camera buttons, the rating slider, filter pills, bud thumbnail,
//  emoji mood scale, and the flow layout for tags.
//

import SwiftUI

// MARK: - App background

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .overlay(
                // Real vintage leaf texture, very faint, sitting behind all content.
                Image("leaf_texture")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.06)
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            )
            .overlay(BotanicalOverlay().ignoresSafeArea().allowsHitTesting(false))
    }
}

/// Faint leaf silhouettes in the corners for atmosphere.
struct BotanicalOverlay: View {
    var body: some View {
        ZStack {
            HStack {
                Spacer()
                Image(systemName: "leaf.fill")
                    .resizable().scaledToFit()
                    .frame(width: 220)
                    .foregroundStyle(Palette.greenBright.opacity(0.05))
                    .rotationEffect(.degrees(25))
                    .offset(x: 70, y: 120)
            }
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "leaf.fill")
                        .resizable().scaledToFit()
                        .frame(width: 180)
                        .foregroundStyle(Palette.greenBright.opacity(0.05))
                        .rotationEffect(.degrees(-160))
                        .offset(x: -50, y: 40)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Cards

struct DarkCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = Radius.lg
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Screen header (back / title / trailing)

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var showLeaf: Bool = false
    @ViewBuilder var trailing: Trailing

    init(title: String,
         onBack: (() -> Void)? = nil,
         showLeaf: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.showLeaf = showLeaf
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            if showLeaf {
                VStack(spacing: 2) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.green)
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)
                }
            } else {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
            }
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                trailing
            }
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil, showLeaf: Bool = false) {
        self.init(title: title, onBack: onBack, showLeaf: showLeaf) { EmptyView() }
    }
}

// MARK: - Field label

struct FieldLabel: View {
    let text: String
    var onCream: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(onCream ? Palette.onCreamSoft : Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Input fields

struct InputField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var showsCamera: Bool = false
    var onCamera: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 10) {
                TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary))
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                if showsCamera {
                    Button { onCamera?() } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NotesField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 90
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
    }
}

// MARK: - Rating slider (Slight ... High)

struct RatingSlider: View {
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(value))")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            Slider(value: $value, in: 1...10, step: 1)
                .tint(Palette.greenBright)
                .accessibilityLabel("Rating")
                .accessibilityValue("\(Int(value)) out of 10")
            HStack {
                Text("Slight").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("High").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Choice chip (icon + label, outlined)

/// A selectable emoji + label chip. Consolidates the hand-rolled chip pattern
/// (Session Tags, Effects, Champions, Smoke Again, broadcast vibes) into one
/// component so they look and behave identically and restyle in one place (#4).
/// Renders an activity's glyph: the custom illustrated icon when one exists
/// (smoking / bong / rolling), otherwise the activity emoji. One source of truth
/// so every surface shows the same thing.
struct ActivityGlyph: View {
    @Environment(ThemeManager.self) private var theme
    let activity: SeshActivity
    var size: CGFloat = 18

    var body: some View {
        switch theme.iconStyle {
        case .sfSymbols:
            // Symbols mode: use an SF Symbol for the illustrated activities,
            // emoji for the rest.
            if let symbol = symbolName {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(Palette.greenBright)
                    .frame(width: size, height: size)
            } else {
                Text(activity.emoji).font(.system(size: size * 0.9))
            }
        case .apothecary, .midnight:
            if let name = activity.iconName {
                // In Midnight, prefer a _midnight feed asset when it exists, else
                // fall back to the base illustrated icon so nothing goes blank.
                let midnightName = name + "_midnight"
                let resolved = (theme.iconStyle == .midnight && UIImage(named: midnightName) != nil)
                    ? midnightName : name
                Image(resolved).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Text(activity.emoji).font(.system(size: size * 0.9))
            }
        }
    }

    /// SF Symbol equivalents for the illustrated activities (Symbols icon style).
    private var symbolName: String? {
        switch activity {
        case .smoking:     return "smoke.fill"
        case .hittingBong: return "humidity.fill"
        case .rollingUp:   return "flame.fill"
        default:           return nil
        }
    }
}

struct EmojiChip: View {
    let emoji: String
    let title: String
    let isSelected: Bool
    var fillWidth: Bool = true
    /// Optional custom icon; when set, shown instead of the emoji.
    var iconName: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconName {
                    Image(iconName).resizable().scaledToFit().frame(width: 17, height: 17)
                } else {
                    Text(emoji).font(.system(size: 15))
                }
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if fillWidth { Spacer(minLength: 0) }
            }
            .foregroundStyle(isSelected ? Palette.onGreen : Palette.text)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .padding(.horizontal, fillWidth ? 12 : 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? Palette.green : Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isSelected ? Color.clear : Palette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OptionChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Palette.onGreen : tint)
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isSelected ? Palette.green : Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? Color.clear : Palette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter pill row

struct FilterPills: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let active = selection == item
                    Button { selection = item } label: {
                        Text(item)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(active ? Palette.onCream : Palette.textSecondary)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(active ? Palette.cream : Palette.field))
                            .overlay(Capsule().stroke(active ? Color.clear : Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }
}

/// Underlined tab style (Journal "All / Favorites / ...").
struct UnderlineTabs: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(items, id: \.self) { item in
                    let active = selection == item
                    Button { selection = item } label: {
                        VStack(spacing: 6) {
                            Text(item)
                                .font(.system(size: 14, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Palette.text : Palette.textSecondary)
                            Rectangle()
                                .fill(active ? Palette.gold : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? Palette.onGreen : Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.green.opacity(isEnabled ? 1 : 0.4)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bud thumbnail (placeholder art)

struct BudThumb: View {
    var size: CGFloat = 64
    var seed: Int = 0
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(
                LinearGradient(colors: [Palette.greenDeep, Palette.green.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Palette.greenBright.opacity(0.55))
                    .rotationEffect(.degrees(Double((seed % 60 &* 47) % 60 - 30)))
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Rating badge pill

struct RatingBadge: View {
    let value: Double
    var body: some View {
        Text(String(format: "%.1f", value))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.gold)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Palette.ratingPill))
    }
}

// MARK: - Small category tag

struct CategoryTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(Palette.stroke, lineWidth: 0.5))
    }
}

// MARK: - Emoji mood scale (Rant before/after)

struct MoodScale: View {
    @Binding var selection: Int   // 0...4
    private let symbols = [
        "cloud.bolt.fill", "cloud.rain.fill", "cloud.fill",
        "cloud.sun.fill", "sun.max.fill"
    ]
    private let labels = ["Angry", "Meh", "Neutral", "Good", "Great"]
    private let tints = [
        Palette.moodAngry, Palette.moodMeh, Palette.moodNeutral,
        Palette.moodGood, Palette.moodGreat
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Button { selection = i } label: {
                    Image(systemName: symbols[i])
                        .font(.system(size: 22))
                        .foregroundStyle(tints[i])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(selection == i ? Palette.field : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(selection == i ? tints[i].opacity(0.6) : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(labels[i])
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Flow layout (wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Memoized subview sizes so each pass measures every subview once.
    func makeCache(subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
    func updateCache(_ cache: inout [CGSize], subviews: Subviews) {
        cache = subviews.map { $0.sizeThatFits(.unspecified) }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in cache {
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for (v, s) in zip(subviews, cache) {
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Progress bar

/// A simple progress bar that doesn't use GeometryReader (per architecture
/// rules). Used by the Strains intelligence grid and the Lounge's player and
/// poll cards. Previously lived in Social/LoungeView.swift, which is retired.
struct GeometryFreeBar: View {
    let fraction: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.field).frame(height: 8)
            Capsule().fill(Palette.green).frame(height: 8)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: max(0, min(1, fraction)), anchor: .leading)
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(max(0, min(1, fraction)) * 100)) percent")
    }
}
