//
//  LoungePostCards.swift
//  The SESH
//
//  (SESH-RL-001-R2 §8) One card per post type.
//
//  Every card, however irregular its silhouette, is wrapped in a rectangular
//  accessible hit region with a real label (§10). Decorative bits — bubble
//  tails, pins, glow — are marked decorative so VoiceOver skips them.
//

import SwiftUI

// MARK: - Entry point

/// Renders a placement using the template the layout engine chose.
struct LoungePostCard: View {
    let placement: LoungePlacement
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onVote: (LoungePost, String) -> Void = { _, _ in }
    var onMenu: (LoungePost) -> Void = { _ in }
    var onJoinLive: (LoungePost) -> Void = { _ in }

    private var post: LoungePost { placement.post }

    var body: some View {
        content
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        switch placement.template {
        case .bubbleNarrow, .bubbleMedium, .bubbleFull:
            LoungeThoughtCard(post: post, onOpen: onOpen, onReact: onReact, onMenu: onMenu)
        case .textCardWide, .textCardFull:
            LoungeTextCard(post: post, onOpen: onOpen, onReact: onReact, onMenu: onMenu)
        case .mediaWide, .mediaFull:
            LoungeMediaCard(post: post, full: placement.template == .mediaFull,
                            onOpen: onOpen, onReact: onReact, onMenu: onMenu)
        case .playerMedium, .playerFull:
            LoungePlayerCard(post: post, onOpen: onOpen, onReact: onReact, onMenu: onMenu)
        case .pollMedium, .pollFull:
            LoungePollCard(post: post, onOpen: onOpen, onReact: onReact,
                           onVote: onVote, onMenu: onMenu)
        case .liveFeature, .liveMedium:
            LoungeLiveCard(post: post, featured: placement.template == .liveFeature,
                           onOpen: onOpen, onJoin: onJoinLive)
        case .smallCard:
            LoungeCheckInCard(post: post, onOpen: onOpen, onReact: onReact)
        }
    }

    private var accessibilityLabel: String {
        let who = post.author.displayName
        let what = post.kind.tagTitle
        let body = post.text.isEmpty ? "" : ", \(post.text)"
        return "\(what) by \(who), \(post.agePhrase)\(body)"
    }
}

// MARK: - Shared chrome

