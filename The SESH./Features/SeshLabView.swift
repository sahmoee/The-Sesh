//
//  SeshLabView.swift
//  The SESH
//
//  Hub for the Batch-5 feature pack (new-features list): stash forecasts,
//  cost analytics, strain match scores, recap cards, QR friend card, and the
//  rest-day planner. Opened via AppRouter (.seshLab) or the Profile link.
//

import SwiftUI

struct SeshLabView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Sesh Lab")
                    Text("Tools for your personal journal, plus an optional friend card you can share.")
                        .font(.seshScaled(13)).foregroundStyle(Palette.textSecondary)

                    labLink("books.vertical", "Journal Studio",
                            "Notebooks, reflections, comparison, and private exports") { JournalStudioView() }
                    labLink("hourglass.bottomhalf.filled", "Stash Forecast",
                            "When each jar runs low, from your logged use") { StashForecastView() }
                    labLink("dollarsign.arrow.circlepath", "Cost per Sesh",
                            "Spend by session, method, strain, and month") { CostAnalyticsView() }
                    labLink("sparkles", "Strain Match",
                            "Your strains ranked by your own history") { StrainMatchView() }
                    labLink("square.and.arrow.up.on.square", "Recap Cards",
                            "Shareable, privacy-safe weekly & monthly recaps") { RecapCardsView() }
                    labLink("qrcode", "QR Friend Card",
                            "Your friend code as a scannable card") { QRFriendCardView() }
                    labLink("calendar.badge.minus", "Rest Days",
                            "Plan breaks and watch tolerance patterns") { TolerancePlannerView() }
                }
                .padding(16).seshReadableForm()
            }
        }
        .navigationTitle("Sesh Lab")
    }

    private func labLink<Dest: View>(_ symbol: String, _ title: String, _ subtitle: String,
                                     @ViewBuilder dest: @escaping () -> Dest) -> some View {
        NavigationLink {
            dest()
                .environment(session).environment(social)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.seshScaled(17)).foregroundStyle(Palette.greenBright).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.seshScaled(15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.seshScaled(12)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.seshScaled(13)).foregroundStyle(Palette.textTertiary)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
