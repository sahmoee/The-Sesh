//
//  LoungeFeedStore.swift
//  The SESH
//
//  (SESH-RL-001-R2 §11) Feed state for The Lounge.
//
//  Ordering guarantees, which the layout engine depends on:
//    • Pages append. Already-visible posts are never reordered or reshaped.
//    • New posts arrive only through an explicit refresh, never by injecting
//      into the middle of the viewport while the user is reading.
//    • A failed page leaves the existing list untouched so retry is free.
//    • Each tab keeps its own cursor, session id and scroll-relevant state, so
//      switching For You -> Following -> back doesn't refetch or lose position.
//

import Foundation
import Observation

@MainActor
@Observable
final class LoungeFeedStore {

    // MARK: Per-tab state

    private struct TabState {
        var posts: [LoungePost] = []
        var bands: [LoungeBand] = []
        var cursor: String?
        var sessionID: String = UUID().uuidString
        var hasMore: Bool = true
        var isLoading: Bool = false
        var isRefreshing: Bool = false
        var loadFailed: Bool = false
        var loadedOnce: Bool = false
    }

    // MARK: Public state

    var tab: LoungeTab = .forYou {
        didSet {
            if tab != oldValue {
                switchTask?.cancel()
                switchTask = Task { await loadIfNeeded() }
            }
        }
    }

    var filter: LoungeFilter = .all {
        didSet {
            if filter != oldValue {
                switchTask?.cancel()
                switchTask = Task { await reload() }
            }
        }
    }

    /// The in-flight load spawned by a tab/filter switch. Held so rapid
    /// switching cancels the previous load instead of stacking them.
    private var switchTask: Task<Void, Never>?

    // MARK: Compose state (Phase 4)

    /// True while a compose submit (upload + create) is in flight.
    var isPosting: Bool = false
    /// True during the media-upload leg specifically, so the compose sheet can
    /// show "Uploading photo…" progress.
    var isUploadingMedia: Bool = false
    /// User-facing message when the last compose attempt failed. Cleared at the
    /// start of each attempt; the sheet shows it inline and keeps the draft.
    var composeError: String?

    /// Just-composed posts, newest first — re-merged into reset loads so an
    /// in-flight refresh can't vanish a post the user just passed to the circle.
    private var recentlyComposed: [LoungePost] = []

    /// Set by the view from the environment. At large dynamic type every post
    /// takes the full row so nothing is truncated (§10 accessibility).
    var accessibilityFullWidth: Bool = false {
        didSet { if accessibilityFullWidth != oldValue { replanAll() } }
    }

    private var states: [LoungeTab: TabState] = [:]

    let api: SeshAPI
    private var identity: SeshIdentity?

    /// Read-only access for extensions in this file.
    var currentIdentity: SeshIdentity? { identity }

    init(api: SeshAPI = SeshAPI()) {
        self.api = api
    }

    func configure(identity: SeshIdentity?) {
        self.identity = identity
    }

    // MARK: Derived accessors for the current tab

    private var state: TabState { states[tab] ?? TabState() }

    var posts: [LoungePost] { state.posts }
    var bands: [LoungeBand] { state.bands }
    var isLoading: Bool { state.isLoading }
    var isRefreshing: Bool { state.isRefreshing }
    var hasMore: Bool { state.hasMore }
    var loadFailed: Bool { state.loadFailed }
    var loadedOnce: Bool { state.loadedOnce }

    var isEmpty: Bool { state.posts.isEmpty }

    /// Live rooms surfaced from the current page, for the Live Now tab.
    var liveRooms: [LoungePost] {
        state.posts.filter { $0.kind == .live }
    }

    // MARK: Loading

    /// First load for a tab, skipped if it already has content.
    func loadIfNeeded() async {
        guard !state.loadedOnce, !state.isLoading else { return }
        await loadPage(reset: true)
    }

    /// Explicit user refresh: new session, fresh first page, replaces the list.
    func refresh() async {
        var s = state
        s.isRefreshing = true
        states[tab] = s
        await loadPage(reset: true)
        var done = state
        done.isRefreshing = false
        states[tab] = done
    }

