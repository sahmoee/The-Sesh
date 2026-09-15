//
//  GoalsAndExtras.swift
//  The SESH
//
//  A bundle of community + personal features:
//   - SeshGoal model + GoalsView (#goals): "smoke less", "spend less", etc., with
//     simple progress tracking from real session/spend data.
//   - JokesView (#jokes): a built-in rotating list of stoner-friendly jokes.
//   - CommunityPromptView (#story time / prompts): randomized prompts from an
//     extensive categorized list, with a space to answer.
//

import SwiftUI

// MARK: - Goals model

enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case smokeLess = "Smoke less"
    case spendLess = "Spend less"
    case toleranceBreak = "Tolerance break"
    case sleepBetter = "Sleep better"
    case stayPresent = "Be more present"
    case custom = "Custom"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .smokeLess:      return "chart.line.downtrend.xyaxis"
        case .spendLess:      return "dollarsign.circle"
        case .toleranceBreak: return "pause.circle"
        case .sleepBetter:    return "moon.zzz"
        case .stayPresent:    return "leaf"
        case .custom:         return "target"
        }
    }
    var blurb: String {
        switch self {
        case .smokeLess:      return "Fewer sessions per week"
        case .spendLess:      return "Keep your spend in check"
        case .toleranceBreak: return "Take a break to reset"
        case .sleepBetter:    return "Wind down earlier"
        case .stayPresent:    return "Be intentional with each sesh"
        case .custom:         return "Your own goal"
        }
    }
    /// Whether this goal type measures against a numeric target.
    var isMeasurable: Bool {
        self == .smokeLess || self == .spendLess
    }
}

struct SeshGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: GoalKind
    var title: String              // editable headline
    var target: Double?            // e.g. 5 sessions/week, or $40/week
    var unit: String?              // "sessions/week", "$/week"
    var createdAt = Date()
    var note: String = ""
    var active: Bool = true
}

// MARK: - Goals view

