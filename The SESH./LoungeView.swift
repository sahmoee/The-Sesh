//
//  LoungeView.swift
//  The SESH
//
//  The Lounge — the public community area (not friend-focused). Discussions,
//  strain rooms, polls, trending, and community reviews. Seeded locally for now
//  behind the same pattern as the rest of the social layer; a real backend can
//  populate these later.
//

import SwiftUI

// MARK: - Models (lightweight, local)

struct LoungeDiscussion: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var author: String
    var replies: Int
    var category: String
    var ago: String
}

struct LoungePoll: Identifiable, Hashable {
    let id = UUID()
    var question: String
    var options: [LoungePollOption]
    var votes: Int
}
struct LoungePollOption: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var share: Double   // 0–1
}

struct CommunityReview: Identifiable, Hashable {
    let id = UUID()
    var strain: String
    var author: String
    var rating: Double
    var text: String
    var ago: String
}

// MARK: - Lounge

struct LoungeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var section = "Trending"

    private let sections = ["Trending", "Discussions", "Reviews"]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                FilterPills(items: sections, selection: $section)
                    .padding(.horizontal, 18).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch section {
                        case "Trending":     trending
                        case "Discussions":  discussions
                        default:             reviews
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18).padding(.top, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text("🌎 Lounge").font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                Text("What the community's talking about").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
    }

    // MARK: Sections

    private var trending: some View {
        VStack(alignment: .leading, spacing: 12) {
            trendCard("Most Discussed Strain", "Blue Dream", "324 posts this week", "flame.fill", Palette.moodAngry)
            trendCard("Most Compared Strain", "Gelato", "On 1.2k compare lists", "rectangle.split.3x1", Palette.gold)
            trendCard("Most Wishlisted", "Permanent Marker", "+890 this week", "bookmark.fill", Palette.green)
            trendCard("Popular Review", "Wedding Cake", "“Best night-time strain, period.”", "star.fill", Palette.gold)
        }
    }

    private func trendCard(_ label: String, _ value: String, _ detail: String, _ icon: String, _ tint: Color) -> some View {
        DarkCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var discussions: some View {
        VStack(spacing: 12) {
            ForEach(seedDiscussions) { d in
                DarkCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(d.category).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.onGreen)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Palette.green))
                            Spacer()
                            Text(d.ago).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                        Text(d.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        HStack(spacing: 10) {
                            Text(d.author).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                            Label("\(d.replies)", systemImage: "bubble.right").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var reviews: some View {
        VStack(spacing: 12) {
            ForEach(seedReviews) { r in
                DarkCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(r.strain, systemImage: "leaf.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.gold)
                                Text(String(format: "%.1f", r.rating)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                            }
                        }
                        Text(r.text).font(.system(size: 13)).foregroundStyle(Palette.text.opacity(0.9))
                        HStack {
                            Text(r.author).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(r.ago).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Seed

    private var seedDiscussions: [LoungeDiscussion] {
        [
            .init(title: "Best strain for a creative flow state?", author: "@greenthumb", replies: 42, category: "Question", ago: "2h"),
            .init(title: "Underrated indicas that deserve more love", author: "@nightowl", replies: 28, category: "Discussion", ago: "5h"),
            .init(title: "How do you organize your stash?", author: "@organized", replies: 17, category: "Advice", ago: "1d"),
            .init(title: "First time trying live rosin — wow", author: "@dabbin", replies: 63, category: "Experience", ago: "1d"),
        ]
    }

    private var seedPolls: [LoungePoll] {
        [
            .init(question: "Best wake & bake strain?", options: [
                .init(label: "Green Crack", share: 0.44),
                .init(label: "Durban Poison", share: 0.31),
                .init(label: "Blue Dream", share: 0.25),
            ], votes: 1284),
            .init(question: "Most overrated strain?", options: [
                .init(label: "Runtz", share: 0.38),
                .init(label: "Gelato", share: 0.34),
                .init(label: "OG Kush", share: 0.28),
            ], votes: 902),
        ]
    }

    private var seedReviews: [CommunityReview] {
        [
            .init(strain: "Wedding Cake", author: "@couchlock", rating: 9.1, text: "Best night-time strain, period. Melts stress instantly.", ago: "3h"),
            .init(strain: "Blue Dream", author: "@daydreamer", rating: 8.4, text: "Perfect daytime balance — creative but not racy.", ago: "8h"),
            .init(strain: "Gelato", author: "@dessert", rating: 8.8, text: "Smooth, sweet, euphoric. Lives up to the hype.", ago: "1d"),
        ]
    }
}

/// A simple progress bar that doesn't use GeometryReader (per architecture rules).
struct GeometryFreeBar: View {
    let fraction: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.field).frame(height: 8)
            Capsule().fill(Palette.green).frame(height: 8)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: max(0, min(1, fraction)), anchor: .leading)
        }
    }
}
