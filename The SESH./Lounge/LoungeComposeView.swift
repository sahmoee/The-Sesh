//
//  LoungeComposeView.swift
//  The SESH
//
//  (SESH-RL-001-R2 Phase 4) The compose sheet — "pass something to the circle".
//
//  One sheet, eight kinds. The main text editor is shared; each kind adds its
//  own attachment section (photo, poll builder, track search, review extras).
//  Sesh context (strain / method / mood) is opt-in per field, defaulted from
//  PrivacySettings (§12), and prefilled from the live or latest sesh. Submits
//  go through LoungeFeedStore.createPost, which uploads media first, creates
//  the post, and prepends it to the feed without reshuffling anything (§11).
//
//  Presented by LoungeFeedView in a sheet; the parameterless init is the
//  public contract.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Draft bits

/// One editable poll choice row. The id is minted client-side and sent to the
/// server, which keeps it (or substitutes its own) — votes are forced to 0
/// server-side either way.
private struct PollChoiceDraft: Identifiable, Hashable {
    let id: String = UUID().uuidString
    var label: String = ""

    var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A processed, upload-ready photo attachment.
private struct ComposePhoto {
    var data: Data      // JPEG, longest side <= 1280, quality 0.7
    var aspect: Double  // width / height
    var preview: UIImage
}

// MARK: - Compose sheet

struct LoungeComposeView: View {
    @Environment(LoungeFeedStore.self) private var store
    @Environment(PlaylistStore.self) private var playlists
    @Environment(StrainStore.self) private var strains
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    // Kind
    @State private var kind: LoungePostKind = .highThought

    // Text
    @State private var text = ""
    @FocusState private var editorFocused: Bool

    // Photo (1 image v1)
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: ComposePhoto?
    @State private var photoAltText = ""
    @State private var processingPhoto = false
    @State private var photoError: String?

    // Poll (2–6 choices)
    @State private var pollChoices: [PollChoiceDraft] = [PollChoiceDraft(), PollChoiceDraft()]

    // Music
    @State private var musicQuery = ""
    @State private var musicSource: ExportTarget = .appleMusic
    @State private var musicResults: [PlaylistTrack] = []
    @State private var musicSearching = false
    @State private var musicSearched = false
    @State private var musicSearchTask: Task<Void, Never>?
    @State private var selectedTrack: PlaylistTrack?

    // Review
    @State private var reviewStrain = ""
    @State private var reviewRating: Double = 8
    @State private var showStrainSuggestions = false

    // Sesh context — field-level sharing per §12, DEFAULTED from PrivacySettings.
    @State private var shareStrain = PrivacySettings.shared.shareStrainDetails
    @State private var shareMethod = PrivacySettings.shared.shareActivity
    @State private var shareMood = PrivacySettings.shared.shareActivity
    @State private var contextStrain: String?
    @State private var contextMethod: String?
    @State private var contextMood: String?
    @State private var didPrefill = false

    // Governance — no "private" in the composer; private stays in the journal.
    @State private var visibility: LoungeVisibility = .publicFeed

    // Submit
    /// Minted once per draft; resubmitting the same draft after a flaky
    /// response is deduped server-side via X-Idempotency-Key.
    @State private var idempotencyKey = UUID().uuidString
    @State private var confirmDiscard = false

    private static let hardTextLimit = 4000
    private static let bubbleLimit = LoungePost.shortTextLimit     // 180
    private static let readMoreLimit = LoungePost.readMoreLimit    // 280
    private static let pollLabelLimit = 60
    private static let pollMaxChoices = 6
    /// Explicitly nonisolated: read from the off-main image-processing helper.
    nonisolated private static let mediaByteLimit = 2_000_000      // server cap 2 MB