    /// Filter changed — the server re-queries, so start a clean session.
    func reload() async {
        await loadPage(reset: true)
    }

    /// Next page. Appends; never disturbs what's on screen.
    func loadMore() async {
        guard state.hasMore, !state.isLoading, state.loadedOnce else { return }
        await loadPage(reset: false)
    }

    private func loadPage(reset: Bool) async {
        let activeTab = tab
        var s = states[activeTab] ?? TabState()
        guard !s.isLoading else { return }
        s.isLoading = true
        s.loadFailed = false
        if reset { s.sessionID = UUID().uuidString }
        states[activeTab] = s

        let page = await api.fetchLoungeFeed(
            tab: activeTab,
            filter: filter,
            cursor: reset ? nil : s.cursor,
            sessionID: s.sessionID,
            identity: identity
        )

        var updated = states[activeTab] ?? TabState()
        updated.isLoading = false
        updated.loadedOnce = true

        guard let page else {
            // Offline / failed: keep what we have, order untouched, retry is free.
            updated.loadFailed = true
            states[activeTab] = updated
            return
        }

        let sessionID = page.sessionID.isEmpty ? updated.sessionID : page.sessionID
        updated.sessionID = sessionID

        let incoming = page.posts
            .filter(\.passesClientVisibility)
            .map { LoungeLayoutEngine.hydrate($0, sessionID: sessionID) }

        if reset {
            updated.posts = incoming
            // Protect just-composed posts from a reset whose page was fetched
            // before the create landed (or before the server indexed it).
            let present = Set(incoming.map(\.id))
            let missing = recentlyComposed.filter { post in
                !present.contains(post.id)
                    && post.passesClientVisibility
                    && filter.admits(post.kind)
                    && (activeTab != .live || post.kind == .live)
            }
            if !missing.isEmpty {
                updated.posts.insert(
                    contentsOf: missing.map { LoungeLayoutEngine.hydrate($0, sessionID: sessionID) },
                    at: 0)
            }
        } else {
            // Append, de-duplicating by id so a repeated cursor can't double-post
            // or shuffle anything already rendered.
            var seen = Set(updated.posts.map(\.id))
            for post in incoming where seen.insert(post.id).inserted {
                updated.posts.append(post)
            }
        }

        updated.cursor = page.nextCursor
        updated.hasMore = page.nextCursor != nil
        updated.bands = plan(updated.posts, sessionID: sessionID)
        states[activeTab] = updated
    }

    // MARK: Layout

    private func plan(_ posts: [LoungePost], sessionID: String) -> [LoungeBand] {
        LoungeLayoutEngine.plan(posts: posts,
                                sessionID: sessionID,
                                forceFullWidth: accessibilityFullWidth)
    }

    /// Re-plan every tab in place (e.g. dynamic type changed). Content order is
    /// untouched, so this changes shapes without moving anyone's place.
    private func replanAll() {
        for (key, value) in states {
            var s = value
            s.bands = plan(s.posts, sessionID: s.sessionID)
            states[key] = s
        }
    }

    // MARK: Mutations

    /// Optimistic reaction toggle, reverted if the Worker rejects it.
    func toggleReaction(_ post: LoungePost) async {
        let turningOn = !post.viewerHasReacted
        applyInternal(to: post.id) { p in
            p.viewerHasReacted = turningOn
            p.reactionCount = max(0, p.reactionCount + (turningOn ? 1 : -1))
        }
        let ok = await api.reactLounge(postID: post.id, on: turningOn, identity: identity)
        if !ok {
            applyInternal(to: post.id) { p in
                p.viewerHasReacted = !turningOn
                p.reactionCount = max(0, p.reactionCount + (turningOn ? -1 : 1))
            }
        }
    }

    /// Vote, then take the server's tallies as truth.
    func vote(_ post: LoungePost, choiceID: String) async {
        guard post.poll?.hasVoted == false else { return }
        applyInternal(to: post.id) { p in
            p.poll?.viewerChoiceID = choiceID
            p.poll?.totalVotes += 1
            if let i = p.poll?.choices.firstIndex(where: { $0.id == choiceID }) {
                p.poll?.choices[i].votes += 1
            }
        }
        if let fresh = await api.voteLoungePoll(postID: post.id, choiceID: choiceID, identity: identity) {
            applyInternal(to: post.id) { $0.poll = fresh }
        }
    }

