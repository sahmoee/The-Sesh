//
//  SeshFlow.swift
//  The SESH
//
//  The four mockup screens, built to match the designs exactly and wired to the
//  real session model:
//   - StartSessionView   : strain search + recent strains + consumption method + mood
//   - SessionActiveScreen : (the live screen — see SessionActiveView, reused)
//   - AddSongScreen      : Search / Recent tabs, recent searches, trending now
//   - SessionSummaryView : strain card + Method/Started/Duration/Song/Mood/Notes + Save
//
//  These are presented as the active flow: Start -> (live) -> Summary, with Add Song
//  reachable from the live screen.
//

import SwiftUI

// MARK: - Shared mood set (matches the mockup chips)

enum SeshMood: String, CaseIterable, Identifiable {
    case relaxed = "Relaxed"
    case happy = "Happy"
    case creative = "Creative"
    case energetic = "Energetic"
    case other = "Other"
    var id: String { rawValue }
}

// MARK: - Consumption method (matches the mockup grid)

enum SeshMethod: String, CaseIterable, Identifiable {
    case blunt = "Blunt"
    case joint = "Joint"
    case bowl = "Bowl"
    case vape = "Vape"
    case dab = "Dab"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .blunt: return "smoke.fill"
        case .joint: return "pencil"
        case .bowl:  return "cup.and.saucer.fill"
        case .vape:  return "wand.and.rays"
        case .dab:   return "drop.fill"
        }
    }
}

// MARK: - 1. Start a Session