struct LoungeAvatar: View {
    let author: LoungeAuthor
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let raw = author.avatarURL, let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Palette.strokeSoft, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Palette.field)
            Text(String(author.displayName.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// Author + timestamp + category tag, as seen across every card in the mockups.
struct LoungeAuthorRow: View {
    let post: LoungePost
    var avatarSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 7) {
            LoungeAvatar(author: post.author, size: avatarSize)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(post.author.handle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text("· \(post.ageText)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                HStack(spacing: 3) {
                    Image(systemName: post.kind.glyph)
                        .font(.system(size: 8, weight: .semibold))
                    Text(post.kind.tagTitle)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Palette.goldSoft)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Reaction + comment counts and the overflow menu. Controls stay visible —
/// double-tap is an accelerator, never the only way to react (§10).
struct LoungeReactionBar: View {
    let post: LoungePost
    var showMenu: Bool = true
    var onReact: () -> Void = {}
    var onOpen: () -> Void = {}
    var onMenu: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Button(action: { Haptics.tap(); onReact() }) {
                HStack(spacing: 4) {
                    Image(systemName: post.viewerHasReacted ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(post.viewerHasReacted ? Palette.moodAngry : Palette.textTertiary)
                    Text("\(post.reactionCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.field.opacity(0.72)))
                .overlay(Capsule().stroke(Palette.goldRing.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel(post.viewerHasReacted ? "Remove reaction" : "React")

            Button(action: { Haptics.tap(); onOpen() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                    Text("\(post.commentCount)")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.field.opacity(0.72)))
                .overlay(Capsule().stroke(Palette.goldRing.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("\(post.commentCount) comments")

            Spacer(minLength: 0)

            if showMenu {
                Button(action: { Haptics.tap(); onMenu() }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 28, height: 22, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("More options")
            }
        }
    }
}

/// Small vibe/context chips ("Chill", "Night Drive", strain, method).
struct LoungeChip: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            }
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Palette.field))
        .overlay(Capsule().stroke(Palette.strokeSoft, lineWidth: 0.5))
    }
}

/// Standard warm card surface used by most templates.
private struct LoungeSurface<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.cardElevated, Palette.card],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
            .overlay(
                Image("leaf_texture")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.045)
                    .blendMode(.softLight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .accessibilityHidden(true)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.goldRing.opacity(0.24), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                LoungePin()
                    .offset(x: -8, y: -9)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

private struct LoungePin: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Palette.goldSoft, Palette.goldDeep],
                                            startPoint: .top,
                                            endPoint: .bottom))
            .rotationEffect(.degrees(25))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Thought bubble (§8 High Thought)

/// A soft organic bubble with a tail. The tail is decorative and lives inside
/// the card's own bounds so it can never overlap a neighbouring post (§6.2).
struct LoungeThoughtCard: View {
    let post: LoungePost
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onMenu: (LoungePost) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LoungeAuthorRow(post: post, avatarSize: 22)

            Button(action: { onOpen(post) }) {
                Text(post.text)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            LoungeReactionBar(post: post,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) },
                              onMenu: { onMenu(post) })
        }
        .padding(14)
        .background(bubbleBackground)
        .overlay(alignment: .bottomLeading) { tail }
        .padding(.bottom, 10)   // reserved margin the tail lives in
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }

    private var bubbleBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                .fill(LinearGradient(colors: [Palette.cardElevated, Palette.greenDeep.opacity(0.42)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Circle()
                .fill(Palette.cardElevated)
                .frame(width: 58, height: 58)
                .offset(x: -42, y: -16)
                .opacity(0.55)
            Circle()
                .fill(Palette.greenDeep.opacity(0.58))
                .frame(width: 64, height: 64)
                .offset(x: 52, y: -20)
            RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                .stroke(Palette.goldRing.opacity(0.18), lineWidth: 1)
            Image("leaf_texture")
                .resizable()
                .scaledToFill()
                .opacity(0.04)
                .blendMode(.softLight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
    }

    private var tail: some View {
        HStack(spacing: 3) {
            Circle().fill(Palette.cardElevated).frame(width: 9, height: 9)
                .overlay(Circle().stroke(Palette.stroke, lineWidth: 0.5))
            Circle().fill(Palette.cardElevated).frame(width: 5, height: 5)
                .overlay(Circle().stroke(Palette.stroke, lineWidth: 0.5))
        }
        .padding(.leading, 18)
        .offset(y: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Long text (§8 Rant / Review)

struct LoungeTextCard: View {
    let post: LoungePost
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onMenu: (LoungePost) -> Void = { _ in }

    /// Long text is never squeezed: it truncates to a preview and offers
    /// Read More rather than shrinking into an unreadable column (§6.2).
    private var needsReadMore: Bool { post.characterCount > LoungePost.readMoreLimit }

    var body: some View {
        LoungeSurface {
            LoungeAuthorRow(post: post)

            if post.kind == .review, let strain = post.strainName {
                HStack(spacing: 6) {
                    LoungeChip(text: strain, icon: "leaf.fill")
                    if let method = post.method { LoungeChip(text: method) }
                }
            }

            Button(action: { onOpen(post) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(post.text)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.text)
                        .lineLimit(needsReadMore ? 6 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if needsReadMore {
                        Text("Read More")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.greenBright)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !post.media.isEmpty {
                LoungeMediaThumb(media: post.media[0], height: 150)
                    .onTapGesture { onOpen(post) }
            }

            LoungeReactionBar(post: post,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) },
                              onMenu: { onMenu(post) })
        }
    }
}

// MARK: - Media (§8 Photo / Setup / Munchies / Video)

struct LoungeMediaThumb: View {
    let media: LoungeMedia
    var height: CGFloat?

    /// Only constrain the ratio when no explicit height was given; the modifier
    /// wants a CGFloat?, and media aspect is stored as a Double.
    private var intrinsicRatio: CGFloat? {
        height == nil ? CGFloat(media.aspectRatio) : nil
    }

    var body: some View {
        ZStack {
            if let url = URL(string: media.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.field)
                        .overlay(ProgressView().tint(Palette.textTertiary))
                }
            } else {
                Rectangle().fill(Palette.field)
            }
            if media.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .aspectRatio(intrinsicRatio, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct LoungeMediaCard: View {
    let post: LoungePost
    var full: Bool = false
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onMenu: (LoungePost) -> Void = { _ in }

    var body: some View {
        LoungeSurface(padding: 10) {
            LoungeAuthorRow(post: post, avatarSize: 22)

            if let media = post.primaryMedia {
                Button(action: { onOpen(post) }) {
                    LoungeMediaThumb(media: media, height: full ? 220 : 150)
                }
                .buttonStyle(.plain)
                // Author-supplied alt text (§12) beats the generic label.
                .accessibilityLabel(media.altText.map { "\($0). Opens full view" } ?? "Open media")
            }

            if !post.text.isEmpty {
                Text(post.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .lineLimit(full ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !post.vibeTags.isEmpty || post.strainName != nil {
                HStack(spacing: 5) {
                    if let strain = post.strainName { LoungeChip(text: strain, icon: "leaf.fill") }
                    ForEach(post.vibeTags.prefix(2), id: \.self) { LoungeChip(text: $0) }
                }
            }

            LoungeReactionBar(post: post,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) },
                              onMenu: { onMenu(post) })
        }
    }
}

// MARK: - Music (§8 Pass the Aux)

/// A functional player, not decorative album art (§Table 4). Playback is an
/// explicit control and never auto-plays sound (§9). Real audio comes from
/// LoungePreviewPlayer — one shared AVPlayer, one preview at a time, with the
/// progress bar driven by actual playback position.
struct LoungePlayerCard: View {
    let post: LoungePost
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onMenu: (LoungePost) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    /// Accessed in body so observation tracking picks up transport changes.
    private var player: LoungePreviewPlayer { .shared }

    var body: some View {
        LoungeSurface(padding: 10) {
            LoungeAuthorRow(post: post, avatarSize: 22)

            if let track = post.track {
                artwork(track)
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text).lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary).lineLimit(1)

                if !post.text.isEmpty {
                    Text(post.text)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                transport(track)

                if !track.vibeTags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(track.vibeTags.prefix(2), id: \.self) { LoungeChip(text: $0) }
                    }
                }
            }

            LoungeReactionBar(post: post,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) },
                              onMenu: { onMenu(post) })
        }
        // A card that scrolls out of the feed takes its sound with it.
        .onDisappear { player.stop(postID: post.id) }
    }

    @ViewBuilder private func artwork(_ track: LoungeTrack) -> some View {
        ZStack {
            if let raw = track.artworkURL, let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.field)
                }
            } else {
                Rectangle().fill(Palette.field)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 24)).foregroundStyle(Palette.textTertiary))
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private func transport(_ track: LoungeTrack) -> some View {
        if track.previewURL != nil {
            let playing = player.isPlaying(post.id)
            HStack(spacing: 8) {
                Button(action: { Haptics.tap(); player.toggle(postID: post.id, track: track) }) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.onGreen)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Palette.green))
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel(playing ? "Pause preview of \(track.title)" : "Play preview of \(track.title)")

                GeometryFreeBar(fraction: player.progress(for: post.id))
                    .frame(height: 4)

                Text(timeText(track))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
        } else {
            // No preview stream for this track — send the listener out instead
            // of showing a transport that can't transport.
            Button(action: { openInMusic(track) }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open in Music")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Palette.greenBright)
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("Open \(track.title) by \(track.artist) in Music")
        }
    }

    /// Elapsed time while this card is the active preview, else total duration.
    private func timeText(_ track: LoungeTrack) -> String {
        if player.isActive(post.id) { return Self.timestamp(player.elapsed) }
        guard let seconds = track.durationSeconds, seconds > 0 else { return "--:--" }
        return Self.timestamp(seconds)
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func openInMusic(_ track: LoungeTrack) {
        Haptics.tap()
        let term = "\(track.title) \(track.artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://music.apple.com/search?term=\(term)") {
            openURL(url)
        }
    }
}

