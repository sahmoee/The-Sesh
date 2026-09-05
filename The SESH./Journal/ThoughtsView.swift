//
//  ThoughtsView.swift
//  The SESH
//
//  Thoughts now live in the unified Log feed (see JournalView). This file keeps
//  the two reusable thought components used there: the ThoughtCard (a feed row)
//  and ComposeThoughtView (the new/edit sheet). The old Thoughts tab, the
//  segmented Thoughts/Rants control, and the Rant feature have been removed.
//

import SwiftUI

struct ThoughtCard: View {
    @Environment(AppSession.self) private var session
    let thought: HighThought

    var body: some View {
        let bg = thought.highlighted ? Palette.purple : Palette.card
        let stroke = thought.highlighted ? Palette.purpleStroke : Palette.stroke
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening").font(.system(size: 18)).foregroundStyle(Palette.gold)
                Text(thought.text).font(.system(size: 16)).foregroundStyle(Palette.text)
            }
            HStack(spacing: 8) {
                Text(timeString(thought.date)).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                if let tag = thought.tag { CategoryTag(text: tag.rawValue) }
                Spacer()
                Button {
                    Haptics.selection(); session.toggleThoughtFavorite(thought)
                } label: {
                    Image(systemName: thought.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(thought.isFavorite ? Palette.gold : Palette.textSecondary)
                        .minimumTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(thought.isFavorite ? "Unfavorite thought" : "Favorite thought")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

// MARK: - Compose Quick Thought (new or edit)

struct ComposeThoughtView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var editing: HighThought? = nil
    /// Optional tag to pre-select when composing a new thought (e.g. Rant from Home).
    var initialTag: ThoughtTag? = nil

    @State private var text = ""
    @State private var tag: ThoughtTag?
    @State private var visibility: PostVisibility = .privatePost
    @State private var didLoad = false
    @State private var loadedFingerprint = ""
    @State private var confirmDiscard = false
    @State private var confirmVisibility = false
    @State private var saveError: String?
    @State private var saving = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var fingerprint: String {
        JournalInputPolicy.fingerprint([text, tag?.rawValue ?? "", visibility.rawValue])
    }
    private var hasEdits: Bool { didLoad && fingerprint != loadedFingerprint }
    private var canSave: Bool { !JournalInputPolicy.trimmed(text).isEmpty && !saving }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: headerTitle, onBack: { if hasEdits { confirmDiscard = true } else { dismiss() } })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 18) {
                        NotesField(label: "What's on your mind?",
                                   placeholder: composerPlaceholder, text: $text, minHeight: 120)
                        tagSection
                        visibilitySection
                        if let saveError { Text(saveError).font(.callout).foregroundStyle(Palette.moodAngry).accessibilityIdentifier("thought.saveError") }
                        Text("Saved to your private journal on this device. Visibility is a preference for optional sharing; saving here does not publish a post.")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                        PrimaryButton(title: editing == nil ? "Capture Thought" : "Save Changes") {
                            if visibility != .privatePost && visibility != (editing?.visibility ?? .privatePost) {
                                confirmVisibility = true
                            } else { saveThought() }
                        }
                        .disabled(!canSave)
                        .accessibilityHint(canSave ? "Save this thought locally" : "Enter a thought before saving")
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                    .seshReadableForm()
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .seshEditorPresentation()
        .interactiveDismissDisabled(hasEdits)
        .confirmationDialog("Discard this thought draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
        .confirmationDialog("Change sharing preference?", isPresented: $confirmVisibility, titleVisibility: .visible) {
            Button("Save with \(visibility.rawValue)") { saveThought() }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text("The selected preference is \(visibility.rawValue). This journal save does not publish your thought.") }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let e = editing {
                text = e.text; tag = e.tag; visibility = e.visibility
            } else if let initialTag {
                tag = initialTag
            }
            loadedFingerprint = fingerprint
        }
    }

    private var headerTitle: String {
        if editing != nil { return "Edit Thought" }
        return tag == .rant ? "Rant" : "High Thought"
    }

    private var composerPlaceholder: String {
        tag == .rant ? "Let it all out…" : "Whoa, what if..."
    }

    @ViewBuilder private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Tag (optional)")
            FlowLayout(spacing: 10) {
                ForEach(ThoughtTag.allCases) { t in
                    Button {
                        Haptics.selection(); tag = (tag == t) ? nil : t
                    } label: {
                        Text(t.rawValue)
                            .font(.seshScaled(14, weight: .medium))
                            .foregroundStyle(tag == t ? Palette.onGreen : Palette.textSecondary)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(tag == t ? Palette.green : Palette.field))
                            .overlay(Capsule().stroke(tag == t ? Color.clear : Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tag == t ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Who can see this?")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(PostVisibility.allCases) { v in
                    Button {
                        Haptics.selection(); visibility = v
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: v.symbol).font(.system(size: 13))
                            Text(v.rawValue).font(.seshScaled(13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(visibility == v ? Palette.onGreen : Palette.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(visibility == v ? Palette.green : Palette.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(visibility == v ? Color.clear : Palette.stroke, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(visibility == v ? .isSelected : [])
                }
            }
        }
    }

    private func saveThought() {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave, !s.isEmpty else { return }
        if let original = editing {
            guard var e = session.thoughts.first(where: { $0.id == original.id }) else {
                saveError = "This thought was removed while you were editing. Your draft is still here; copy it before closing."
                return
            }
            e.text = s; e.tag = tag; e.visibility = visibility
            saving = true
            session.updateThought(e)
        } else {
            saving = true
            var t = HighThought(text: s, tag: tag)
            t.visibility = visibility
            session.addThought(t)
        }
        Haptics.success()
        dismiss()
    }
}
