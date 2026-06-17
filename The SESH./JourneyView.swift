//
//  JourneyView.swift
//  HighThoughts
//
//  "Your Journey" overview (parchment) + navigation to Badges, Stats,
//  and Strain Insights.
//

import SwiftUI

struct JourneyView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains
    @State private var friendPeek: SeshUser?
    @State private var showStartSesh = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Parchment background for Journey
                Palette.cream.ignoresSafeArea()
                BotanicalOverlayCream().ignoresSafeArea().allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        ZStack {
                            Text("Your Journey")
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(Palette.onCream)
                            HStack {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 18)).foregroundStyle(Palette.onCream)
                                Spacer()
                                NavigationLink {
                                    ProfileSettingsView().environment(session).navigationBarBackButtonHidden(true)
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 18)).foregroundStyle(Palette.onCream)
                                }
                            }
                        }
                        .padding(.top, 8)

                        // Connection status (loading/error state, #22)
                        if social.loading && !social.online {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Connecting…").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                        } else if !social.online {
                            Button { Task { await social.refresh() } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wifi.exclamationmark").font(.system(size: 13))
                                    Text("Offline — showing local data. Tap to retry.").font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                                }
                                .foregroundStyle(Palette.gold)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.gold.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }

                        // ── Social hub ──────────────────────────────
                        Text("Sesh Together")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.onCream)

                        // Active friends presence (cream-styled inline)
                        if !social.activeFriends.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(social.activeFriends) { f in
                                        Button { friendPeek = f } label: {
                                            VStack(spacing: 5) {
                                                PresenceAvatar(user: f, size: 50)
                                                Text(f.displayName).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.onCream).lineLimit(1)
                                                ActivityGlyph(activity: f.activity, size: 13)
                                            }.frame(width: 60)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical, 2)
                            }
                        }

                        VStack(spacing: 12) {
                            Button { showStartSesh = true } label: {
                                if let live = session.liveSesh {
                                    exploreRow("play.circle.fill", "Resume sesh",
                                               "\(live.stage.rawValue)\(live.strainName.isEmpty ? "" : " · \(live.strainName)")")
                                } else {
                                    exploreRow("play.circle.fill", "Start sesh", "Begin a live session")
                                }
                            }.buttonStyle(.plain)
                            NavigationLink { FriendsView().navigationBarBackButtonHidden(true) } label: {
                                exploreRow("person.2.fill", "Friends", "Add friends and see who's around")
                            }.buttonStyle(.plain)
                            NavigationLink { FriendActivityView().navigationBarBackButtonHidden(true) } label: {
                                exploreRow("sparkles", "Activity", "See what your friends are up to")
                            }.buttonStyle(.plain)
                            NavigationLink { CyphersView().navigationBarBackButtonHidden(true) } label: {
                                exploreRow("dot.radiowaves.left.and.right", "Cyphers", "Host or join a shared session")
                            }.buttonStyle(.plain)
                            NavigationLink { LiveChatView().navigationBarBackButtonHidden(true) } label: {
                                exploreRow("bubble.left.and.bubble.right.fill", "Live Chat", "Hop into the live room right now")
                            }.buttonStyle(.plain)
                            NavigationLink { ChatRoomsView().navigationBarBackButtonHidden(true) } label: {
                                exploreRow("bubble.left.and.bubble.right", "Chat Rooms", "Jump into the conversation")
                            }.buttonStyle(.plain)
                        }

                        // Overview
                        Text("Overview")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.onCream)
                            .padding(.top, 4)

                        HStack(spacing: 12) {
                            overviewTile(title: "Current Streak", value: "\(session.currentStreak)",
                                         suffix: "Days", emoji: "flame.fill", emojiColor: Palette.moodAngry)
                            NavigationLink {
                                StatsView().environment(session).navigationBarBackButtonHidden(true)
                            } label: {
                                overviewTile(title: "Sessions Logged", value: "\(session.sessionsLogged)",
                                             suffix: nil, emoji: "doc.text", emojiColor: Palette.green)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 12) {
                            overviewTile(title: "Unique Strains Tried", value: "\(session.uniqueStrains)",
                                         suffix: nil, emoji: "leaf.fill", emojiColor: Palette.green)
                            NavigationLink {
                                StatsView(initialTab: "Spending").environment(session).navigationBarBackButtonHidden(true)
                            } label: {
                                overviewTile(title: "This Month Spent",
                                             value: String(format: "$%.2f", session.thisMonthSpent),
                                             suffix: nil, emoji: "dollarsign.circle", emojiColor: Palette.green)
                            }
                            .buttonStyle(.plain)
                        }

                        // Top stats
                        Text("Top Stats")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.onCream)
                            .padding(.top, 4)

                        VStack(spacing: 0) {
                            topStatRow("trophy", "Highest Rated Strain",
                                       session.highestRatedStrain ?? "—",
                                       trailing: session.highestRating > 0 ? String(format: "%.1f", session.highestRating) : nil,
                                       trailingIsRating: true)
                            divider
                            topStatRow("shield", "Most Relaxing",
                                       session.topStrain(for: .chill) ?? session.topStrain(for: .couchPotato) ?? "—",
                                       trailingIcon: "leaf.fill")
                            divider
                            topStatRow("bolt", "Most Productive",
                                       session.topStrain(for: .productive) ?? "—",
                                       trailingIcon: "bolt.fill")
                            divider
                            topStatRow("bag", "Most Purchased",
                                       session.mostPurchasedStrain ?? "—",
                                       trailingIcon: "cart.fill")
                        }
                        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.creamElevated))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))

                        // Explore links
                        VStack(spacing: 12) {
                            NavigationLink { BadgesView().environment(session).navigationBarBackButtonHidden(true) } label: {
                                exploreRow("rosette", "Badges", "See what you've earned")
                            }.buttonStyle(.plain)
                            NavigationLink { InsightsListView().environment(session).navigationBarBackButtonHidden(true) } label: {
                                exploreRow("sparkles", "Strain Insights", "What each strain does for you")
                            }.buttonStyle(.plain)
                            NavigationLink { StatsView().environment(session).navigationBarBackButtonHidden(true) } label: {
                                exploreRow("chart.bar", "Stats", "Mood, strains & spending")
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
                .refreshable { await social.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $friendPeek) { f in
            FriendSheet(user: f).presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showStartSesh) {
            StartSeshView()
                .environment(session).environment(strains).environment(social)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.creamStroke.opacity(0.7)).frame(height: 1).padding(.leading, 44)
    }

    private func overviewTile(title: String, value: String, suffix: String?, emoji: String, emojiColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Palette.onCreamSoft)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.onCream)
                    if let suffix { Text(suffix).font(.system(size: 12)).foregroundStyle(Palette.onCreamSoft) }
                }
                Spacer()
                Image(systemName: emoji).font(.system(size: 22)).foregroundStyle(emojiColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.creamElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
    }

    private func topStatRow(_ icon: String, _ label: String, _ value: String,
                            trailing: String? = nil, trailingIsRating: Bool = false,
                            trailingIcon: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Palette.green)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.cream))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11)).foregroundStyle(Palette.onCreamSoft)
                Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.onCream)
            }
            Spacer()
            if let trailing {
                HStack(spacing: 3) {
                    if trailingIsRating { Image(systemName: "face.smiling").font(.system(size: 12)).foregroundStyle(Palette.gold) }
                    Text(trailing).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onCream)
                }
            } else if let trailingIcon {
                Image(systemName: trailingIcon).font(.system(size: 15)).foregroundStyle(Palette.green)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func exploreRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Palette.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onCream)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.onCreamSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onCreamSoft)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.creamElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct BotanicalOverlayCream: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "leaf.fill")
                    .resizable().scaledToFit().frame(width: 200)
                    .foregroundStyle(Palette.green.opacity(0.06))
                    .rotationEffect(.degrees(20)).offset(x: 50, y: 30)
            }
        }
    }
}