struct GoalsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editing: SeshGoal?
    @State private var pendingDeletion: SeshGoal?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Goals", onBack: { dismiss() }) {
                Button { showAdd = true } label: { Image(systemName: "plus").minimumTapTarget() }
                    .buttonStyle(.plain).foregroundStyle(Palette.text).accessibilityLabel("Add a personal goal")
            }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            ScrollView {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let summary = PersonalGoalPolicy.week(now: context.date, sessionDates: session.entries.map(\.date), purchases: session.purchases.map { ($0.date, $0.cost) })
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let error = session.goalStorageError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.moodAngry)
                            Button("Retry reading goals") { session.retryLoadingGoals() }.foregroundStyle(Palette.greenBright).minimumTapTarget()
                        }
                        if session.goals.isEmpty {
                            EmptyStateView(icon: "target", title: "Set a personal goal", message: "Keep your own intentions and weekly limits in one place.", actionTitle: "Add a goal", actionIcon: "plus") { showAdd = true }
                        } else {
                            Text("Week of \(summary.start.formatted(.dateTime.month(.abbreviated).day())) · recorded through now")
                                .font(.footnote).foregroundStyle(Palette.textSecondary)
                            if summary.ignoredCosts > 0 {
                                Label("\(summary.ignoredCosts) invalid recorded cost(s) excluded from the total.", systemImage: "exclamationmark.circle")
                                    .font(.footnote).foregroundStyle(Palette.moodAngry)
                            }
                            ForEach(session.goals.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }) { goal in
                                goalCard(goal, summary: summary)
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 28).seshReadableForm()
                }
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showAdd) { AddGoalSheet() }
        .sheet(item: $editing) { AddGoalSheet(editing: $0) }
        .confirmationDialog("Delete this goal?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            if let goal = pendingDeletion { Button("Delete Goal", role: .destructive) { if session.deleteGoal(goal) { pendingDeletion = nil; Haptics.warning() } } }
            Button("Keep Goal", role: .cancel) { pendingDeletion = nil }
        } message: { Text("Only the goal is removed. Your journal and historical records remain.") }
    }

    private func goalCard(_ goal: SeshGoal, summary: PersonalGoalPolicy.WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: goal.kind.symbol).foregroundStyle(Palette.greenBright).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title).font(.headline).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    Text(goal.active ? goal.kind.rawValue : "Paused · " + goal.kind.rawValue).font(.caption).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Menu {
                    Button("Edit Goal", systemImage: "pencil") { editing = goal }
                    Button("Delete Goal", systemImage: "trash", role: .destructive) { pendingDeletion = goal }
                } label: { Image(systemName: "ellipsis").minimumTapTarget().foregroundStyle(Palette.textSecondary) }
                .accessibilityLabel("Options for \(goal.title)")
            }
            if goal.kind.isMeasurable {
                if let target = goal.target, PersonalGoalPolicy.validTarget(target, wholeNumber: goal.kind == .smokeLess) {
                    progressBlock(goal, target: target, actual: goal.kind == .smokeLess ? Double(summary.sessions) : summary.spent)
                } else {
                    Text("A valid weekly target is needed to show usage.").font(.footnote).foregroundStyle(Palette.textSecondary)
                    Button("Set a target") { editing = goal }.foregroundStyle(Palette.greenBright).minimumTapTarget()
                }
            }
            if !goal.note.isEmpty { Text(goal.note).font(.subheadline).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func progressBlock(_ goal: SeshGoal, target: Double, actual: Double) -> some View {
        let usage = PersonalGoalPolicy.usage(actual: actual, target: target) ?? 0
        let over = actual > target
        let unit = goal.kind == .smokeLess ? "sessions" : "USD"
        return VStack(alignment: .leading, spacing: 7) {
            Text("\(PersonalGoalPolicy.number(actual)) of \(PersonalGoalPolicy.number(target)) \(unit) recorded")
                .font(.subheadline.weight(.semibold)).foregroundStyle(over ? Palette.moodAngry : Palette.greenBright)
            ProgressView(value: usage).tint(over ? Palette.moodAngry : Palette.greenBright)
                .accessibilityLabel("Weekly recorded usage")
                .accessibilityValue("\(PersonalGoalPolicy.number(actual)) recorded; limit \(PersonalGoalPolicy.number(target)) \(unit)")
            Text(over ? "Above your chosen weekly limit." : "Within your chosen weekly limit.")
                .font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
}

struct AddGoalSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var editing: SeshGoal? = nil
    @State private var kind: GoalKind = .smokeLess
    @State private var title = ""
    @State private var targetText = ""
    @State private var note = ""
    @State private var baseline: String?
    @State private var confirmDiscard = false
    @State private var saving = false
    @State private var saveError: String?
    private var fingerprint: String { JournalInputPolicy.fingerprint([kind.rawValue, title, targetText, note]) }
    private var hasEdits: Bool { baseline.map { $0 != fingerprint } ?? false }
    private var target: Double? { kind.isMeasurable ? JournalInputPolicy.decimal(targetText) : nil }
    private var canSave: Bool { !saving && (!kind.isMeasurable || PersonalGoalPolicy.validTarget(target, wholeNumber: kind == .smokeLess)) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: editing == nil ? "New Goal" : "Edit Goal", onBack: { if hasEdits { confirmDiscard = true } else { dismiss() } })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("What matters to you?").font(.headline).foregroundStyle(Palette.text)
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            ForEach(GoalKind.allCases) { kindTile($0) }
                        }
                        InputField(label: "Title", placeholder: kind.rawValue, value: $title)
                        if kind.isMeasurable {
                            InputField(label: kind == .spendLess ? "Weekly limit (USD)" : "Sessions per calendar week", placeholder: "0", value: $targetText)
                                .keyboardType(.decimalPad)
                            Text(kind == .smokeLess ? "Enter a whole number, including zero." : "Use your region's decimal separator. A zero limit is allowed.")
                                .font(.footnote).foregroundStyle(Palette.textSecondary)
                            if !targetText.isEmpty && !canSave && !saving {
                                Label("Enter a complete nonnegative number\(kind == .smokeLess ? " with no fractional sessions" : "").", systemImage: "exclamationmark.circle")
                                    .font(.footnote).foregroundStyle(Palette.moodAngry)
                            }
                        }
                        NotesField(label: "Note (optional)", placeholder: "Why does this matter to you?", text: $note, minHeight: 80)
                        if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.moodAngry) }
                        PrimaryButton(title: editing == nil ? "Save Goal" : "Save Changes", icon: "checkmark") { save() }
                            .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                    }.padding(.horizontal, 18).padding(.bottom, 28).seshReadableForm()
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .seshEditorPresentation().interactiveDismissDisabled(hasEdits || saving)
        .onAppear {
            guard baseline == nil else { return }
            if let editing {
                kind = editing.kind; title = editing.title; note = editing.note
                targetText = editing.target.map { JournalInputPolicy.editableDecimal($0) } ?? ""
            }
            baseline = fingerprint
        }
        .confirmationDialog("Discard goal changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }; Button("Keep Editing", role: .cancel) { }
        }
    }
    private func kindTile(_ choice: GoalKind) -> some View {
        let selected = kind == choice
        return Button { kind = choice; Haptics.selection() } label: {
            VStack(spacing: 8) {
                HStack { Image(systemName: choice.symbol); if selected { Image(systemName: "checkmark") } }.accessibilityHidden(true)
                Text(choice.rawValue).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Palette.greenBright : Palette.textSecondary)
            .frame(maxWidth: .infinity).padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Palette.greenBright : Palette.stroke, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityLabel(choice.rawValue).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func save() {
        guard canSave else { return }
        saving = true; defer { saving = false }
        let name = JournalInputPolicy.trimmed(title)
        var value = editing ?? SeshGoal(kind: kind, title: kind.rawValue)
        value.kind = kind; value.title = name.isEmpty ? kind.rawValue : name
        value.target = target; value.unit = kind.isMeasurable ? (kind == .spendLess ? "$/week" : "sessions/week") : nil
        value.note = JournalInputPolicy.trimmed(note)
        let saved = editing == nil ? session.addGoal(value) : session.updateGoal(value, replacing: editing)
        guard saved else { saveError = session.goalStorageError; return }
        Haptics.success(); dismiss()
    }
}

// MARK: - Jokes

struct JokesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index = Int.random(in: 0..<SeshJokes.all.count)

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Dad Jokes & Giggles", onBack: { dismiss() })
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "face.smiling.inverse").font(.system(size: 40)).foregroundStyle(Palette.gold)
                Text(SeshJokes.all[index])
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { nextJoke() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Another one").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Palette.onGreen)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .background(AppBackground())
    }

    private func nextJoke() {
        var n = index
        while n == index && SeshJokes.all.count > 1 { n = Int.random(in: 0..<SeshJokes.all.count) }
        index = n
        Haptics.tap()
    }
}

