//
//  RootView.swift
//  SESH
//
//  Six-tab bar: Home · Journal · Library · Thoughts · Journey · Profile.
//  Journey doubles as the social hub (Cyphers, Live, Chat).
//

import SwiftUI

enum Tab: Int, CaseIterable {
    // Order defines tab-bar order: Home · Community · Explore · Track · Me
    case home, community, explore, track, me

    var title: String {
        switch self {
        case .home:      return "Home"
        case .community: return "Community"
        case .explore:   return "Explore"
        case .track:     return "Track"
        case .me:        return "Me"
        }
    }
    var symbol: String {
        switch self {
        case .home:      return "house"
        case .community: return "person.2"
        case .explore:   return "leaf"
        case .track:     return "chart.bar"
        case .me:        return "person.crop.circle"
        }
    }
    /// Symbols without a clean ".fill" variant get symbolVariant instead.
    var fillable: Bool { true }
}

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(SocialStore.self) private var social
    @Environment(ThemeManager.self) private var theme
    @State private var selection: Tab = .home
    /// Per-tab reset counter. Re-tapping the active tab bumps its value, which
    /// changes that tab's .id and recreates it — popping navigation and
    /// returning to the tab's default page (items: tap-to-go-home behaviour).
    @State private var resetToken: [Tab: Int] = [:]

    /// Called by the tab bar. Switching tabs preserves each tab's place; tapping
    /// the already-selected tab returns it to its default page.
    private func selectTab(_ tab: Tab) {
        if selection == tab {
            resetToken[tab, default: 0] += 1
        } else {
            selection = tab
        }
    }
    @State private var showLog = false
    @State private var showInbox = false
    @State private var showQuickThought = false
    /// Pre-selected tag for the thought composer (e.g. .rant from High Thoughts).
    @State private var quickThoughtTag: ThoughtTag? = nil
    /// "High Thoughts" action sheet: choose Thought or Rant.
    @State private var showHighThoughtChooser = false
    @State private var showLounge = false
    @State private var showStash = false
    @State private var showStrains = false
    @State private var showStartSesh = false
    @State private var showActivityChooser = false
    @State private var chosenActivity: StartActivity? = nil
    @State private var endSeshFromWidget = false
    /// When a start is requested while a sesh is live, stash the pending activity
    /// and show the "in progress" confirm dialog. Works for widget + in-app.
    @State private var showSessionScreen = false
    /// If set, this activity starts once the current save screen is dismissed.
    @State private var startAfterSave: StartActivity? = nil
    /// Stashed chooser pick, applied after the chooser sheet dismisses.
    @State private var pendingChooserActivity: StartActivity? = nil

    /// Single entry point for starting a sesh (from the chooser OR a widget).
    /// If a sesh is already live, warn first; otherwise start fresh.
    private func requestStart(_ activity: StartActivity) {
        if session.liveSesh != nil {
            // A sesh is already in progress: never start a second one and never
            // offer to discard. Any start attempt routes to the active screen,
            // which is the only place a sesh can be ended.
            showSessionScreen = true
        } else {
            chosenActivity = activity
            showStartSesh = true
        }
    }
    @State private var showCompare = false
    @State private var showAddPurchase = false
    @State private var showFriends = false
    @State private var showBadges = false
    @State private var showAnalytics = false
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
            // Per the session rule, a sesh can only be ended from the active
            // screen — route there instead of an inline end/save.
            if session.liveSesh != nil { showSessionScreen = true }
        case .logSesh:
            selection = .track
        case .quickThought:
            showQuickThought = true
        }
    }

    /// Routes a Home Quick Action to its destination.
    private func routeQuickAction(_ action: HomeQuickAction) {
        switch action {
        case .compareStrains: showCompare = true
        case .addPurchase:    showAddPurchase = true
        case .logSession:     showStartSesh = true
        case .logThought:     showQuickThought = true
        case .friends:        showFriends = true
        case .music:          selection = .home   // music hub lands on Home (step 6)
        case .startCyph:      selection = .community
        case .scanProduct:    showStrains = true  // scan flow not built yet -> strains
        case .viewBadges:     showBadges = true
        case .setStatus:      showActivityChooser = true
        case .analytics:      showAnalytics = true
        case .stash:          showStash = true
        case .lounge:         showLounge = true
        case .strains:        selection = .explore
        }
    }

    var body: some View {
        tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $selection, onSelect: { selectTab($0) })
        }
        .id("\(theme.choice.rawValue)-\(theme.iconStyle.rawValue)")
        .preferredColorScheme(theme.choice.isDark ? .dark : .light)
        .toast($toastMessage)
        .notificationBanner(onTap: { _ in showInbox = true })
        .sheet(isPresented: $showInbox) {
            NavigationStack { NotificationInboxView() }
        }
        .task {
            if AppChangelog.shouldShowWhatsNew { showWhatsNew = true }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView().presentationDetents([.large])
        }
        .sheet(isPresented: $showLog, onDismiss: { onLogDismiss() }) {
            LogSeshView(prefill: logPrefill).environment(session).environment(strains)
                .onAppear { entryCountBefore = session.entries.count }
        }
        .sheet(isPresented: $showQuickThought, onDismiss: {
            onThoughtDismiss(); quickThoughtTag = nil
        }) {
            ComposeThoughtView(initialTag: quickThoughtTag).environment(session)
                .presentationDetents([.medium, .large])
                .onAppear { thoughtCountBefore = session.thoughts.count }
        }
        .confirmationDialog("High Thoughts", isPresented: $showHighThoughtChooser, titleVisibility: .visible) {
            Button("Log a Thought") { quickThoughtTag = nil; showQuickThought = true }
            Button("Start a Rant") { quickThoughtTag = .rant; showQuickThought = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showStash) {
            StashView().environment(session)
        }
        .sheet(isPresented: $showStrains) {
            NavigationStack {
                StrainLibraryView(onLog: { strain in
                    logPrefill = strain
                    showStrains = false
                    showLog = true
                })
            }
            .environment(session).environment(strains)
        }
        .fullScreenCover(isPresented: $showLounge) { LoungeView() }
        .fullScreenCover(isPresented: $showStartSesh, onDismiss: { onStartSeshDismiss() }) {
            StartSessionView()
                .environment(session).environment(strains).environment(social)
                .onAppear { entryCountBefore = session.entries.count }
        }
        .fullScreenCover(isPresented: $showSessionScreen) {
            SessionActiveView(onEnd: {
                // End clears live state; the active screen presents its own summary.
                // Status goes to "vibing", then fades to "away" after a while.
                social.enterVibingThenAway()
            })
            .environment(session).environment(strains).environment(social)
        }
        .sheet(isPresented: $showActivityChooser, onDismiss: { onChooserDismiss() }) {
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
        .sheet(isPresented: $showAddPurchase) {
            AddPurchaseView().environment(session).environment(strains)
        }
        .fullScreenCover(isPresented: $showFriends) {
            FriendsView().environment(social).environment(session)
        }
        .fullScreenCover(isPresented: $showBadges) {
            BadgesView().environment(session)
        }
        .fullScreenCover(isPresented: $showAnalytics) {
            StatsView().environment(session)
        }
    }

    @ViewBuilder private var tabContent: some View {
        // All tabs are kept alive in a ZStack so each remembers its place
        // (scroll + navigation) when you switch away and back. Only the selected
        // tab is visible and interactive. Re-tapping the selected tab bumps its
        // reset token, which recreates that tab's view tree — popping any
        // navigation and returning to the tab's default page.
        ZStack {
            tabView(.home) {
                HomeView(
                    onStartSesh: { activity in requestStart(activity) },
                    onEndSesh: {
                        // Same path the widget uses: end live sesh -> skippable save.
                        endSeshFromWidget = true
                        showStartSesh = true
                    },
                    onHighThought: { showHighThoughtChooser = true },
                    onOpenStash: { showStash = true },
                    onOpenLounge: { showLounge = true },
                    onOpenStrains: { showStrains = true },
                    onMenu: { showActivityChooser = true },
                    onOpenInbox: { showInbox = true },
                    onQuickAction: { routeQuickAction($0) }
                )
            }
            tabView(.community) { JourneyView() }
            tabView(.explore) {
                StrainLibraryView(onLog: { strain in
                    logPrefill = strain
                    showLog = true
                })
            }
            tabView(.track) { JournalView() }
            tabView(.me) { ProfileView() }
        }
    }

    /// Wraps a tab's content: kept alive but only shown/interactive when selected,
    /// and keyed by a per-tab reset token so re-tapping returns it to its default.
    @ViewBuilder private func tabView<Content: View>(_ tab: Tab, @ViewBuilder _ content: () -> Content) -> some View {
        let isActive = selection == tab
        content()
            .id(resetToken[tab, default: 0])
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }

    private func onLogDismiss() {
        if session.entries.count > entryCountBefore {
            toastMessage = "Sesh logged"
            social.setMyActivity(.smoking, detail: session.entries.first?.strain)
        }
    }

    private func onThoughtDismiss() {
        if session.thoughts.count > thoughtCountBefore { toastMessage = "Thought captured" }
    }

    private func onStartSeshDismiss() {
        chosenActivity = nil
        endSeshFromWidget = false
        if let next = startAfterSave {
            startAfterSave = nil
            requestStart(next)
        }
    }

    private func onChooserDismiss() {
        if let act = pendingChooserActivity {
            pendingChooserActivity = nil
            requestStart(act)
        }
    }
}

struct TabBar: View {
    @Binding var selection: Tab
    /// Called when a tab is tapped. Lets RootView handle re-tap (return to
    /// default page) vs. switch (preserve place).
    var onSelect: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    if selection != tab { Haptics.selection() }
                    withAnimation(.easeOut(duration: 0.2)) { onSelect(tab) }
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