    func report(_ post: LoungePost, reason: LoungeReportReason, detail: String = "") async -> Bool {
        let ok = await api.reportLounge(postID: post.id, reason: reason, detail: detail, identity: identity)
        if ok { hideLocally(post.id) }
        return ok
    }

    func hide(_ post: LoungePost) async {
        hideLocally(post.id)
        _ = await api.hideLounge(postID: post.id, identity: identity)
    }

    /// Drops a post from every tab and re-plans. Removing content *does* change
    /// bands, which is correct — the user asked for it to go away.
    private func hideLocally(_ postID: String) {
        for (key, value) in states {
            var s = value
            let before = s.posts.count
            s.posts.removeAll { $0.id == postID }
            if s.posts.count != before {
                s.bands = plan(s.posts, sessionID: s.sessionID)
            }
            states[key] = s
        }
    }

    /// Mutate one post in place across all tabs, then re-plan only if the change
    /// could affect layout. Reactions and votes never do, so the feed holds still.
    func applyInternal(to postID: String, _ mutate: (inout LoungePost) -> Void) {
        for (key, value) in states {
            var s = value
            guard let index = s.posts.firstIndex(where: { $0.id == postID }) else { continue }
            mutate(&s.posts[index])
            // Rebuild only the affected placements; band structure is unchanged.
            let updated = s.posts[index]
            s.bands = s.bands.map { band in Self.replacing(postID: postID, with: updated, in: band) }
            states[key] = s
        }
    }

    private static func replacing(postID: String, with post: LoungePost, in band: LoungeBand) -> LoungeBand {
        func swap(_ p: LoungePlacement) -> LoungePlacement {
            p.post.id == postID ? LoungePlacement(post: post, template: p.template) : p
        }
        switch band {
        case .full(let p):
            return .full(swap(p))
        case .wideNarrow(let a, let b):
            return .wideNarrow(swap(a), swap(b))
        case .narrowWide(let a, let b):
            return .narrowWide(swap(a), swap(b))
        case .pairedShort(let a, let b):
            return .pairedShort(swap(a), swap(b))
        case .singleBubble(let p, let side, let fraction):
            return .singleBubble(swap(p), side: side, widthFraction: fraction)
        }
    }
}

// MARK: - Composing (Phase 4)

extension LoungeFeedStore {

    /// Prepend a freshly created post to the current tab WITHOUT reshuffling
    /// anything already on screen (§11: new posts appear at top; existing
    /// placements never move).
    ///
    /// Why not just re-plan [new] + existing? LoungeLayoutEngine is
    /// deterministic per sessionID:postID, but its band plan is *sequential*:
    /// pairing depends on each post's neighbor and on the running
    /// full-width-reset counter. Prepending a post shifts every adjacency, so a
    /// full re-plan could re-pair (reshape) posts the user is looking at.
    /// Instead the new post is planned alone — which yields exactly one band
    /// (full, or a single bubble for concise text) — and that band is prepended
    /// to the existing plan, leaving every current placement untouched.
    func insertLocal(_ post: LoungePost) {
        guard post.passesClientVisibility else { return }

        // Remember it briefly so a reset load that was already in flight when
        // this insert happened can't wholesale-replace it away (the fetched
        // page predates the create). Re-merged in loadPage's reset branch.
        recentlyComposed.removeAll { $0.id == post.id }
        recentlyComposed.insert(post, at: 0)
        if recentlyComposed.count > Self.recentlyComposedCap {
            recentlyComposed.removeLast(recentlyComposed.count - Self.recentlyComposedCap)
        }

        // A fresh post belongs at the top of For You AND Following (it's the
        // author's own); it belongs in Live Now only when it's a live post.
        for target in LoungeTab.allCases {
            if target == .live && post.kind != .live { continue }
            insert(post, intoTab: target)
        }
    }

    /// How many just-composed posts are protected from reset races.
    private static let recentlyComposedCap = 10

