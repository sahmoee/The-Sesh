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

    @State private var text = ""
    @State private var tag: ThoughtTag?
    @State private var visibility: PostVisibility = .privatePost
    @State private var didLoad = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: editing == nil ? "Quick Thought" : "Edit Thought", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 18) {
                        NotesField(label: "What's on your mind?",
                                   placeholder: "Whoa, what if...", text: $text, minHeight: 120)

                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Tag (optional)")
                            HStack(spacing: 10) {
                                ForEach(ThoughtTag.allCases) { t in
                                    Button {
                                        Haptics.selection(); tag = (tag == t) ? nil : t
                                    } label: {
                                        Text(t.rawValue)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(tag == t ? Palette.onGreen : Palette.textSecondary)
                                            .padding(.horizontal, 16).padding(.vertical, 9)
                                            .background(Capsule().fill(tag == t ? Palette.green : Palette.field))
                                            .overlay(Capsule().stroke(tag == t ? Color.clear : Palette.stroke, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Who can see this?")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(PostVisibility.allCases) { v in
                                    Button {
                                        Haptics.selection(); visibility = v
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: v.symbol).font(.system(size: 13))
                                            Text(v.rawValue).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        }
                                        .foregroundStyle(visibility == v ? Palette.onGreen : Palette.text)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(visibility == v ? Palette.green : Palette.field))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .stroke(visibility == v ? Color.clear : Palette.stroke, lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        PrimaryButton(title: editing == nil ? "Capture Thought" : "Save Changes") {
                            let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !s.isEmpty else { return }
                            if var e = editing {
                                e.text = s; e.tag = tag; e.visibility = visibility
                                session.updateThought(e)
                            } else {
                                var t = HighThought(text: s, tag: tag)
                                t.visibility = visibility
                                session.addThought(t)
                            }
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let e = editing { text = e.text; tag = e.tag; visibility = e.visibility }
        }
    }
}
