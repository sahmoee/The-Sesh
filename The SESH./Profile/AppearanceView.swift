//
//  AppearanceView.swift
//  The SESH
//
//  The dedicated Appearance page — the single home for all visual customization:
//  Theme Selection and Icon Style Selection, with room for future options. Both
//  pickers show a short personality subtitle so the choice communicates itself
//  before selection.
//

import SwiftUI

struct AppearanceView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Appearance", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        themeSection
                        Divider().overlay(Palette.stroke)
                        iconStyleSection
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Theme").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                Text("Set the color and mood of the whole app.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ThemeChoice.allCases) { choice in
                    themeCard(choice)
                }
            }
        }
    }

    private func themeCard(_ choice: ThemeChoice) -> some View {
        let selected = theme.choice == choice
        return Button {
            theme.choice = choice; Haptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // mini preview using that theme's literal palette
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(choice.palette.bgTop)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4).fill(choice.palette.card).frame(height: 16)
                            .overlay(
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(choice.palette.text.opacity(0.8)).frame(width: 22, height: 4)
                                    Spacer()
                                }.padding(.horizontal, 4)
                            )
                        HStack(spacing: 4) {
                            Circle().fill(choice.palette.green).frame(width: 11, height: 11)
                            Circle().fill(choice.palette.gold).frame(width: 11, height: 11)
                            Circle().fill(choice.palette.purple).frame(width: 11, height: 11)
                            Circle().fill(choice.palette.moodAngry).frame(width: 11, height: 11)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(selected ? Palette.gold : Palette.stroke, lineWidth: selected ? 2 : 1)
                )
                HStack(spacing: 4) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                    }
                    Text(choice.label).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
                }
                Text(choice.subtitle)
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon style

    private var iconStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Icon Style").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                Text("How actions and avatars are drawn.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            VStack(spacing: 10) {
                ForEach(IconStyle.allCases) { style in
                    iconStyleRow(style)
                }
            }
        }
    }

    private func iconStyleRow(_ style: IconStyle) -> some View {
        let selected = theme.iconStyle == style
        return Button {
            theme.iconStyle = style; Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                iconStylePreview(style)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(style.subtitle).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Palette.greenBright : Palette.textTertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(selected ? Palette.greenBright : Palette.stroke, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// A small three-icon preview of a given icon style.
    @ViewBuilder private func iconStylePreview(_ style: IconStyle) -> some View {
        HStack(spacing: 5) {
            ForEach([SeshIcon.rollUp, .bongRip, .leaf], id: \.self) { icon in
                if style.usesSymbols {
                    Image(systemName: IconStyle.symbolName(icon))
                        .font(.system(size: 16)).foregroundStyle(Palette.greenBright)
                        .frame(width: 26, height: 26)
                } else {
                    let name = style.assetName(for: icon)
                    let resolved = UIImage(named: name) != nil ? name : IconStyle.baseAsset(icon)
                    Image(resolved).resizable().scaledToFit().frame(width: 26, height: 26)
                }
            }
        }
        .frame(width: 100, alignment: .leading)
    }
}
