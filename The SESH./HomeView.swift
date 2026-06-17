//
//  HomeView.swift
//  HighThoughts
//
//  Dark hero ("High Thoughts") over a parchment action card with greeting,
//  Log Your Sesh, Quick Thought, and the most recent session.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains
    let onLog: () -> Void
    let onQuickThought: () -> Void
    var onStartSesh: () -> Void = {}
    var onCompare: () -> Void = {}

    @AppStorage("ht.onboarded.v1") private var onboarded = false
    @State private var friendPeek: SeshUser?
    @State private var showLounge = false
    @State private var showStash = false
    @State private var detailEntry: JournalEntry?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    actionCard
                        .padding(.horizontal, 18)
                        .offset(y: -28)
                        // pull following layout up so the -28 offset doesn't leave a gap
                        .padding(.bottom, -28)

                    // ── Social: presence, broadcast, feed ──
                    VStack(spacing: 18) {
                        PresenceRow(onTapFriend: { friendPeek = $0 })
                        // Big color-coded CURRENT STATUS card when a status/sesh
                        // is live; otherwise the compact vibe-setting strip.
                        if social.me.activity != .idle {
                            CurrentStatusCard()
                        }
                        BroadcastStrip()

                        // Stash — your current supply + purchase log
                        Button { showStash = true; Haptics.tap() } label: {
                            DarkCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox.fill").font(.system(size: 20)).foregroundStyle(Palette.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Your Stash").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                        if session.stashRemaining.isEmpty {
                                            Text("Log what you bought and how much").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                        } else {
                                            let names = session.stashRemaining.prefix(2).map(\.strain).joined(separator: ", ")
                                            Text("\(session.stashRemaining.count) in stock · \(names)").font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }.buttonStyle(.plain)

                        ActivityFeedCard()

                        // Lounge highlights entry
                        Button { showLounge = true; Haptics.tap() } label: {
                            DarkCard {
                                HStack(spacing: 12) {
                                    Text("🌎").font(.system(size: 22))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("The Lounge").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                        Text("Trending strains, discussions & community reviews").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                }
                // clear the floating tab bar so the last card is never covered
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $friendPeek) { f in
            FriendSheet(user: f).presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showLounge) { LoungeView() }
        .sheet(isPresented: $showStash) { StashView().environment(session) }
        .sheet(item: $detailEntry) { e in
            LogSeshView(editing: e).environment(session).environment(strains)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Palette.heroTop, Palette.heroBottom],
                           startPoint: .top, endPoint: .bottom)

            // candle + smoke suggestion
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundStyle(Palette.gold.opacity(0.85))
                .padding(.trailing, 60).padding(.bottom, 70)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .accessibilityLabel("Menu")
                    Spacer()
                    Image(systemName: "bell")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.text)
                        .accessibilityLabel("Notifications")
                }
                .padding(.top, 8)

                Spacer(minLength: 16)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("The")
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text.opacity(0.9))
                    Text("Sesh")
                        .font(.system(size: 60, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .tracking(1)
                }
                Text("Your cannabis companion.\nTrack, sesh & connect.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 10)

                Spacer(minLength: 28)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 320)
        .clipped()
    }

    // MARK: Action card

    private var actionCard: some View {
        CreamCard(padding: 18) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Palette.cream).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Palette.creamStroke, lineWidth: 1))
                        Image(systemName: "leaf.fill").foregroundStyle(Palette.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(greeting), \(session.userName)")
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundStyle(Palette.onCream)
                        Text("Take a breath. You're doing great.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.onCreamSoft)
                    }
                    Spacer()
                }

                Button(action: onStartSesh) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill").font(.system(size: 17, weight: .semibold))
                        Text("Start sesh").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                }
                .buttonStyle(.plain)

                Button(action: onLog) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        Text("Log your sesh").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                secondaryButton("Quick Thought", "square.and.pencil", action: onQuickThought)
                Button(action: onCompare) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1").font(.system(size: 14, weight: .semibold))
                        Text("Compare Strains").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Palette.onCream)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.cream.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if !onboarded {
                    onboardingHint
                }

                if !session.entries.isEmpty {
                    weekStrip
                }

                recentSession
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let e = session.entries.first { detailEntry = e; Haptics.tap() }
                    }
            }
        }
    }

    // MARK: This-week strip + streak ring

    private var weekStrip: some View {
        HStack(spacing: 12) {
            StreakRing(streak: session.currentStreak, goal: session.nextStreakMilestone)
            VStack(spacing: 0) {
                Text("\(session.sessionsThisWeek)")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.onCream)
                Text("this week").font(.system(size: 11)).foregroundStyle(Palette.onCreamSoft)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(Palette.creamStroke).frame(width: 1, height: 32)
            VStack(spacing: 0) {
                Text(session.avgRatingThisWeek > 0 ? Fmt.rating(session.avgRatingThisWeek) : "—")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.onCream)
                Text("avg high").font(.system(size: 11)).foregroundStyle(Palette.onCreamSoft)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(Palette.creamStroke).frame(width: 1, height: 32)
            VStack(spacing: 0) {
                Text(session.spentThisWeek > 0 ? Fmt.currency0(session.spentThisWeek) : "—")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.onCream)
                Text("spent").font(.system(size: 11)).foregroundStyle(Palette.onCreamSoft)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.creamElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
    }

    private var onboardingHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.wave.fill").font(.system(size: 20)).foregroundStyle(Palette.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to The Sesh").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onCream)
                Text("Log a sesh, capture a thought, and explore the Strain Library.")
                    .font(.system(size: 12)).foregroundStyle(Palette.onCreamSoft)
            }
            Spacer(minLength: 4)
            Button { withAnimation { onboarded = true } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.onCreamSoft)
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.creamElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
    }

    private func secondaryButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Palette.onCream)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.creamElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var recentSession: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT SESSION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.onCreamSoft)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.onCreamSoft)
            }
            .padding(.bottom, 10)

            if let e = session.entries.first {
                HStack(spacing: 12) {
                    StoredImage(name: e.photoName, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.strain)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.onCream)
                        Text(relativeDay(e.date) + " · " + timeString(e.date))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.onCreamSoft)
                        Text(e.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.onCream.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling").font(.system(size: 14)).foregroundStyle(Palette.gold)
                        Text(String(format: "%.1f", e.rating))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.onCream)
                    }
                }
            } else {
                Text("No sessions yet — tap Log Your sesh to begin.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.onCreamSoft)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.creamElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.creamStroke, lineWidth: 1))
    }
}

// MARK: - Streak ring

struct StreakRing: View {
    let streak: Int
    let goal: Int
    private var progress: Double { goal > 0 ? min(1, Double(streak) / Double(goal)) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.creamStroke, lineWidth: 5).frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(streak)").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.onCream)
                Text("day").font(.system(size: 9)).foregroundStyle(Palette.onCreamSoft)
            }
        }
        .accessibilityLabel("Streak \(streak) of \(goal) days")
    }
}

// MARK: - Date helpers (shared)

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let f = DateFormatter(); f.dateFormat = "MMM d"
    return f.string(from: date)
}

func timeString(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: date)
}
