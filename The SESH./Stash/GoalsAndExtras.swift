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

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Goals", onBack: { dismiss() }) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

            if session.goals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(session.goals) { goal in
                            goalCard(goal)
                        }
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showAdd) { AddGoalSheet() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "target").font(.system(size: 44)).foregroundStyle(Palette.greenBright)
            Text("Set a goal").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text("Smoke less, spend less, take a tolerance break — track what matters to you.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button { showAdd = true } label: {
                Text("Add a goal").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(Capsule().fill(Palette.greenBright))
            }
            .buttonStyle(.plain)
            Spacer(); Spacer()
        }
    }

    private func goalCard(_ goal: SeshGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: goal.kind.symbol).font(.system(size: 18)).foregroundStyle(Palette.greenBright).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(goal.kind.rawValue).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Menu {
                    Button(role: .destructive) { session.deleteGoal(goal) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Palette.textSecondary).frame(width: 30, height: 30)
                }
            }
            if goal.kind.isMeasurable, let target = goal.target, target > 0 {
                progressBlock(goal, target: target)
            }
            if !goal.note.isEmpty {
                Text(goal.note).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private func progressBlock(_ goal: SeshGoal, target: Double) -> some View {
        let actual = currentValue(for: goal)
        let ratio = min(1.5, actual / target)        // can exceed (over budget)
        let over = actual > target
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This week").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(format(actual)) / \(format(target)) \(goal.unit ?? "")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(over ? Palette.moodAngry : Palette.greenBright)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.field).frame(height: 8)
                    Capsule().fill(over ? Palette.moodAngry : Palette.greenBright)
                        .frame(width: geo.size.width * min(1.0, ratio / 1.0), height: 8)
                }
            }
            .frame(height: 8)
            Text(over ? "Over your target — ease back to hit it." : "On track. Keep it up!")
                .font(.system(size: 12)).foregroundStyle(over ? Palette.moodAngry : Palette.textSecondary)
        }
    }

    /// Pulls the real value from session data for the current week.
    private func currentValue(for goal: SeshGoal) -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        switch goal.kind {
        case .smokeLess:
            return Double(session.entries.filter { $0.date >= weekAgo }.count)
        case .spendLess:
            return session.purchases.filter { $0.date >= weekAgo }.map(\.cost).reduce(0, +)
        default:
            return 0
        }
    }
    private func format(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Add Goal sheet

struct AddGoalSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var kind: GoalKind = .smokeLess
    @State private var title = ""
    @State private var targetText = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What's your goal?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(GoalKind.allCases) { k in
                            kindTile(k)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        TextField(kind.rawValue, text: $title)
                            .textFieldStyle(.plain).foregroundStyle(Palette.text)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
                    }
                    if kind.isMeasurable {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .spendLess ? "Weekly budget ($)" : "Sessions per week")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                            TextField(kind == .spendLess ? "40" : "5", text: $targetText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note (optional)").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        TextField("Why does this matter to you?", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain).foregroundStyle(Palette.text)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
                    }
                }
                .padding(18)
            }
            .background(AppBackground())
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
        }
    }

    private func kindTile(_ k: GoalKind) -> some View {
        let isSel = kind == k
        return Button { kind = k; Haptics.selection() } label: {
            VStack(spacing: 8) {
                Image(systemName: k.symbol).font(.system(size: 20)).foregroundStyle(isSel ? Palette.greenBright : Palette.textSecondary)
                Text(k.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(isSel ? Palette.text : Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(isSel ? Palette.greenBright : Palette.stroke, lineWidth: isSel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? kind.rawValue : title
        let target = Double(targetText)
        let unit = kind == .spendLess ? "$/week" : (kind == .smokeLess ? "sessions/week" : nil)
        session.addGoal(SeshGoal(kind: kind, title: finalTitle, target: target, unit: unit, note: note))
        Haptics.success()
        dismiss()
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

                    TextField("Share your answer with the community...", text: $answer, axis: .vertical)
                        .lineLimit(4...10)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.text)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))

                    Button { submit() } label: {
                        Text(submitted ? "Shared!" : "Share")
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
        guard !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        submitted = true
        Haptics.success()
        // (Local for now; community sync can post this later via SeshAPI.)
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