    /// Kinds the composer offers, in display order (no video/live in v1).
    private static let composableKinds: [LoungePostKind] =
        [.highThought, .rant, .photo, .munchies, .poll, .checkIn, .review, .music]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        kindSection
                        editorSection
                        kindSpecificSection
                        contextSection
                        visibilitySection
                        errorSection
                        submitSection
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task { prefillFromSesh() }
        .interactiveDismissDisabled(hasEdits)
        .confirmationDialog("Discard this post?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Writing", role: .cancel) {}
        } message: {
            Text("What you wrote won't be passed to the circle.")
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > Self.hardTextLimit {
                text = String(newValue.prefix(Self.hardTextLimit))
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            loadPickedPhoto(newItem)
        }
        .onChange(of: musicQuery) { _, _ in scheduleMusicSearch() }
        .onChange(of: musicSource) { _, _ in scheduleMusicSearch() }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Pass something to the circle")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button {
                    if hasEdits { confirmDiscard = true } else { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: Kind picker

    private var kindSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.composableKinds, id: \.self) { k in
                    kindPill(k)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("What are you passing?")
    }

    private func kindPill(_ k: LoungePostKind) -> some View {
        let active = kind == k
        return Button {
            Haptics.selection()
            withMotion { kind = k }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: k.glyph).font(.system(size: 12, weight: .medium))
                Text(kindLabel(k)).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? Palette.onGreen : Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Capsule().fill(active ? Palette.green : Palette.field))
            .overlay(Capsule().stroke(active ? Color.clear : Palette.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityLabel(kindLabel(k))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func kindLabel(_ k: LoungePostKind) -> String {
        switch k {
        case .highThought: return "High Thought"
        case .rant:        return "Rant"
        case .photo:       return "Photo"
        case .munchies:    return "Munchies"
        case .poll:        return "Poll"
        case .checkIn:     return "Check-In"
        case .review:      return "Review"
        case .music:       return "Music"
        default:           return k.tagTitle
        }
    }

    // MARK: Text editor + counter

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(editorPlaceholder)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .foregroundStyle(Palette.text)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: kind == .rant ? 140 : 100)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .accessibilityLabel(editorAccessibilityLabel)
            }
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { editorFocused = true }

            counterRow
        }
    }

    private var editorPlaceholder: String {
        switch kind {
        case .highThought: return "What's floating through your head…"
        case .rant:        return "Let it out. All of it…"
        case .photo:       return "Say something about it (optional)…"
        case .munchies:    return "What's on the plate? (optional)…"
        case .poll:        return "Ask the circle a question…"
        case .checkIn:     return "Where's your head at right now?"
        case .review:      return "How was it? The taste, the high, the ride…"
        case .music:       return "Why this track? (optional)…"
        default:           return "Say something…"
        }
    }

    private var editorAccessibilityLabel: String {
        kind == .poll ? "Poll question" : "\(kindLabel(kind)) text"
    }

    private var counterRow: some View {
        let count = text.count
        // High Thought shows the 180 bubble cap; everything else the hard max.
        let visibleCap = kind == .highThought ? Self.bubbleLimit : Self.hardTextLimit
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let hint = editorHint {
                Text(hint.0)
                    .font(.system(size: 12))
                    .foregroundStyle(hint.1)
            }
            Spacer(minLength: 0)
            Text("\(count)/\(visibleCap)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(count > visibleCap ? Palette.gold : Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(counterAccessibilityLabel)
    }

    /// Dynamic guidance under the editor: short thoughts float as bubbles,
    /// long rants take the full width.
    private var editorHint: (String, Color)? {
        switch kind {
        case .highThought:
            return text.count <= Self.bubbleLimit
                ? ("Floats as a thought bubble", Palette.textTertiary)
                : ("Past \(Self.bubbleLimit), it lands as a full card", Palette.gold)
        case .rant:
            return text.count > Self.readMoreLimit
                ? ("Long rant — it takes the full width. Storytime.", Palette.goldSoft)
                : ("Under \(Self.readMoreLimit) keeps it snappy", Palette.textTertiary)
        default:
            return nil
        }
    }

    private var counterAccessibilityLabel: String {
        var parts = ["\(text.count) characters"]
        if kind == .highThought {
            parts.append(text.count <= Self.bubbleLimit
                ? "floats as a thought bubble"
                : "over the \(Self.bubbleLimit) character bubble size")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Kind-specific sections

    @ViewBuilder private var kindSpecificSection: some View {
        switch kind {
        case .photo, .munchies: photoSection
        case .poll:             pollSection
        case .music:            musicSection
        case .review:           reviewSection
        default:                EmptyView()
        }
    }

    // MARK: Photo

    @ViewBuilder private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: kind == .munchies ? "The evidence" : "Photo")
            if let photo {
                photoPreview(photo)
                InputField(label: "Describe it (alt text, optional)",
                           placeholder: "For friends using VoiceOver",
                           value: $photoAltText)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack(spacing: 10) {
                        if processingPhoto {
                            ProgressView().tint(Palette.textSecondary)
                            Text("Preparing photo…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 17))
                                .foregroundStyle(Palette.greenBright)
                            Text("Add a photo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Palette.text)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .disabled(processingPhoto)
                .accessibilityLabel("Add a photo")
            }
            if let photoError {
                Text(photoError)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.moodAngry)
            }
        }
    }

    private func photoPreview(_ photo: ComposePhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.preview)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1))
                .accessibilityLabel(photoAltText.isEmpty ? "Attached photo" : photoAltText)
            Button {
                Haptics.selection()
                withMotion { self.photo = nil; photoAltText = "" }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.text, Palette.card.opacity(0.85))
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("Remove photo")
            .padding(6)
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        processingPhoto = true
        photoError = nil
        Task {
            defer { pickerItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                processingPhoto = false
                photoError = "That photo couldn't be loaded. Try a different one."
                return
            }
            let processed = await Task.detached(priority: .userInitiated) {
                Self.makeUploadJPEG(from: image)
            }.value
            processingPhoto = false
            guard let processed else {
                photoError = "That photo couldn't be prepared. Try a different one."
                return
            }
            withMotion { photo = processed }
        }
    }

    /// Downscale to 1280 on the longest side and re-encode as JPEG 0.7.
    /// Re-rendering through UIGraphicsImageRenderer produces a brand-new
    /// bitmap, so the uploaded JPEG carries none of the original's EXIF /
    /// GPS-location metadata (§12 — location is stripped before anything
    /// leaves the device). Steps quality down if still over the 2 MB cap.
    nonisolated private static func makeUploadJPEG(from image: UIImage) -> ComposePhoto? {
        let maxSide: CGFloat = 1280
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let newSize = CGSize(width: max(1, image.size.width * scale),
                             height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        var quality: CGFloat = 0.7
        var data = rendered.jpegData(compressionQuality: quality)
        while let d = data, d.count > mediaByteLimit, quality > 0.3 {
            quality -= 0.15
            data = rendered.jpegData(compressionQuality: quality)
        }
        guard let final = data, final.count <= mediaByteLimit else { return nil }
        let aspect = Double(newSize.width / max(1, newSize.height))
        return ComposePhoto(data: final, aspect: aspect, preview: rendered)
    }

    // MARK: Poll builder

    private var pollSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Choices (2–\(Self.pollMaxChoices))")
            ForEach($pollChoices) { $choice in
                pollChoiceRow($choice)
            }
            if pollChoices.count < Self.pollMaxChoices {
                Button {
                    Haptics.selection()
                    withMotion { pollChoices.append(PollChoiceDraft()) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text("Add choice").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Palette.green)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Add poll choice")
            }
        }
    }

    private func pollChoiceRow(_ choice: Binding<PollChoiceDraft>) -> some View {
        let index = pollChoices.firstIndex(where: { $0.id == choice.wrappedValue.id }) ?? 0
        return HStack(spacing: 8) {
            TextField("", text: choice.label,
                      prompt: Text("Choice \(index + 1)").foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
                .submitLabel(.done)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.strokeSoft, lineWidth: 1))
                .onChange(of: choice.wrappedValue.label) { _, newValue in
                    // Server clamps labels at 60; mirror it so nothing is lost silently.
                    if newValue.count > Self.pollLabelLimit {
                        choice.wrappedValue.label = String(newValue.prefix(Self.pollLabelLimit))
                    }
                }
                .accessibilityLabel("Poll choice \(index + 1)")
            if pollChoices.count > 2 {
                Button {
                    Haptics.selection()
                    withMotion { pollChoices.removeAll { $0.id == choice.wrappedValue.id } }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityLabel("Remove choice \(index + 1)")
            }
        }
    }

    // MARK: Music (Pass the Aux)

    @ViewBuilder private var musicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Pass the aux")
            if let track = selectedTrack {
                selectedTrackCard(track)
            } else {
                Picker("Source", selection: $musicSource) {
                    Text("Apple Music").tag(ExportTarget.appleMusic)
                    Text("Spotify").tag(ExportTarget.spotify)
                }
                .pickerStyle(.segmented)

                TextField("", text: $musicQuery,
                          prompt: Text("Search a song…").foregroundStyle(Palette.textTertiary))
                    .foregroundStyle(Palette.text)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    .accessibilityLabel("Search for a song")

                if musicSearching {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.textSecondary)
                        Text("Searching…").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                } else if !musicResults.isEmpty {
                    musicResultsList
                } else if musicSearched && !musicQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("No songs found. Try another search.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var musicResultsList: some View {
        VStack(spacing: 0) {
            ForEach(musicResults.prefix(8)) { t in
                Button {
                    Haptics.tap()
                    withMotion { selectedTrack = t; musicResults = [] }
                } label: {
                    trackRow(t)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(t.title) by \(t.artist)")
                .accessibilityHint("Attaches this track")
                if t.id != musicResults.prefix(8).last?.id {
                    Rectangle().fill(Palette.stroke).frame(height: 0.5)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.cardElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private func trackRow(_ t: PlaylistTrack) -> some View {
        HStack(spacing: 10) {
            trackArt(t, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                Text(t.artist).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func selectedTrackCard(_ t: PlaylistTrack) -> some View {
        HStack(spacing: 12) {
            trackArt(t, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text).lineLimit(1)
                Text(t.artist).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer()
            Button {
                Haptics.selection()
                withMotion { selectedTrack = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("Remove track")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func trackArt(_ t: PlaylistTrack, size: CGFloat) -> some View {
        if let art = t.artworkURL, let url = URL(string: art) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                trackArtPlaceholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .accessibilityHidden(true)
        } else {
            trackArtPlaceholder
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var trackArtPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Palette.field)
            Image(systemName: "music.note").foregroundStyle(Palette.textTertiary)
        }
    }

    /// Debounced search mirroring TrackSearchView: 300 ms after the last
    /// keystroke, cancelled by newer input.
    private func scheduleMusicSearch() {
        musicSearchTask?.cancel()
        musicSearchTask = Task {
            let trimmed = musicQuery.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                musicResults = []; musicSearching = false; musicSearched = false
                return
            }
            musicSearching = true
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }  // cancelled: a newer query took over
            let r = await playlists.search(trimmed, on: musicSource)
            guard !Task.isCancelled else { return }
            musicResults = r
            musicSearching = false
            musicSearched = true
        }
    }

    // MARK: Review extras

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Strain (optional)")
                TextField("", text: $reviewStrain,
                          prompt: Text("Which strain is this about?").foregroundStyle(Palette.textTertiary))
                    .foregroundStyle(Palette.text)
                    .submitLabel(.done)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    .onChange(of: reviewStrain) { _, _ in showStrainSuggestions = true }
                    .accessibilityLabel("Strain name")
                strainSuggestionsList
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Rate the high")
                RatingSlider(value: $reviewRating)
            }
        }
    }

    @ViewBuilder private var strainSuggestionsList: some View {
        let suggestions = showStrainSuggestions ? strains.suggestions(for: reviewStrain) : []
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions) { s in
                    Button {
                        Haptics.tap()
                        reviewStrain = s.name
                        showStrainSuggestions = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.green)
                            Text(s.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if s.id != suggestions.last?.id {
                        Rectangle().fill(Palette.stroke).frame(height: 0.5)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.cardElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    // MARK: Sesh context ("share to the circle")

    @ViewBuilder private var contextSection: some View {
        if contextStrain != nil || contextMethod != nil || contextMood != nil {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(text: "Bring your sesh into the circle")
                Text("Each detail is shared only if its chip is on.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                FlowLayout(spacing: 8) {
                    if let strain = contextStrain {
                        contextChip("leaf.fill", "Strain", strain, isOn: shareStrain) {
                            shareStrain.toggle()
                        }
                    }
                    if let method = contextMethod {
                        contextChip("flame", "Method", method, isOn: shareMethod) {
                            shareMethod.toggle()
                        }
                    }
                    if let mood = contextMood {
                        contextChip("face.smiling", "Mood", mood, isOn: shareMood) {
                            shareMood.toggle()
                        }
                    }
                }
            }
        }
    }

    private func contextChip(_ symbol: String, _ label: String, _ value: String,
                             isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withMotion { toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
            }
            .foregroundStyle(isOn ? Palette.onGreen : Palette.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Capsule().fill(isOn ? Palette.green : Palette.field))
            .overlay(Capsule().stroke(isOn ? Color.clear : Palette.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityLabel("Share \(label.lowercased()): \(value)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Prefill context values from the live sesh if one is running, else the
    /// most recent journal entry. Runs once; nothing obvious means no prefill.
    private func prefillFromSesh() {
        guard !didPrefill else { return }
        didPrefill = true
        if let live = session.liveSesh {
            let strain = live.strainName.trimmingCharacters(in: .whitespaces)
            if !strain.isEmpty { contextStrain = strain }
            let method = live.rollMethod.trimmingCharacters(in: .whitespaces)
            if !method.isEmpty { contextMethod = method }
        }
        let latest = session.entries.max(by: { $0.date < $1.date })
        if contextStrain == nil, let s = latest?.strain,
           !s.isEmpty, s != "Untitled" {
            contextStrain = s
        }
        if contextMethod == nil, let m = latest?.method, !m.isEmpty {
            contextMethod = m
        }
        if contextMood == nil, let mood = latest?.mood {
            contextMood = mood.rawValue
        }
    }

    // MARK: Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Who's in the circle?")
            HStack(spacing: 10) {
                OptionChip(title: "Everyone", symbol: "globe",
                           isSelected: visibility == .publicFeed) {
                    Haptics.selection()
                    visibility = .publicFeed
                }
                OptionChip(title: "Friends only", symbol: "person.2.fill",
                           isSelected: visibility == .friendsOnly) {
                    Haptics.selection()
                    visibility = .friendsOnly
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Who's in the circle?")
    }

    // MARK: Error + submit

    @ViewBuilder private var errorSection: some View {
        if let err = store.composeError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.moodAngry)
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.moodAngry.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    private var submitSection: some View {
        PrimaryButton(title: submitTitle) { submit() }
            .disabled(!canSubmit)
            .padding(.top, 4)
            .accessibilityHint(canSubmit ? "Posts to the Lounge" : "Finish your post first")
    }

    private var submitTitle: String {
        if store.isUploadingMedia { return "Uploading photo…" }
        if store.isPosting { return "Passing it…" }
        return "Pass it to the circle"
    }

    // MARK: Validation & submit

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validPollChoices: [PollChoiceDraft] {
        pollChoices.filter { !$0.trimmedLabel.isEmpty }
    }

    private var canSubmit: Bool {
        guard !store.isPosting, !processingPhoto else { return false }
        switch kind {
        case .photo, .munchies:
            return photo != nil
        case .poll:
            return !trimmedText.isEmpty && validPollChoices.count >= 2
        case .music:
            return selectedTrack != nil
        default:
            return !trimmedText.isEmpty
        }
    }

    /// Anything worth a discard confirmation?
    private var hasEdits: Bool {
        !trimmedText.isEmpty
            || photo != nil
            || selectedTrack != nil
            || pollChoices.contains { !$0.trimmedLabel.isEmpty }
            || !reviewStrain.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            let poll: LoungePollContent? = kind == .poll
                ? LoungePollContent(question: trimmedText,
                                    choices: validPollChoices.map {
                                        LoungePollChoice(id: $0.id, label: $0.trimmedLabel)
                                    })
                : nil
            let track: LoungeTrack? = kind == .music
                ? selectedTrack.map {
                    LoungeTrack(title: $0.title, artist: $0.artist, artworkURL: $0.artworkURL)
                }
                : nil
            // Strain: an explicit review strain wins; otherwise the sesh-context
            // chip decides whether the strain travels with the post (§12).
            let strainName: String? = {
                if kind == .review {
                    let s = reviewStrain.trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { return s }
                }
                return shareStrain ? contextStrain : nil
            }()
            // A review's rating rides as a vibe tag ("8/10") — the post model
            // has no rating field and the tag renders naturally in the chrome.
            let vibeTags: [String] = kind == .review ? ["\(Int(reviewRating))/10"] : []
            let altText = photoAltText.trimmingCharacters(in: .whitespacesAndNewlines)

            let created = await store.createPost(
                kind: kind,
                text: trimmedText,
                imageJPEG: photo?.data,
                imageAspectRatio: photo?.aspect ?? 1,
                imageAltText: altText.isEmpty ? nil : altText,
                track: track,
                poll: poll,
                strainName: strainName,
                method: shareMethod ? contextMethod : nil,
                mood: shareMood ? contextMood : nil,
                vibeTags: vibeTags,
                visibility: visibility,
                idempotencyKey: idempotencyKey)

            if created != nil {
                Haptics.success()
                dismiss()
            }
            // On failure store.composeError renders inline and the whole draft
            // (text, photo, poll, track, toggles) stays exactly as it was.
        }
    }
}