enum SeshJokes {
    static let all: [String] = [
        "Why did the joint go to therapy? It had too much baggage to roll with.",
        "I told my plant a joke. It was too high to laugh.",
        "What do you call a sleepy bud? A bed-bud.",
        "Why don't stoners ever win races? They always take the scenic route.",
        "I was going to clean my grinder, but then I got too attached to the kief.",
        "What's a stoner's favorite kind of music? Anything with a good baked-line.",
        "Why did the edible bring a ladder? It heard the high was way up there.",
        "My friend asked if I wanted to hear a weed joke. I said sure, but make it dank.",
        "What do you call a happy plant? A high-bred.",
        "Why did the bong break up with the lighter? It said the spark was gone.",
        "I tried to write a joke about rolling papers, but it didn't have a good wrap.",
        "What's a strain's favorite exercise? The Indica-line crunch.",
        "Why did the cannabis go to school? To get a little higher education.",
        "What did one bud say to the other? We make a great pair.",
        "Why are stoners great gardeners? They really know how to let things grow.",
        "I asked my dealer for something uplifting. He handed me a forklift manual.",
        "What do you call a nervous joint? A little rolled up.",
        "Why did the vape go to the party? It heard things were about to heat up.",
        "What's a stoner's favorite type of weather? A high-pressure system.",
        "Why don't joints ever feel lonely? They always come around eventually.",
    ]
}

// MARK: - Community prompts / Story time