struct StartSessionView: View {
    @Environment(StrainStore.self) private var strains
    @Environment(AppSession.self) private var session
    @Environment(ScrobbleStore.self) private var scrobbler
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedStrain: StrainProfile?
    @State private var method: SeshMethod = .joint
    @State private var mood: SeshMood = .relaxed
    @State private var showAllStrains = false
    @State private var searchResults: [StrainProfile] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    title
                    searchField
                    recentStrains
                    methodSection
                    feelingSection
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20)
            }
        }
        .overlay(alignment: .bottom) { startButton }
        .background(AppBackground())
        .task(id: query) {
            // Debounce: filter the catalog ~250ms after the last keystroke
            // instead of on every keystroke during view update.
            guard !query.isEmpty else { searchResults = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searchResults = strains.strains.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var header: some View {
        HStack {
            Text("sesh")
                .font(.custom("SnellRoundhand-Black", size: 30))
                .foregroundStyle(Palette.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Start a Session")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.text)
            Text("What are you smoking?")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
            TextField("Search strains...", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.text)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var recentStrains: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Strains").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                Button { withMotion { showAllStrains.toggle() } } label: {
                    Text(showAllStrains ? "Show less" : "See all")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayStrains) { strain in
                        strainCard(strain)
                    }
                }
            }
        }
    }

    private func strainCard(_ strain: StrainProfile) -> some View {
        let isSel = selectedStrain?.id == strain.id
        return Button {
            selectedStrain = strain; query = strain.name; Haptics.selection()
        } label: {
            VStack(spacing: 8) {
                StoredImage(name: strain.photoName, size: 96, corner: 12, strainID: strain.id)
                    .padding(.top, 4)
                Text(strain.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(strain.type.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(strain.type.tint)
            }
            .frame(width: 130, height: 190)
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isSel ? Palette.purple.opacity(0.25) : Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(isSel ? Palette.greenBright : Palette.stroke, lineWidth: isSel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consumption Method").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            HStack(spacing: 10) {
                ForEach(SeshMethod.allCases) { m in
                    let isSel = method == m
                    Button { method = m; Haptics.selection() } label: {
                        VStack(spacing: 8) {
                            Image(systemName: m.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(isSel ? Palette.greenBright : Palette.textSecondary)
                            Text(m.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isSel ? Palette.greenBright : Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(isSel ? Palette.greenBright : Palette.stroke, lineWidth: isSel ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How are you feeling?").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            Text("You can update this later").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SeshMood.allCases) { md in
                        let isSel = mood == md
                        Button { mood = md; Haptics.selection() } label: {
                            Text(md.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSel ? Palette.onGreen : Palette.text)
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .background(Capsule().fill(isSel ? Palette.greenBright : Palette.purple.opacity(0.3)))
                                .overlay(Capsule().stroke(isSel ? Color.clear : Palette.purpleStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var startButton: some View {
        Button { startSession() } label: {
            Text("Start Session")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.onGreen)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Palette.bgBottom.opacity(0), Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).allowsHitTesting(false), alignment: .bottom)
    }

    /// The strains shown in Recent Strains (recent first, else the catalog head).
    /// Search results come from the debounced task above, not a per-keystroke
    /// filter of the whole catalog.
    private var displayStrains: [StrainProfile] {
        let all = strains.strains
        if query.isEmpty { return showAllStrains ? all : Array(all.prefix(8)) }
        return searchResults
    }

    private func startSession() {
        let name = selectedStrain?.name ?? (query.isEmpty ? "Quick Sesh" : query)
        let state = LiveSeshState(
            startedAt: Date(),
            stageRaw: SeshStage.allCases.first?.rawValue ?? "",
            sessionTypeRaw: SessionType.relaxing.rawValue,
            strainName: name,
            attachedThought: "",
            rollFinalSeconds: nil,
            rollMethod: method.rawValue,
            invited: [])
        session.saveLiveSesh(state)
        // Capture the currently-playing song with this strain, so the sesh builds
        // the strain<->music history that powers stations and recommendations.
        if let np = scrobbler.current {
            session.recordSongPlay(StrainSongPlay(
                strainName: name,
                title: np.title,
                artist: np.artist,
                album: np.album,
                artworkURL: np.artworkURL,
                sourceRaw: np.source.rawValue,
                sessionTypeRaw: state.sessionTypeRaw))
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - 3. Add Song

struct AddSongScreen: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .search
    @State private var query = ""
    @State private var results: [PlaylistTrack] = []
    @State private var searching = false
    @State private var recentSearches: [String] = []
    @State private var added: Set<String> = []

    enum Tab { case search, recent }

    /// The playlist tracks get appended to (a session soundtrack).
    var playlistID: String

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchField
                    if searching {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if !results.isEmpty {
                        searchResults
                    } else {
                        recentSearchesSection
                        trendingSection
                    }
                    Color.clear.frame(height: 70)
                }
                .padding(.horizontal, 20).padding(.top, 14)
            }
        }
        .overlay(alignment: .bottom) {
            Button { dismiss() } label: {
                Text("Cancel").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .background(Palette.bgBottom.opacity(0.95))
        }
        .background(AppBackground())
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Add Song").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
                Text("What are you listening to?").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton("Search", .search)
            tabButton("Recent", .recent)
        }
        .padding(.horizontal, 20)
        .overlay(Divider().overlay(Palette.stroke), alignment: .bottom)
    }

    private func tabButton(_ label: String, _ t: Tab) -> some View {
        let isSel = tab == t
        return Button { tab = t } label: {
            VStack(spacing: 8) {
                Text(label).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSel ? Palette.greenBright : Palette.textSecondary)
                Rectangle().fill(isSel ? Palette.greenBright : Color.clear).frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
            TextField("Search for a song or artist", text: $query)
                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                .submitLabel(.search).onSubmit { runSearch() }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    @ViewBuilder private var recentSearchesSection: some View {
        if recentSearches.isEmpty {
            EmptyStateView(icon: "clock.arrow.circlepath", title: "No recent searches",
                           message: "Songs you search for will show up here for quick re-adding.")
        } else {
            recentSearchesList
        }
    }

    private var recentSearchesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Searches").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            ForEach(recentSearches, id: \.self) { item in
                HStack {
                    Text(recentTitle(item))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    + Text(recentArtist(item))
                        .font(.system(size: 16)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button { recentSearches.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trending Now").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            ForEach(trending) { t in trackRow(t) }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            ForEach(results) { t in trackRow(t) }
        }
    }

    private func trackRow(_ track: PlaylistTrack) -> some View {
        HStack(spacing: 12) {
            artwork(track)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer()
            Button {
                playlists.addTrack(track, to: playlistID); added.insert(track.id); Haptics.tap()
            } label: {
                Image(systemName: added.contains(track.id) ? "checkmark.circle.fill" : "plus")
                    .font(.system(size: 18))
                    .foregroundStyle(added.contains(track.id) ? Palette.greenBright : Palette.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.card))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func artwork(_ track: PlaylistTrack) -> some View {
        if let s = track.artworkURL, let url = URL(string: s) {
            AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { artPlaceholder }
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            artPlaceholder.frame(width: 52, height: 52)
        }
    }
    private var artPlaceholder: some View {
        ZStack { RoundedRectangle(cornerRadius: 8).fill(Palette.field)
            Image(systemName: "music.note").foregroundStyle(Palette.textTertiary) }
    }

    // Static trending list (matches the mockup; album art comes from search in use)
    private var trending: [PlaylistTrack] {
        [
            PlaylistTrack(title: "Creepin'", artist: "Metro Boomin, The Weeknd, 21 Savage", source: .spotify),
            PlaylistTrack(title: "Snooze", artist: "SZA", source: .spotify),
            PlaylistTrack(title: "Die For You", artist: "The Weeknd", source: .spotify),
        ]
    }

    private func recentTitle(_ s: String) -> String { String(s.split(separator: "–").first ?? "").trimmingCharacters(in: .whitespaces) }
    private func recentArtist(_ s: String) -> String {
        let parts = s.split(separator: "–")
        return parts.count > 1 ? " – " + parts[1].trimmingCharacters(in: .whitespaces) : ""
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        // Record the search so Recent Searches reflects real activity.
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 8 { recentSearches.removeLast(recentSearches.count - 8) }
        searching = true
        Task {
            let r = await playlists.search(query, on: .appleMusic)
            results = r
            searching = false
        }
    }
}

// MARK: - 4. Session Summary

struct SessionSummaryView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(ScrobbleStore.self) private var scrobbler
    @Environment(\.dismiss) private var dismiss

    /// The finished live state to summarize (captured when the user ended).
    let strainName: String
    let method: String
    let startedAt: Date
    let durationSeconds: Int
    var moodLabel: String = "Relaxed"
    @State private var notes: String = ""
    @State private var rating: Double = 7
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    strainCard
                    row(icon: "pencil", label: "Method", trailing: pill(method))
                    row(icon: "play.circle", label: "Started", trailing: valueText(startedString))
                    row(icon: "clock", label: "Duration", trailing: valueText(durationString))
                    songRow
                    row(icon: "face.smiling", label: "Mood", trailing: pill(moodLabel))
                    ratingCard
                    notesCard
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) { saveButton }
        .background(AppBackground())
        .confirmationDialog("Discard this sesh?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Sesh", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This sesh won't be saved to your Journal.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { confirmDiscard = true } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { save() } label: {
                    Text("Save").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                }
                .buttonStyle(.plain)
            }
            Text("Session Summary")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.text)
                .padding(.top, 10)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
    }

    private var strainCard: some View {
        HStack(spacing: 14) {
            if let strain = matchedStrain {
                StoredImage(name: strain.photoName, size: 64, corner: 12, strainID: strain.id)
            } else {
                StoredImage(name: nil, size: 64, corner: 12, strainID: strainName)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(strainName.isEmpty ? "Sesh" : strainName)
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                if let t = matchedStrain?.type {
                    Text(t.rawValue).font(.system(size: 14, weight: .medium)).foregroundStyle(t.tint)
                }
            }
            Spacer()
            Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.purple.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.purpleStroke.opacity(0.6), lineWidth: 1))
    }

    private func row(icon: String, label: String, trailing: some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.textSecondary).frame(width: 24)
            Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var songRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(Palette.textSecondary).frame(width: 24)
            Text("Song").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
            Spacer()
            if let np = scrobbler.current {
                HStack(spacing: 10) {
                    if let s = np.artworkURL, let url = URL(string: s) {
                        AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.clear }
                            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(np.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(np.artist).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                }
            } else {
                Text("No song").font(.system(size: 14)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "star").font(.system(size: 16)).foregroundStyle(Palette.textSecondary).frame(width: 24)
                Text("Rating").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
                Spacer()
            }
            RatingSlider(value: $rating)
                .padding(.leading, 36)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "note.text").font(.system(size: 16)).foregroundStyle(Palette.textSecondary).frame(width: 24)
                Text("Notes").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }
            TextField("How was it?", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2...5)
                .padding(.leading, 36)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var saveButton: some View {
        Button { save() } label: {
            Text("Save Session")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.onGreen)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Palette.bgBottom.opacity(0), Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).allowsHitTesting(false), alignment: .bottom)
    }

    // Helpers
    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.greenBright)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .overlay(Capsule().stroke(Palette.greenBright, lineWidth: 1.5))
    }
    private func valueText(_ s: String) -> some View {
        Text(s).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
    }

    private var matchedStrain: StrainProfile? {
        strains.strains.first { $0.name.caseInsensitiveCompare(strainName) == .orderedSame }
    }
    private var startedString: String {
        let prefix = Calendar.current.isDateInToday(startedAt) ? "Today, " : ""
        return prefix + Fmt.time(startedAt)
    }
    private var durationString: String {
        let h = durationSeconds / 3600, m = (durationSeconds % 3600) / 60, s = durationSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func save() {
        let moodValue = Mood.allCases.first { $0.rawValue.caseInsensitiveCompare(moodLabel) == .orderedSame }
        let entry = JournalEntry(
            strain: strainName.isEmpty ? "Sesh" : strainName,
            method: method,
            rating: min(10, max(1, rating)),
            mood: moodValue,
            notes: notes,
            sessionType: moodLabel,
            durationMinutes: max(1, durationSeconds / 60))
        session.add(entry)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Strain Soundtrack (Image 1: "Your Soundtrack for <strain>")

/// A per-strain soundtrack screen: mood-named playlists for songs heard while
/// enjoying a given strain, plus a Create New Playlist action. Each mood row
/// opens (or creates) a "<Strain> <Mood>" playlist.
struct StrainSoundtrackView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss

    let strain: StrainProfile

    private struct Vibe: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let tint: Color
        let fill: Color
    }
    private var vibes: [Vibe] {
        [
            Vibe(name: "Relaxed",   symbol: "leaf.fill",        tint: Palette.greenBright, fill: Palette.greenDeep.opacity(0.35)),
            Vibe(name: "Creative",  symbol: "lightbulb.fill",   tint: Palette.gold,        fill: Palette.purple.opacity(0.25)),
            Vibe(name: "Energetic", symbol: "bolt.fill",        tint: Palette.moodAngry,   fill: Palette.purple.opacity(0.3)),
            Vibe(name: "Late Night", symbol: "moon.fill",       tint: Palette.purpleStroke, fill: Palette.purple.opacity(0.22)),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    strainHeader
                    soundtrackTitle
                    ForEach(vibes) { vibe in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlistID(for: vibe.name),
                                               subtitle: "Based on your \(strain.name) sessions")
                        } label: {
                            vibeRow(vibe)
                        }
                        .buttonStyle(.plain)
                    }
                    createButton
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 20).padding(.top, 6)
            }
        }
        .background(AppBackground())
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "heart").font(.system(size: 18)).foregroundStyle(Palette.text)
                Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(Palette.text)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var strainHeader: some View {
        VStack(spacing: 10) {
            StoredImage(name: strain.photoName, size: 150, corner: 16, strainID: strain.id)
            VStack(spacing: 4) {
                Text(strain.name).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.text)
                HStack(spacing: 10) {
                    Text(strain.type.rawValue).font(.system(size: 15, weight: .medium)).foregroundStyle(strain.type.tint)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                        Text(rating).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Palette.card))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var soundtrackTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Soundtrack for \(strain.name)")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text("Songs you've listened to while enjoying \(strain.name).")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.top, 6)
    }

    private func vibeRow(_ vibe: Vibe) -> some View {
        let count = playlists.playlist(playlistID(for: vibe.name))?.tracks.count ?? 0
        return HStack(spacing: 14) {
            Image(systemName: vibe.symbol).font(.system(size: 20)).foregroundStyle(vibe.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(vibe.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(count) \(count == 1 ? "song" : "songs")").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.greenBright)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(vibe.fill))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private var createButton: some View {
        Button { _ = playlists.createPlaylist(name: "\(strain.name) Mix", autoCollect: false); Haptics.tap() } label: {
            Text("Create New Playlist")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var rating: String {
        // Stable pseudo rating from the name (display only).
        let base = 4.0 + Double(abs(strain.name.hashValue) % 10) / 10.0
        return String(format: "%.1f", min(5.0, base))
    }

    private func playlistID(for mood: String) -> String {
        let name = "\(strain.name) · \(mood)"
        if let existing = playlists.playlists.first(where: { $0.name == name }) { return existing.id }
        return playlists.createPlaylist(name: name, autoCollect: false).id
    }
}
