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
    @State private var endSeshFromWidget = false
    /// When a start is requested while a sesh is live, stash the pending activity
    /// and show the "in progress" confirm dialog. Works for widget + in-app.
    @State private var pendingStartActivity: StartActivity? = nil
    @State private var showInProgressWarning = false
    /// If set, this activity starts once the current save screen is dismissed.
    @State private var startAfterSave: StartActivity? = nil
    /// Stashed chooser pick, applied after the chooser sheet dismisses.
    @State private var pendingChooserActivity: StartActivity? = nil

    /// Single entry point for starting a sesh (from the chooser OR a widget).
    /// If a sesh is already live, warn first; otherwise start fresh.
    private func requestStart(_ activity: StartActivity) {
        if session.liveSesh != nil {
            pendingStartActivity = activity
            showInProgressWarning = true
        } else {
            chosenActivity = activity
            showStartSesh = true
        }
    }
    private func discardAndStart() {
        guard let act = pendingStartActivity else { return }
        session.clearLiveSesh(); LiveSeshActivityController.end(); social.setMyActivity(.idle)
        pendingStartActivity = nil
        chosenActivity = act
        showStartSesh = true
    }
    private func saveOldThenStart() {
        guard let act = pendingStartActivity else { return }
        // Open the save screen for the in-progress sesh; the queued activity
        // starts after the user finishes/skips saving (see fullScreenCover onDismiss).
        startAfterSave = act
        pendingStartActivity = nil
        endSeshFromWidget = true   // reuse the "end -> save" path
        showStartSesh = true
    }

    /// Message for the in-progress confirm dialog, naming the live sesh.
    private var inProgressMessage: String {
        if let s = session.liveSesh {
            let what = s.strainName.isEmpty ? s.stage.rawValue.lowercased() : s.strainName
            return "You have a \(what) sesh in progress. Save it or discard it before starting a new one?"
        }
        return "You have a sesh in progress. Save it or discard it before starting a new one?"
    }
    @State private var showCompare = false
    @State private var logPrefill: StrainProfile?
    @State private var toastMessage: String?
    @State private var entryCountBefore = 0
    @State private var thoughtCountBefore = 0
    @State private var showWhatsNew = false

    /// Routes a sesh:// deep link (from the Home Screen widget) to the right action.
    private func handleDeepLink(_ url: URL) {
        guard let link = SeshDeepLink(url: url) else { return }
        switch link {
        case .startSesh(let act):
            // Unified path: warns if a sesh is already in progress.
            requestStart(act)
        case .openChooser:
            showActivityChooser = true
        case .endSesh:
            // End the live sesh and open the (skippable) save screen.
            endSeshFromWidget = true
            showStartSesh = true
        case .logSesh:
            selection = .log
        case .quickThought:
            showQuickThought = true
        }
    }

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
        .fullScreenCover(isPresented: $showStartSesh, onDismiss: {
            chosenActivity = nil
            endSeshFromWidget = false
            // If the user chose "Save & start new", launch the queued activity now.
            if let next = startAfterSave {
                startAfterSave = nil
                requestStart(next)
            }
        }) {
            StartSeshView(initialActivity: chosenActivity, endImmediately: endSeshFromWidget)
                .environment(session).environment(strains).environment(social)
                .onDisappear {
                    if session.entries.count > entryCountBefore { toastMessage = "Sesh saved to Journal" }
                }
                .onAppear { entryCountBefore = session.entries.count }
        }
        .confirmationDialog(inProgressMessage, isPresented: $showInProgressWarning, titleVisibility: .visible) {
            Button("Save & start new") { saveOldThenStart() }
            Button("Discard & start new", role: .destructive) { discardAndStart() }
            Button("Cancel", role: .cancel) { pendingStartActivity = nil }
        }
        .sheet(isPresented: $showActivityChooser, onDismiss: {
            if let act = pendingChooserActivity {
                pendingChooserActivity = nil
                requestStart(act)
            }
        }) {
            StartSeshChooser(onPick: { act in
                pendingChooserActivity = act
            })
            .environment(social)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            handleDeepLink(url)
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