struct CommunityPromptView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: CommunityPrompt = CommunityPrompts.random()
    @State private var answer: String = ""
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Story Time", onBack: { dismiss() }) {
                Button { shuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    categoryBadge
                    Text(prompt.question)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Write your answer — it's saved to your High Thoughts...", text: $answer, axis: .vertical)
                        .lineLimit(4...10)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.text)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))

                    Button { submit() } label: {
                        Text(submitted ? "Saved to High Thoughts!" : "Save to High Thoughts")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.onGreen)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(submitted ? Palette.greenDeep : Palette.greenBright))
                    }
                    .buttonStyle(.plain)
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || submitted)

                    Button { shuffle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Different prompt").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Palette.greenBright)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Color.clear.frame(height: 20)
                }
                .padding(18)
            }
        }
        .background(AppBackground())
    }

    private var categoryBadge: some View {
        Text(prompt.category.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.greenBright)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Palette.greenDeep.opacity(0.4)))
    }

    private func shuffle() {
        var p = CommunityPrompts.random()
        var guardCount = 0
        while p.question == prompt.question && guardCount < 8 { p = CommunityPrompts.random(); guardCount += 1 }
        prompt = p; answer = ""; submitted = false
        Haptics.tap()
    }
    private func submit() {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Persist locally as a High Thought (with the prompt for context) —
        // previously the answer was silently discarded.
        session.addThought(HighThought(text: "\(prompt.question)\n\(trimmed)"))
        submitted = true
        Haptics.success()
    }
}

struct CommunityPrompt: Hashable {
    let category: String
    let question: String
}

enum CommunityPrompts {
    static func random() -> CommunityPrompt {
        let cat = categories.randomElement()!
        let q = cat.value.randomElement()!
        return CommunityPrompt(category: cat.key, question: q)
    }

    /// An extensive, categorized prompt list. Add freely.
    static let categories: [String: [String]] = [
        "Story Time": [
            "Tell us about the funniest thing that happened to you while high.",
            "What's your most memorable first-time story?",
            "Describe a sesh that turned into an adventure.",
            "What's the best conversation you've ever had while elevated?",
            "Share a time a sesh brought you closer to someone.",
            "What's the wildest place you've ever sparked up?",
            "Tell us about a sesh that didn't go as planned.",
        ],
        "Munchies": [
            "What's your ultimate munchies meal?",
            "Weirdest food combo you've ever made high — and was it good?",
            "Sweet or savory when you've got the munchies?",
            "What snack do you always keep stocked for a sesh?",
            "Describe your dream late-night munchies spread.",
            "What's a munchies creation you're secretly proud of?",
        ],
        "Strains & Taste": [
            "What strain changed the game for you?",
            "Indica, sativa, or hybrid — what's your go-to and why?",
            "Describe your perfect flavor profile in a strain.",
            "What's a strain name that always makes you laugh?",
            "If you could only smoke one strain forever, what is it?",
            "What's the most overrated strain, in your opinion?",
        ],
        "Rituals": [
            "Describe your perfect sesh setup.",
            "What's your pre-sesh ritual?",
            "Morning sesh or night sesh — which are you?",
            "What's the one thing you always need for a good sesh?",
            "Solo sesh or with friends — what's your vibe?",
            "What music is always on your sesh playlist?",
        ],
        "Deep Thoughts": [
            "What's a shower thought you had while high that blew your mind?",
            "If plants could talk, what would cannabis say?",
            "What's something you understand better after a sesh?",
            "Describe the universe in one sentence — high edition.",
            "What's a question you wish you had the answer to?",
            "What would you tell your past self about slowing down?",
        ],
        "Hot Takes": [
            "What's your most controversial sesh opinion?",
            "Joints vs blunts vs bongs — defend your pick.",
            "Is breakfast food better high? Make your case.",
            "What's a popular trend you just don't get?",
            "Rolling your own vs pre-rolls — where do you stand?",
        ],
        "This or That": [
            "Beach sesh or forest sesh?",
            "Edibles or flower?",
            "Comedy or music while you sesh?",
            "Big group or close friends?",
            "Sunrise or sunset session?",
        ],
        "Gratitude": [
            "What's something good that happened today?",
            "Who would you want to share a sesh with right now?",
            "What's a small thing you're grateful for this week?",
            "What's something you're proud of lately?",
            "What's bringing you peace right now?",
        ],
    ]
}