// MARK: - Poll (§8)

struct LoungePollCard: View {
    let post: LoungePost
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }
    var onVote: (LoungePost, String) -> Void = { _, _ in }
    var onMenu: (LoungePost) -> Void = { _ in }

    @State private var pendingChoice: String?

    var body: some View {
        LoungeSurface {
            LoungeAuthorRow(post: post, avatarSize: 22)

            if let poll = post.poll {
                Text(poll.question)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    ForEach(poll.choices) { choice in
                        choiceRow(poll: poll, choice: choice)
                    }
                }

                HStack {
                    Text("\(poll.totalVotes) votes")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer()
                    if !poll.hasVoted && !poll.isClosed {
                        Button("Vote") { submit(poll) }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(pendingChoice == nil ? Palette.textTertiary : Palette.onGreen)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(pendingChoice == nil ? Palette.field : Palette.green))
                            .buttonStyle(.plain)
                            .disabled(pendingChoice == nil)
                    } else if poll.isClosed {
                        Text("Closed").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }

            LoungeReactionBar(post: post,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) },
                              onMenu: { onMenu(post) })
        }
        // Once the store reflects the recorded vote (optimistic or from the
        // server response), the pending selection has served its purpose —
        // clear it so it can't linger as stale highlight state.
        .onChange(of: post.poll?.viewerChoiceID) { _, recorded in
            if recorded != nil { pendingChoice = nil }
        }
    }

    /// Percentages appear only after the viewer votes (§Table 4).
    @ViewBuilder
    private func choiceRow(poll: LoungePollContent, choice: LoungePollChoice) -> some View {
        let selected = poll.viewerChoiceID == choice.id || pendingChoice == choice.id
        Button(action: {
            guard !poll.hasVoted, !poll.isClosed else { return }
            pendingChoice = choice.id
            Haptics.selection()
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(choice.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    if poll.hasVoted {
                        Text("\(Int((poll.fraction(for: choice) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .monospacedDigit()
                    }
                }
                if poll.hasVoted {
                    GeometryFreeBar(fraction: poll.fraction(for: choice))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(selected ? Palette.green.opacity(0.18) : Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(selected ? Palette.green : Palette.strokeSoft, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func submit(_ poll: LoungePollContent) {
        guard let choice = pendingChoice else { return }
        Haptics.tap()
        onVote(post, choice)
    }
}

// MARK: - Live preview (§9)

struct LoungeLiveCard: View {
    let post: LoungePost
    var featured: Bool = false
    var onOpen: (LoungePost) -> Void = { _ in }
    var onJoin: (LoungePost) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                still
                liveBadge.padding(10)
            }
            details
        }
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .stroke(Palette.goldRing.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(post) }
    }

    @ViewBuilder private var still: some View {
        ZStack {
            if let raw = post.live?.stillURL, let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.field)
                }
            } else {
                LinearGradient(colors: [Palette.goldDeep.opacity(0.55), Palette.card],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(height: featured ? 150 : 104)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(Palette.moodAngry).frame(width: 6, height: 6)
            Text("LIVE NOW")
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(post.live?.title ?? "Live session")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                Text("\(post.live?.participantCount ?? 0) in the circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }

            if let tags = post.live?.vibeTags, !tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(tags.prefix(featured ? 3 : 2), id: \.self) { LoungeChip(text: $0) }
                }
            }

            // Join is always an explicit, separate action (§10).
            Button(action: { Haptics.tap(); onJoin(post) }) {
                Text("Join")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Capsule().fill(Palette.green))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join \(post.live?.title ?? "live session")")
        }
        .padding(12)
    }
}

// MARK: - Short check-in (§8)

struct LoungeCheckInCard: View {
    let post: LoungePost
    var onOpen: (LoungePost) -> Void = { _ in }
    var onReact: (LoungePost) -> Void = { _ in }

    var body: some View {
        LoungeSurface(padding: 11) {
            LoungeAuthorRow(post: post, avatarSize: 20)
            if !post.text.isEmpty {
                Text(post.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let mood = post.mood {
                LoungeChip(text: mood, icon: "sparkles")
            }
            LoungeReactionBar(post: post, showMenu: false,
                              onReact: { onReact(post) },
                              onOpen: { onOpen(post) })
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(post) }
    }
}
