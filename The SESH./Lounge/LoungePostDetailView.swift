//
//  LoungePostDetailView.swift
//  The SESH
//
//  (SESH-RL-001-R2 §10, Phase 3) The expanded post.
//
//  Shows the full caption, creator, sesh details, comments, reactions,
//  follow/friend controls, report/block, and related strain or song links.
//  Presented as a sheet so the feed underneath keeps its scroll position.
//

import SwiftUI

struct LoungePostDetailView: View {
    @Environment(LoungeFeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Accessed in body so observation tracking picks up transport changes.
    private var previewPlayer: LoungePreviewPlayer { .shared }

    let post: LoungePost
    /// Where "Join" on a live post routes — plumbed from the feed so the sheet
    /// and the feed share one real join action.
    var onJoinLive: (LoungePost) -> Void = { _ in }

    @State private var detail: LoungePostDetail?
    @State private var comments: [LoungeComment] = []
    @State private var draft: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var commentError: String?
    @State private var enlargedMedia: LoungeMedia?
    @State private var showReport = false

    /// Server copy when we have it, otherwise the feed's copy so the sheet has
    /// content immediately instead of flashing a spinner.
    private var current: LoungePost { detail?.post ?? post }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: current.kind.tagTitle, onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        creatorRow
                        if current.kind == .live { liveBlock } else { mediaBlock }
                        bodyText
                        contextChips
                        engagementRow
                        Divider().overlay(Palette.stroke)
                        commentsSection
                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 18)
                }

                composer
            }
        }
        .task { await load() }
        .fullScreenCover(item: $enlargedMedia) { media in
            LoungeMediaViewer(media: media)
        }
        .sheet(isPresented: $showReport) {
            LoungeReportSheet(post: current)
                .environment(store)
                .presentationDetents([.medium])
        }
    }

    // MARK: Loading

    private func load() async {
        let fetched = await store.loadDetail(post.id)
        if let fetched {
            detail = fetched
            comments = fetched.comments
        }
        loading = false
    }

    // MARK: Blocks

    private var creatorRow: some View {
        HStack(spacing: 10) {
            LoungeAvatar(author: current.author, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.author.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(current.author.atHandle) · \(current.agePhrase)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            // No Follow button: the Worker has no follow endpoint yet, and a
            // control that only flips its own label would be a lie.
        }
    }

    @ViewBuilder private var mediaBlock: some View {
        if !current.media.isEmpty {
            VStack(spacing: 8) {
                ForEach(current.media) { media in
                    Button(action: { enlargedMedia = media; Haptics.tap() }) {
                        LoungeMediaThumb(media: media, height: 260)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enlarge media")
                }
            }
        } else if let track = current.track {
            trackBlock(track)
        } else if current.poll != nil {
            LoungePollCard(post: current,
                           onVote: { p, choice in Task { await store.vote(p, choiceID: choice) } })
        }
    }

    /// The detail player shares LoungePreviewPlayer with the feed card, so
    /// state (playing / progress) carries over between the two seamlessly.
    private func trackBlock(_ track: LoungeTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    if let raw = track.artworkURL, let url = URL(string: raw) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                            Rectangle().fill(Palette.field)
                        }
                    } else {
                        Rectangle().fill(Palette.field)
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text).lineLimit(2)
                    Text(track.artist).font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary).lineLimit(1)
                    if track.previewURL == nil {
                        Button(action: { openInMusic(track) }) {
                            Text("Open in Music")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.greenBright)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(track.title) by \(track.artist) in Music")
                    }
                }
                Spacer(minLength: 0)

                if track.previewURL != nil {
                    Button(action: { Haptics.tap(); previewPlayer.toggle(postID: current.id, track: track) }) {
                        Image(systemName: previewPlayer.isPlaying(current.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.onGreen)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Palette.green))
                    }
                    .buttonStyle(.plain)
                    .minimumTapTarget()
                    .accessibilityLabel(previewPlayer.isPlaying(current.id)
                                        ? "Pause preview of \(track.title)"
                                        : "Play preview of \(track.title)")
                }
            }

            if track.previewURL != nil {
                GeometryFreeBar(fraction: previewPlayer.progress(for: current.id))
                    .frame(height: 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
    }

    private func openInMusic(_ track: LoungeTrack) {
        Haptics.tap()
        let term = "\(track.title) \(track.artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://music.apple.com/search?term=\(term)") {
            openURL(url)
        }
    }

    /// §9 — a room that has ended opens a graceful state instead of a dead join.
    @ViewBuilder private var liveBlock: some View {
        if let live = current.live {
            VStack(alignment: .leading, spacing: 10) {
                LoungeLiveCard(post: current, featured: true, onJoin: { joined in
                    dismiss()
                    onJoinLive(joined)
                })
                if !live.isLive {
                    Text("This room has ended. Nearby rooms are still going — check Live Now.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var bodyText: some View {
        if !current.text.isEmpty {
            Text(current.text)
                .font(.system(size: 15, design: current.kind == .highThought ? .serif : .default))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var contextChips: some View {
        let tags = current.vibeTags
        if current.strainName != nil || current.method != nil || current.mood != nil || !tags.isEmpty {
            FlowLayout(spacing: 6) {
                if let strain = current.strainName { LoungeChip(text: strain, icon: "leaf.fill") }
                if let method = current.method { LoungeChip(text: method, icon: "flame.fill") }
                if let mood = current.mood { LoungeChip(text: mood, icon: "sparkles") }
                ForEach(tags, id: \.self) { LoungeChip(text: $0) }
            }
        }
    }

    private var engagementRow: some View {
        HStack(spacing: 18) {
            Button(action: { Task { await store.toggleReaction(current) } }) {
                HStack(spacing: 5) {
                    Image(systemName: current.viewerHasReacted ? "heart.fill" : "heart")
                        .foregroundStyle(current.viewerHasReacted ? Palette.moodAngry : Palette.textSecondary)
                    Text("\(current.reactionCount)")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(current.viewerHasReacted ? "Remove reaction" : "React")

            HStack(spacing: 5) {
                Image(systemName: "bubble.left").foregroundStyle(Palette.textSecondary)
                Text("\(comments.count)").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(comments.count) comments")

            Spacer()

            Button(action: { showReport = true }) {
                Image(systemName: "flag")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Report post")
        }
        .font(.system(size: 15))
    }

    @ViewBuilder private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textTertiary).tracking(0.5)

            if loading {
                ProgressView().tint(Palette.textTertiary).frame(maxWidth: .infinity)
            } else if comments.isEmpty {
                Text("No comments yet. Say something.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 9) {
                        LoungeAvatar(author: comment.author, size: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(comment.author.handle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text("· \(comment.ageText)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Text(comment.text)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let commentError {
                Text(commentError)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.moodAngry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(Palette.field))
                    .overlay(Capsule().stroke(Palette.strokeSoft, lineWidth: 1))

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.onGreen)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canSend ? Palette.green : Palette.field))
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Palette.tabBar)
    }

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        sending = true
        commentError = nil
        Haptics.tap()
        Task {
            if let created = await store.comment(on: current, text: text) {
                comments.append(created)
                draft = ""
            } else {
                commentError = "Couldn't post your comment. Check your connection and try again."
                Haptics.warning()
            }
            sending = false
        }
    }
}

// MARK: - Media viewer

/// Full-screen media with pinch-to-zoom and a clear dismiss target.
struct LoungeMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let media: LoungeMedia

    @State private var scale: CGFloat = 1
    @State private var committed: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: media.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(.white)
                }
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = min(4, max(1, committed * $0)) }
                        .onEnded { _ in committed = scale }
                )
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
            .padding(16)
        }
    }
}