    private func insert(_ post: LoungePost, intoTab target: LoungeTab) {
        var s = states[target] ?? TabState()
        guard !s.posts.contains(where: { $0.id == post.id }) else { return }
        // Respect the store-wide content filter — feeds only ever hold posts
        // the current filter admits (the server applies it too). A post the
        // filter rejects surfaces once the filter changes/reloads.
        guard filter.admits(post.kind) else { return }

        let hydrated = LoungeLayoutEngine.hydrate(post, sessionID: s.sessionID)
        let leading = LoungeLayoutEngine.plan(posts: [hydrated],
                                             sessionID: s.sessionID,
                                             forceFullWidth: accessibilityFullWidth)
        s.posts.insert(hydrated, at: 0)
        s.bands = leading + s.bands
        s.loadedOnce = true
        states[target] = s
    }

    /// Full compose orchestration: upload the photo first (if any), then
    /// create the post, then insert it locally at the top of the feed.
    /// Returns nil on failure and sets `composeError` with a user-facing
    /// message; the compose sheet keeps the draft either way.
    @discardableResult
    func createPost(kind: LoungePostKind,
                    text: String,
                    imageJPEG: Data? = nil,
                    imageAspectRatio: Double = 1,
                    imageAltText: String? = nil,
                    track: LoungeTrack? = nil,
                    poll: LoungePollContent? = nil,
                    strainName: String? = nil,
                    method: String? = nil,
                    mood: String? = nil,
                    vibeTags: [String] = [],
                    visibility: LoungeVisibility = .publicFeed,
                    idempotencyKey: String = UUID().uuidString) async -> LoungePost? {
        guard !isPosting else { return nil }
        isPosting = true
        composeError = nil
        defer { isPosting = false }

        // 1. Media first, so the create body can reference the final URL.
        var media: [SeshAPI.LoungeCreateBody.Media] = []
        if let imageJPEG {
            isUploadingMedia = true
            let url = await api.uploadLoungeMedia(imageJPEG, identity: currentIdentity)
            isUploadingMedia = false
            guard let url else {
                composeError = "Couldn't upload your photo. Check your connection and try again."
                return nil
            }
            media.append(.init(url: url, aspectRatio: imageAspectRatio, altText: imageAltText))
        }

        // 2. Create.
        let body = SeshAPI.LoungeCreateBody(
            idempotencyKey: idempotencyKey,
            kind: kind.rawValue,
            text: text,
            media: media,
            track: track.map {
                .init(title: $0.title, artist: $0.artist, artworkURL: $0.artworkURL,
                      previewURL: $0.previewURL, durationSeconds: $0.durationSeconds,
                      vibeTags: $0.vibeTags)
            },
            poll: poll.map {
                .init(question: $0.question,
                      choices: $0.choices.map { .init(id: $0.id, label: $0.label) })
            },
            strainName: strainName,
            method: method,
            mood: mood,
            vibeTags: vibeTags,
            visibility: visibility.rawValue)

        guard let created = await api.createLoungePost(body, identity: currentIdentity) else {
            composeError = "Couldn't pass that to the circle. Your draft is safe — try again."
            return nil
        }

        // 3. Show it at the top immediately.
        insertLocal(created)
        return created
    }
}

// MARK: - Expanded post (Phase 3)

extension LoungeFeedStore {

    /// Full post + comments for the detail sheet.
    func loadDetail(_ postID: String) async -> LoungePostDetail? {
        await api.fetchLoungePost(id: postID, identity: identityForDetail)
    }

    /// Post a comment and optimistically bump the feed's comment count.
    func comment(on post: LoungePost, text: String) async -> LoungeComment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = await api.commentLounge(postID: post.id, text: trimmed, identity: identityForDetail)
        if created != nil {
            applyPublic(to: post.id) { $0.commentCount += 1 }
        }
        return created
    }

    /// Bridges the private stored identity for the extension above.
    private var identityForDetail: SeshIdentity? { currentIdentity }

    func applyPublic(to postID: String, _ mutate: (inout LoungePost) -> Void) {
        applyInternal(to: postID, mutate)
    }
}
