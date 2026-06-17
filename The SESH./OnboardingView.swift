//
//  OnboardingView.swift
//  The SESH
//
//  First-launch onboarding. A short paged intro that explains what the app
//  does, then hands off to sign-in. Shown once (tracked in @AppStorage).
//

import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let body: String
}

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var index = 0
    /// What the user says they're here for — used to pick the first tab.
    @AppStorage("sesh.intent") private var intent = ""

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(symbol: "leaf.fill", tint: Palette.green,
                           title: "Welcome to The Sesh",
                           body: "Your cannabis companion — track your sessions, discover strains, and sesh with friends."),
            OnboardingPage(symbol: "book.pages.fill", tint: Palette.gold,
                           title: "Journal your sesh",
                           body: "Log strains, methods, moods, and effects. Snap a photo and capture a thought while you're in it."),
            OnboardingPage(symbol: "magnifyingglass", tint: Palette.greenBright,
                           title: "Know your strains",
                           body: "Explore a library of strains, compare your favorites, and find your vibe by the effects you want."),
            OnboardingPage(symbol: "dot.radiowaves.left.and.right", tint: Palette.green,
                           title: "Sesh together",
                           body: "Host or join a Cypher, drop into Live Chat, and see what your friends are up to in real time."),
        ]
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 20).padding(.top, 12)
                        .accessibilityHint("Skips the introduction")
                }

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                        VStack(spacing: 22) {
                            Spacer()
                            Image(systemName: page.symbol)
                                .font(.system(size: 64))
                                .foregroundStyle(page.tint)
                                .frame(width: 132, height: 132)
                                .background(Circle().fill(page.tint.opacity(0.14)))
                                .accessibilityHidden(true)
                            VStack(spacing: 12) {
                                Text(page.title)
                                    .font(.system(size: 26, weight: .bold, design: .serif))
                                    .foregroundStyle(Palette.text)
                                    .multilineTextAlignment(.center)
                                Text(page.body)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Palette.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            Spacer()
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // On the last page, ask what they're here for (adaptive landing).
                if index == pages.count - 1 {
                    VStack(spacing: 8) {
                        Text("What brings you here?")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 8) {
                            intentChip("Track", "book.pages.fill", "track")
                            intentChip("Discover", "leaf.fill", "discover")
                            intentChip("Connect", "person.2.fill", "connect")
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 4)
                    .transition(.opacity)
                }

                PrimaryButton(title: index == pages.count - 1 ? "Get Started" : "Next",
                              icon: index == pages.count - 1 ? "checkmark" : "arrow.right") {
                    if index < pages.count - 1 {
                        withAnimation { index += 1 }
                    } else {
                        finish()
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
    }

    private func intentChip(_ label: String, _ icon: String, _ value: String) -> some View {
        let on = intent == value
        return Button { intent = on ? "" : value; Haptics.selection() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(on ? Palette.onGreen : Palette.text)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(on ? Palette.green : Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(on ? Color.clear : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)\(on ? ", selected" : "")")
    }

    private func finish() {
        Haptics.success()
        onDone()
    }
}
