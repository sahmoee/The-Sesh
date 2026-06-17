//
//  RootView.swift
//  SESH
//
//  Six-tab bar: Home · Journal · Library · Thoughts · Journey · Profile.
//  Journey doubles as the social hub (Cyphers, Live, Chat).
//

import SwiftUI

enum Tab: Int, CaseIterable {
    // Order defines tab-bar order: Home · Log · Cyphs · Strains · Me
    case home, log, journey, library, profile

    var title: String {
        switch self {
        case .home:     return "Home"
        case .log:      return "Log"
        case .journey:  return "Cyphs"
        case .library:  return "Strains"
        case .profile:  return "Me"
        }
    }
    var symbol: String {
        switch self {
        case .home:     return "house"
        case .log:      return "doc.text"
        case .journey:  return "smoke"
        case .library:  return "leaf"
        case .profile:  return "person.crop.circle"
        }
    }
    /// Symbols without a clean ".fill" variant get symbolVariant instead.
    var fillable: Bool { self != .journey }
}

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(SocialStore.self) private var social
    @Environment(ThemeManager.self) private var theme
    @State private var selection: Tab = {
        switch UserDefaults.standard.string(forKey: "sesh.intent") {
        case "discover": return .library
        case "connect":  return .journey
        default:          return .home
        }
    }()
    @State private var showLog = false
    @State private var showQuickThought = false
    @State private var showStartSesh = false
    @State private var showActivityChooser = false
    @State private var chosenActivity: StartActivity? = nil
    @State private var showCompare = false
    @State private var logPrefill: StrainProfile?
    @State private var toastMessage: String?
    @State private var entryCountBefore = 0
    @State private var thoughtCountBefore = 0
    @State private var showWhatsNew = false

    var body: some View {
        Group {
            switch selection {
            case .home:
                HomeView(
                    onLog: { logPrefill = nil; showLog = true },
                    onQuickThought: { showQuickThought = true },
                    onStartSesh: { showActivityChooser = true },
                    onCompare: { showCompare = true }
                )
            case .log:  JournalView()
            case .library:
                StrainLibraryView(onLog: { strain in
                    logPrefill = strain
                    showLog = true
                })
            case .journey:  JourneyView()
            case .profile:  ProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $selection)
        }
        .id(theme.choice)
        .preferredColorScheme(theme.choice.isDark ? .dark : .light)
        .toast($toastMessage)
        .task {
            if AppChangelog.shouldShowWhatsNew { showWhatsNew = true }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView().presentationDetents([.large])
        }
        .sheet(isPresented: $showLog, onDismiss: {
            if session.entries.count > entryCountBefore {
                toastMessage = "Sesh logged"
                social.setMyActivity(.smoking, detail: session.entries.first?.strain)
            }
        }) {
            LogSeshView(prefill: logPrefill).environment(session).environment(strains)
                .onAppear { entryCountBefore = session.entries.count }
        }
        .sheet(isPresented: $showQuickThought, onDismiss: {
            if session.thoughts.count > thoughtCountBefore { toastMessage = "Thought captured" }
        }) {
            ComposeThoughtView().environment(session).presentationDetents([.medium, .large])
                .onAppear { thoughtCountBefore = session.thoughts.count }
        }
        .fullScreenCover(isPresented: $showStartSesh, onDismiss: { chosenActivity = nil }) {
            StartSeshView(initialActivity: chosenActivity)
                .environment(session).environment(strains).environment(social)
                .onDisappear {
                    if session.entries.count > entryCountBefore { toastMessage = "Sesh saved to Journal" }
                }
                .onAppear { entryCountBefore = session.entries.count }
        }
        .sheet(isPresented: $showActivityChooser, onDismiss: {
            // If the user picked an activity, launch the live sesh now that the
            // chooser has dismissed. (No-op if they cancelled.)
            if chosenActivity != nil { showStartSesh = true }
        }) {
            StartSeshChooser(onPick: { act in
                chosenActivity = act
            })
            .environment(social)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompare) {
            CompareStrainsView().environment(session).environment(strains)
        }
    }
}

struct TabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    if selection != tab { Haptics.selection() }
                    withAnimation(.easeOut(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: iconName(tab))
                            .font(.system(size: 18))
                            .symbolVariant(selection == tab && !tab.fillable ? .fill : .none)
                            .scaleEffect(selection == tab ? 1.12 : 1.0)
                        Text(tab.title).font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Palette.gold : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Palette.tabBar
                .overlay(Rectangle().fill(Palette.stroke).frame(height: 0.5), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func iconName(_ tab: Tab) -> String {
        (selection == tab && tab.fillable) ? "\(tab.symbol).fill" : tab.symbol
    }
}
