//
//  LogSeshView.swift
//  HighThoughts
//
//  Log or edit a sesh. Supports strain type-ahead, real photo capture, mood
//  pre-fill from strain effects, validation, and a save toast/haptic.
//

import SwiftUI

struct LogSeshView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss

    /// Pre-selected strain (from the Library).
    var prefill: StrainProfile? = nil
    /// Existing entry to edit; nil means a new entry.
    var editing: JournalEntry? = nil

    @State private var strain = ""
    @State private var extraStrains: [String] = []   // #multi-strain
    @State private var newStrainEntry = ""            // input for adding another strain
    @State private var newExtraStrain = ""
    @State private var method = ""
    @State private var rating: Double = 8
    @State private var mood: Mood?
    @State private var smokeAgain: SmokeAgain?
    @State private var category: SeshCategory?
    @State private var customCategory: String?        // #custom categories
    @State private var showAddCategory = false        // inline add-category field
    @State private var newCategoryName = ""
    @State private var notes = ""
    @State private var photoName: String?
    @State private var sessionTags: Set<String> = []   // #vault rebuild — Session Tags
    @State private var effects: Set<String> = []         // Effects selection
    @State private var customEffect = ""                 // ➕ custom effect input
    @State private var showCustomEffect = false
    @State private var champion: String?                 // "Why are you saving this?"
    @State private var moodBefore: Int = 2
    @State private var moodAfter: Int = 2
    @State private var trackMoodShift = false
    @State private var amount = ""
    @State private var amountUnit = "g"
    @State private var matched: StrainProfile?
    @State private var showSuggestions = false
    @State private var didLoad = false

    private let moodCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var suggestions: [StrainProfile] {
        guard showSuggestions, matched?.name != strain else { return [] }
        return strains.suggestions(for: strain)
    }

    /// Show the "add new strain" affordance only when the typed name is real,
    /// not already matched, and not present anywhere in the local database.
    private var canAddNew: Bool {
        let trimmed = strain.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return false }
        return strains.isUnknown(trimmed)
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: isEditing ? "Edit sesh" : "Log your sesh",
                             onBack: { dismiss() }, showLeaf: true)
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 18) {
                        // Strain + photo row, with type-ahead from the catalog
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .bottom, spacing: 10) {
                                VStack(alignment: .leading, spacing: 8) {
                                    FieldLabel(text: "Strain")
                                    TextField("", text: $strain,
                                              prompt: Text("Enter strain name").foregroundStyle(Palette.textTertiary))
                                        .foregroundStyle(Palette.text)
                                        .submitLabel(.done)
                                        .padding(.horizontal, 14).padding(.vertical, 13)
                                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                        .onChange(of: strain) { _, newValue in
                                            showSuggestions = true
                                            if let m = matched, m.name != newValue { matched = nil }
                                        }
                                }
                                // Real photo capture (camera or library)
                                VStack(alignment: .leading, spacing: 8) {
                                    FieldLabel(text: "Photo")
                                    PhotoField(photoName: $photoName, size: 48)
                                }
                            }

                            if !suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(suggestions) { s in
                                        Button { select(s) } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "leaf.fill").font(.system(size: 12)).foregroundStyle(s.type.tint)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(s.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                                                    Text(strainSubtitle(s)).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                                }
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.horizontal, 12).padding(.vertical, 10)
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

                            // Offer to save a brand-new strain to the local library.
                            if showSuggestions, matched == nil, canAddNew {
                                Button { addNewStrain() } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.green)
                                        Text("Add \"\(strain.trimmingCharacters(in: .whitespaces))\" as a new strain")
                                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.green.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }

                            if let m = matched { StrainMatchChip(profile: m) }

                            // Additional strains in the same sesh (#multi-strain)
                            if !extraStrains.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(Array(extraStrains.enumerated()), id: \.offset) { idx, name in
                                        HStack(spacing: 8) {
                                            Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(Palette.green)
                                            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                            Spacer()
                                            Button {
                                                extraStrains.remove(at: idx); Haptics.selection()
                                            } label: {
                                                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.textTertiary)
                                            }.buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 9)
                                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                                    }
                                }
                            }
                            // Add-another-strain row
                            HStack(spacing: 8) {
                                TextField("", text: $newStrainEntry,
                                          prompt: Text("Add another strain…").foregroundStyle(Palette.textTertiary))
                                    .foregroundStyle(Palette.text).submitLabel(.done)
                                    .onSubmit { addExtraStrain() }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.strokeSoft, lineWidth: 1))
                                Button { addExtraStrain() } label: {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                                }
                                .buttonStyle(.plain)
                                .disabled(newStrainEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                                .opacity(newStrainEntry.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                            }
                            if !extraStrains.isEmpty {
                                Text("This sesh has \(extraStrains.count + 1) strains. The first is used for strain stats.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            }
                        }

                        InputField(label: "Roll up / Method Used", placeholder: "e.g. Raw Classic", value: $method)

                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Rate Your High")
                            RatingSlider(value: $rating)
                        }

                        // Mood
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "How are you feeling currently? (Choose)")
                            LazyVGrid(columns: moodCols, spacing: 12) {
                                ForEach(Mood.allCases) { m in
                                    OptionChip(title: m.rawValue, symbol: m.symbol, isSelected: mood == m) {
                                        Haptics.selection()
                                        mood = (mood == m) ? nil : m
                                    }
                                }
                            }
                        }

                        // Mood shift (before → after) — optional, #6
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $trackMoodShift.animation()) {
                                FieldLabel(text: "Track mood shift?")
                            }.tint(Palette.green)
                            if trackMoodShift {
                                moodScaleRow("Before", value: $moodBefore)
                                moodScaleRow("After", value: $moodAfter)
                                let delta = moodAfter - moodBefore
                                HStack(spacing: 6) {
                                    Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "arrow.right")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(delta > 0 ? "Lifted your mood (+\(delta))" : delta < 0 ? "Brought it down (\(delta))" : "No change")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(delta > 0 ? Palette.greenBright : delta < 0 ? Palette.moodAngry : Palette.textSecondary)
                            }
                        }

                        // Would you smoke again? — Definitely / Maybe / No
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Would you smoke again?")
                            HStack(spacing: 10) {
                                ForEach(SmokeAgain.allCases) { opt in
                                    EmojiChip(emoji: opt.emoji, title: opt.rawValue,
                                              isSelected: smokeAgain == opt) {
                                        Haptics.selection()
                                        smokeAgain = (smokeAgain == opt) ? nil : opt
                                    }
                                }
                            }
                        }

                        // Category — built-ins + your custom categories (#custom categories)
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Add to Category / List?")
                            LazyVGrid(columns: moodCols, spacing: 12) {
                                // Built-in categories
                                ForEach(SeshCategory.allCases) { c in
                                    OptionChip(title: c.rawValue, symbol: c.symbol, isSelected: category == c && customCategory == nil) {
                                        Haptics.selection()
                                        if category == c { category = nil }
                                        else { category = c; customCategory = nil }
                                    }
                                }
                                // Custom categories
                                ForEach(session.customCategories, id: \.self) { name in
                                    OptionChip(title: name, symbol: "tag.fill", isSelected: customCategory == name) {
                                        Haptics.selection()
                                        if customCategory == name { customCategory = nil }
                                        else { customCategory = name; category = nil }
                                    }
                                }
                            }
                            // Add a new custom category inline
                            if showAddCategory {
                                HStack(spacing: 8) {
                                    TextField("", text: $newCategoryName,
                                              prompt: Text("New category name…").foregroundStyle(Palette.textTertiary))
                                        .foregroundStyle(Palette.text).submitLabel(.done)
                                        .onSubmit { commitNewCategory() }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.strokeSoft, lineWidth: 1))
                                    Button { commitNewCategory() } label: {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .opacity(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                                }
                            } else {
                                Button { withAnimation { showAddCategory = true } } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                                        Text("New category").font(.system(size: 13, weight: .medium))
                                    }.foregroundStyle(Palette.green)
                                }.buttonStyle(.plain)
                            }
                        }

                        // "Why are you saving this?" — only when adding to Favorites (#champions)
                        if category == .personalFaves {
                            VStack(alignment: .leading, spacing: 12) {
                                FieldLabel(text: "Why are you saving this?")
                                LazyVGrid(columns: moodCols, spacing: 12) {
                                    ForEach(Champion.allCases) { c in
                                        EmojiChip(emoji: c.emoji, title: c.rawValue,
                                                  isSelected: champion == c.rawValue) {
                                            Haptics.selection()
                                            champion = (champion == c.rawValue) ? nil : c.rawValue
                                        }
                                    }
                                }
                            }
                        }

                        // Session Tags — multi-select (separate from Vault & Effects)
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "Session Tags")
                            LazyVGrid(columns: moodCols, spacing: 12) {
                                ForEach(SessionType.allCases) { t in
                                    EmojiChip(emoji: t.emoji, title: t.rawValue,
                                              isSelected: sessionTags.contains(t.rawValue)) {
                                        Haptics.selection()
                                        if sessionTags.contains(t.rawValue) { sessionTags.remove(t.rawValue) }
                                        else { sessionTags.insert(t.rawValue) }
                                    }
                                }
                            }
                        }

                        // Effects — how did it make you feel? (multi-select + custom)
                        VStack(alignment: .leading, spacing: 12) {
                            FieldLabel(text: "How did it make you feel?")
                            LazyVGrid(columns: moodCols, spacing: 12) {
                                ForEach(SeshEffect.allCases) { ef in
                                    EmojiChip(emoji: ef.emoji, title: ef.rawValue,
                                              isSelected: effects.contains(ef.rawValue)) {
                                        Haptics.selection()
                                        if effects.contains(ef.rawValue) { effects.remove(ef.rawValue) }
                                        else { effects.insert(ef.rawValue) }
                                    }
                                }
                            }
                            // Custom effects already chosen (tap to remove)
                            let customs = Array(effects.filter { e in !SeshEffect.allCases.contains { $0.rawValue == e } }).sorted()
                            if !customs.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(customs, id: \.self) { c in
                                        Button { effects.remove(c); Haptics.selection() } label: {
                                            HStack(spacing: 5) {
                                                Text(c).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.onGreen)
                                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onGreen)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Capsule().fill(Palette.green))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            // ➕ Custom
                            if showCustomEffect {
                                HStack(spacing: 8) {
                                    TextField("", text: $customEffect,
                                              prompt: Text("Custom feeling…").foregroundStyle(Palette.textTertiary))
                                        .foregroundStyle(Palette.text).submitLabel(.done)
                                        .onSubmit { commitCustomEffect() }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.strokeSoft, lineWidth: 1))
                                    Button { commitCustomEffect() } label: {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                                    }.buttonStyle(.plain)
                                    .disabled(customEffect.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .opacity(customEffect.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                                }
                            } else {
                                Button { withAnimation { showCustomEffect = true } } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                                        Text("Custom").font(.system(size: 13, weight: .medium))
                                    }.foregroundStyle(Palette.green)
                                }.buttonStyle(.plain)
                            }
                        }

                        // Amount (optional) — #2/#3 dosage
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Amount (optional)")
                            HStack(spacing: 8) {
                                TextField("", text: $amount, prompt: Text("0").foregroundStyle(Palette.textTertiary))
                                    .keyboardType(.decimalPad).foregroundStyle(Palette.text)
                                    .padding(.horizontal, 14).padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                Menu {
                                    ForEach(["g", "hits", "mg", "bowls", "ml"], id: \.self) { u in
                                        Button(u) { amountUnit = u }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(amountUnit).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                }
                            }
                        }

                        NotesField(label: "Personal Notes", placeholder: "How was your experience?", text: $notes)

                        PrimaryButton(title: isEditing ? "Save Changes" : "Save Entry") { save() }
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear(perform: loadInitial)
    }

    // MARK: Actions

    private func loadInitial() {
        guard !didLoad else { return }
        didLoad = true
        if let e = editing {
            strain = e.strain; method = e.method; rating = e.rating
            extraStrains = e.extraStrains ?? []
            mood = e.mood; smokeAgain = e.smokeAgain; category = e.category
            customCategory = e.customCategory
            sessionTags = Set(e.sessionTags ?? [])
            effects = Set(e.effects ?? [])
            champion = e.champion
            notes = e.notes; photoName = e.photoName
            if let mb = e.moodBefore, let ma = e.moodAfter {
                moodBefore = mb; moodAfter = ma; trackMoodShift = true
            }
            if let amt = e.amount { amount = amt.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amt)) : String(format: "%.1f", amt) }
            if let u = e.amountUnit { amountUnit = u }
            matched = strains.strain(named: e.strain)
        } else if let p = prefill {
            select(p)
        }
    }

    private func save() {
        // Validation: trimmed strain, clamped rating.
        let trimmed = strain.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "Untitled" : session.canonicalStrainName(trimmed)
        let clampedRating = min(10, max(1, rating))

        var entry = editing ?? JournalEntry(strain: name, method: "", rating: clampedRating, notes: "")
        entry.strain = name
        entry.extraStrains = extraStrains.isEmpty ? nil : extraStrains
        entry.method = method.trimmingCharacters(in: .whitespaces)
        entry.rating = clampedRating
        entry.mood = mood
        entry.smokeAgain = smokeAgain
        entry.category = category
        entry.customCategory = customCategory
        entry.sessionTags = sessionTags.isEmpty ? nil : Array(sessionTags)
        entry.effects = effects.isEmpty ? nil : Array(effects)
        // Champion only applies when saved to Favorites.
        entry.champion = (category == .personalFaves) ? champion : nil
        entry.notes = notes
        // Price is no longer entered per-sesh; it comes from the stash/purchase
        // log on Home. Existing entries keep whatever price they already had.
        entry.photoName = photoName
        entry.moodBefore = trackMoodShift ? moodBefore : nil
        entry.moodAfter = trackMoodShift ? moodAfter : nil
        let amountValue = Double(amount.filter { "0123456789.".contains($0) })
        entry.amount = amountValue
        entry.amountUnit = amountValue != nil ? amountUnit : nil

        session.upsert(entry)
        Haptics.success()
        dismiss()
    }

    private func moodScaleRow(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(MoodScaleInfo.face(value.wrappedValue)) \(MoodScaleInfo.label(value.wrappedValue))")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            }
            HStack(spacing: 8) {
                ForEach(0..<5) { i in
                    Button { value.wrappedValue = i; Haptics.selection() } label: {
                        Text(MoodScaleInfo.faces[i]).font(.system(size: 22))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(value.wrappedValue == i ? Palette.green.opacity(0.25) : Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(value.wrappedValue == i ? Palette.green : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label) \(MoodScaleInfo.label(i))")
                }
            }
        }
    }

    private func addExtraStrain() {
        let trimmed = newStrainEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let canonical = session.canonicalStrainName(trimmed)
        // Avoid duplicating the primary strain or an already-added extra.
        let primary = strain.trimmingCharacters(in: .whitespaces)
        if canonical.caseInsensitiveCompare(primary) != .orderedSame,
           !extraStrains.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
            extraStrains.append(canonical)
        }
        newStrainEntry = ""
        Haptics.selection()
    }

    private func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        session.addCategory(trimmed)
        customCategory = trimmed   // select the newly created category
        category = nil
        newCategoryName = ""
        showAddCategory = false
        Haptics.success()
    }

    private func commitCustomEffect() {
        let trimmed = customEffect.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        effects.insert(trimmed)
        customEffect = ""
        showCustomEffect = false
        Haptics.success()
    }

    private func select(_ s: StrainProfile) {
        strain = s.name
        matched = s
        showSuggestions = false
        // Pre-fill mood from the strain's top effect when nothing is chosen yet.
        if mood == nil, let topEffect = s.effects.first?.name {
            mood = Mood.from(effect: topEffect)
        }
        Haptics.tap()
    }

    /// Save the typed name as a new custom strain in the local library, then
    /// select it so future logs autocomplete it.
    private func addNewStrain() {
        let trimmed = strain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let created = strains.addCustom(name: trimmed, type: .hybrid)
        matched = created
        showSuggestions = false
        Haptics.success()
    }

    private func strainSubtitle(_ s: StrainProfile) -> String {
        var bits = [s.type.rawValue]
        if let thc = s.thc { bits.append("THC \(Int(thc))%") }
        if let first = s.effects.first { bits.append(first.name) }
        return bits.joined(separator: " · ")
    }
}

// MARK: - Map a catalog effect name to one of the app's moods

extension Mood {
    static func from(effect: String) -> Mood? {
        let e = effect.lowercased()
        if e.contains("relax") || e.contains("sleep") { return .couchPotato }
        if e.contains("energ") { return .energetic }
        if e.contains("focus") || e.contains("creativ") || e.contains("product") { return .productive }
        if e.contains("happy") || e.contains("euphor") || e.contains("uplift") { return .chill }
        return nil
    }
}

// MARK: - Matched strain chip

struct StrainMatchChip: View {
    let profile: StrainProfile
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 13)).foregroundStyle(Palette.green)
            Text(profile.type.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(profile.type.tint)
            if let thc = profile.thc {
                Text("THC \(Int(thc))%").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            if let first = profile.effects.first {
                Text("· \(first.name)").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if let src = profile.sources.first {
                Text(src).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}
