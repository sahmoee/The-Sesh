import SwiftUI

private let seshGreen = Color(red: 0.48, green: 0.84, blue: 0.62)

struct SeshWatchHome: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            Section {
                Text("Your private companion").font(.headline).foregroundStyle(seshGreen)
                if let started = store.state.timerStarted {
                    NavigationLink { WatchLogForm(timed: true) } label: {
                        VStack(alignment: .leading) { Label("Watch timer", systemImage: "timer"); Text(started, style: .timer).monospacedDigit() }
                    }
                }
                NavigationLink { WatchLogForm() } label: { Label("Log a sesh", systemImage: "plus.circle.fill") }
                NavigationLink { WatchLogForm(startTimer: true) } label: { Label("Start watch timer", systemImage: "timer") }
                    .disabled(store.state.timerStarted != nil)
                NavigationLink { WatchThoughtForm() } label: { Label("Private thought", systemImage: "text.bubble") }
            }
            Section("Your week") {
                if let snapshot = store.state.snapshot, snapshot.enabled {
                    LabeledContent("Sessions", value: String(snapshot.weeklySessions))
                    LabeledContent("Stash spend", value: snapshot.weeklySpend.formatted(.currency(code: "USD")))
                    if let started = snapshot.phoneSessionStarted {
                        VStack(alignment: .leading) { Text("iPhone session active").font(.headline); Text(snapshot.phoneSessionStrain ?? "Session"); Text(started, style: .timer); Text("Finish it on iPhone to avoid a second log.").font(.footnote).foregroundStyle(.secondary) }
                    }
                } else { Text("Sync with iPhone for your private journal.").font(.footnote) }
            }
            Section {
                NavigationLink { WatchHistory() } label: { Label("Journal", systemImage: "book.closed") }
                NavigationLink { WatchThoughts() } label: { Label("Thoughts", systemImage: "text.bubble") }
                NavigationLink { WatchStash() } label: { Label("Stash", systemImage: "shippingbox") }
                NavigationLink { WatchStrains() } label: { Label("Strains", systemImage: "leaf") }
                NavigationLink { WatchGoals() } label: { Label("Personal goals", systemImage: "target") }
                NavigationLink { WatchSettings() } label: { Label("Sync & settings", systemImage: "gearshape") }
            }
            Section {
                Text(store.status).font(.footnote).foregroundStyle(.secondary)
                if !store.state.pending.isEmpty { NavigationLink("\(store.state.pending.count) pending actions") { WatchQueue() } }
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
        }.navigationTitle("The SESH.")
    }
}

struct WatchLogForm: View {
    @EnvironmentObject private var store: SeshWatchStore
    @Environment(\.dismiss) private var dismiss
    var timed = false
    var startTimer = false
    var strain: String? = nil
    var purchase: SeshWatchStash? = nil
    @State private var draft = SeshWatchLog()
    @State private var amount = ""
    @State private var loaded = false
    @State private var moodShift = false
    @State private var error: String?
    @State private var confirmDiscard = false
    private var candidate: SeshWatchLog {
        var result = draft
        result.amount = amount.isEmpty ? nil : SeshWatchContract.decimal(amount)
        if !moodShift { result.moodBefore = nil; result.moodAfter = nil }
        if timed, let began = store.state.timerStarted {
            result.date = began; result.durationMinutes = max(1, Int(ceil(Double(SeshWatchContract.elapsed(start: began)) / 60)))
        }
        return result
    }
    private var linkedPurchase: SeshWatchStash? {
        guard let id = draft.purchaseID else { return nil }
        return purchase?.id == id ? purchase : store.state.snapshot?.stash.first { $0.id == id }
    }
    private var hasStashLink: Bool { draft.purchaseID != nil }
    private var validAmount: Bool { amount.isEmpty || SeshWatchContract.decimal(amount).map { $0 > 0 && $0 <= 100_000 } == true }
    var body: some View {
        Form {
            Section {
                if timed, let began = store.state.timerStarted { Text(began, style: .timer).font(.title2).monospacedDigit(); Text("Review and save to finish the watch timer.").font(.footnote) }
                TextField("Strain", text: $draft.strain).textContentType(.none)
                Picker("Method", selection: $draft.method) { ForEach(SeshWatchContract.methods, id: \.self) { Text($0) } }
                Picker("Mood", selection: Binding(get: { draft.mood ?? "Not recorded" }, set: { draft.mood = $0 == "Not recorded" ? nil : $0 })) {
                    Text("Not recorded").tag("Not recorded"); ForEach(SeshWatchContract.moods, id: \.self) { Text($0) }
                }
                TextField("Amount (optional)", text: $amount)
                Picker("Unit", selection: $draft.unit) { ForEach(SeshWatchContract.units, id: \.self) { Text($0) } }.disabled(hasStashLink)
                if !validAmount { Text("Use a complete positive amount, such as 0.5.").font(.footnote).foregroundStyle(.orange) }
                if let purchase = linkedPurchase { Text("Deducts this amount from \(purchase.strain) on iPhone after save. Remaining: \(purchase.remaining.formatted()) \(purchase.unit). A changed stash will require review.").font(.footnote) }
                if hasStashLink {
                    if linkedPurchase == nil { Text("Linked stash is outside this offline copy. iPhone will verify the linked stash when you save.").font(.footnote).foregroundStyle(.orange) }
                    Button("Unlink stash deduction") { draft.purchaseID = nil }
                }
                Stepper("Rating: \(Int(draft.rating))/10", value: $draft.rating, in: 1...10, step: 1)
                DatePicker("When", selection: $draft.date, displayedComponents: [.date, .hourAndMinute]).disabled(timed)
                Toggle("Record mood change", isOn: $moodShift)
                if moodShift {
                    moodPicker("Before", value: Binding(get: { draft.moodBefore ?? 2 }, set: { draft.moodBefore = $0 }))
                    moodPicker("After", value: Binding(get: { draft.moodAfter ?? 2 }, set: { draft.moodAfter = $0 }))
                }
                TextField("Private notes", text: $draft.notes, axis: .vertical).lineLimit(3...6).privacySensitive()
                Picker("Session tag", selection: Binding(get: { draft.tags.first ?? "None" }, set: { draft.tags = $0 == "None" ? [] : [$0] })) {
                    ForEach(["None", "Relaxing", "Creative", "Gaming", "Movie Night", "Productive", "Social", "Other"], id: \.self) { Text($0) }
                }
            }
            Section {
                Button(startTimer ? "Start private timer" : "Save private log") {
                    do {
                        let value = candidate; try value.validate()
                        guard validAmount else { throw SeshWatchError.invalid("Review the amount.") }
                        if startTimer { store.startTimer(value); if store.state.timerStarted != nil { dismiss() } }
                        else if store.log(value) { dismiss() }
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(store.state.snapshot?.enabled != true || !validAmount)
                Text("Saved first in the watch queue, then confirmed by iPhone. No community post.").font(.footnote).foregroundStyle(.secondary)
                if timed { Button("Discard watch timer", role: .destructive) { confirmDiscard = true } }
                if let error = error ?? store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
        }.navigationTitle(startTimer ? "Start session" : "Log session")
        .onAppear {
            guard !loaded else { return }; draft = store.state.draft
            if let strain { draft.strain = strain; draft.purchaseID = nil; draft.amount = nil }
            if let purchase { draft.strain = purchase.strain; draft.purchaseID = purchase.id; draft.unit = purchase.unit }
            amount = strain == nil && purchase == nil ? store.state.amountDraft : draft.amount.map { $0.formatted(.number.grouping(.never)) } ?? ""
            moodShift = draft.moodBefore != nil || draft.moodAfter != nil; loaded = true
        }
        .onChange(of: draft) { _, value in if loaded { store.draft(value, rawAmount: amount) } }
        .onChange(of: amount) { _, text in
            if validAmount { draft.amount = text.isEmpty ? nil : SeshWatchContract.decimal(text) }
            if loaded { store.draft(draft, rawAmount: text) }
        }
        .onChange(of: moodShift) { _, value in if value { draft.moodBefore = draft.moodBefore ?? 2; draft.moodAfter = draft.moodAfter ?? 2 } else { draft.moodBefore = nil; draft.moodAfter = nil } }
        .confirmationDialog("Discard the unsaved watch timer?", isPresented: $confirmDiscard) { Button("Discard timer", role: .destructive) { store.discardTimer(); dismiss() } }
    }
    private func moodPicker(_ title: String, value: Binding<Int>) -> some View {
        Picker(title, selection: value) { ForEach(Array(["Rough", "Meh", "Okay", "Good", "Great"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }
    }
}

struct WatchHistory: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            NavigationLink("Browse all \(store.state.snapshot?.totalEntries ?? 0) entries") { WatchBrowse(area: .history) }
            Section("Recent offline copy") {
                ForEach(store.state.snapshot?.entries ?? []) { entry in NavigationLink { WatchEntryDetail(initial: entry) } label: { entryLabel(entry) } }
                if store.state.snapshot?.entries.isEmpty != false { Text("No saved entries in this copy. Log a sesh or sync with iPhone.").font(.footnote) }
            }
        }.navigationTitle("Journal")
    }
}
private func entryLabel(_ entry: SeshWatchEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack { Text(entry.log.strain).font(.headline); if entry.favorite { Image(systemName: "star.fill").foregroundStyle(seshGreen).accessibilityLabel("Favorite") }; if entry.pinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") } }
        Text(entry.log.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption)
        Text("\(entry.log.method) · \(entry.log.rating.formatted())/10").font(.caption).foregroundStyle(.secondary)
    }
}
struct WatchEntryDetail: View {
    @EnvironmentObject private var store: SeshWatchStore
    let initial: SeshWatchEntry
    private var entry: SeshWatchEntry { store.page?.entries.first { $0.id == initial.id } ?? store.state.snapshot?.entries.first { $0.id == initial.id } ?? initial }
    private var waiting: Bool { store.state.pending.contains { $0.command.recordID == entry.id } }
    var body: some View {
        List {
            entryLabel(entry)
            if let amount = entry.log.amount { LabeledContent("Amount", value: "\(amount.formatted()) \(entry.log.unit)") }
            if let mood = entry.log.mood { LabeledContent("Mood", value: mood) }
            if let minutes = entry.log.durationMinutes { LabeledContent("Duration", value: "\(minutes) min") }
            if let before = entry.log.moodBefore, let after = entry.log.moodAfter { Text("Mood before: \(before)/4 · after: \(after)/4") }
            if !entry.log.notes.isEmpty { Text(store.state.hidePrivateText ? "Private notes hidden" : entry.log.notes).privacySensitive() }
            Button(entry.favorite ? "Remove favorite" : "Favorite") { store.setFlag(.favorite, id: entry.id, value: !entry.favorite) }.disabled(waiting)
            Button(entry.pinned ? "Unpin from Studio" : "Pin in Journal Studio") { store.setFlag(.pin, id: entry.id, value: !entry.pinned) }.disabled(waiting)
            if waiting { Label("Change awaiting iPhone", systemImage: "clock").font(.footnote) }
            NavigationLink("Log this strain again") { WatchLogForm(strain: entry.log.strain) }
            Text("Edit full notes, media and notebooks in Journal Studio on iPhone.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Session").privacySensitive()
    }
}
struct WatchThoughtForm: View {
    @EnvironmentObject private var store: SeshWatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        Form {
            TextField("Private thought", text: $text, axis: .vertical).lineLimit(4...10)
            Text("\(text.count)/2,000 characters").font(.footnote)
            Button("Save privately") { if store.saveThought(text) { dismiss() } }.buttonStyle(.borderedProminent)
                .disabled(store.state.snapshot?.enabled != true || !SeshWatchContract.text(text, maximum: 2_000, required: true))
            Text("Stored in your journal, never posted to Community.").font(.footnote)
            if let error = store.error { Text(error).foregroundStyle(.orange).font(.footnote) }
        }.navigationTitle("Thought").privacySensitive()
        .onAppear { text = store.state.thoughtDraft }
        .onChange(of: text) { _, value in store.thoughtDraft(value) }
    }
}
struct WatchThoughts: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            NavigationLink("New private thought") { WatchThoughtForm() }
            NavigationLink("Browse all thoughts") { WatchBrowse(area: .thoughts) }
            ForEach(store.state.snapshot?.thoughts ?? []) { row in thoughtLabel(row, hidden: store.state.hidePrivateText) }
        }.navigationTitle("Thoughts").privacySensitive()
    }
}
private func thoughtLabel(_ row: SeshWatchThought, hidden: Bool) -> some View {
    VStack(alignment: .leading) { Text(row.date, style: .date).font(.caption).foregroundStyle(.secondary); Text(hidden ? "Private thought hidden" : row.text) }
}
struct WatchStash: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            NavigationLink("Add stash record") { WatchStashForm() }
            NavigationLink("Browse all stash") { WatchBrowse(area: .stash) }
            ForEach(store.state.snapshot?.stash ?? []) { row in NavigationLink { WatchStashDetail(row: row) } label: { stashLabel(row) } }
            if store.state.snapshot?.stash.isEmpty != false { Text("Add a purchase or sync your iPhone stash.").font(.footnote) }
        }.navigationTitle("Stash")
    }
}
private func stashLabel(_ row: SeshWatchStash) -> some View {
    VStack(alignment: .leading) { Text(row.strain).font(.headline); Text("\(row.remaining.formatted()) \(row.unit) left").font(.caption).foregroundStyle(.secondary) }
}
struct WatchStashDetail: View {
    let row: SeshWatchStash
    var body: some View {
        List {
            stashLabel(row)
            LabeledContent("Bought", value: "\(row.amount.formatted()) \(row.unit)")
            LabeledContent("Cost", value: row.cost.formatted(.currency(code: "USD")))
            Text(row.date, style: .date)
            if SeshWatchContract.units.contains(row.unit), row.remaining > 0 {
                NavigationLink("Log from this stash") { WatchLogForm(purchase: row) }
            } else { Text("Use iPhone to log or adjust this stash unit.").font(.footnote) }
        }.navigationTitle("Stash detail")
    }
}
struct WatchStashForm: View {
    @EnvironmentObject private var store: SeshWatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var cost = ""
    @State private var unit = "g"
    var body: some View {
        Form {
            TextField("Strain", text: $name); TextField("Amount bought", text: $amount)
            Picker("Unit", selection: $unit) { ForEach(SeshWatchContract.units, id: \.self) { Text($0) } }
            TextField("Cost (USD)", text: $cost)
            Button("Save stash") {
                guard let quantity = SeshWatchContract.decimal(amount), let price = SeshWatchContract.decimal(cost) else { store.error = "Enter complete amount and cost values."; return }
                if store.saveStash(SeshWatchStash(id: UUID(), strain: name, amount: quantity, used: 0, unit: unit, cost: price, date: Date())) { dismiss() }
            }.buttonStyle(.borderedProminent).disabled(store.state.snapshot?.enabled != true)
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.navigationTitle("Add stash")
        .onAppear { let saved = store.state.stashDraft; name = saved.name; amount = saved.amount; cost = saved.cost; unit = saved.unit }
        .onChange(of: [name, amount, cost, unit]) { _, _ in store.stashDraft(SeshWatchStashDraft(name: name, amount: amount, cost: cost, unit: unit)) }
    }
}
struct WatchStrains: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            NavigationLink("Search all \(store.state.snapshot?.totalStrains ?? 0) strains") { WatchBrowse(area: .strains) }
            Section("In your recent journal & stash") {
                ForEach(store.state.snapshot?.strains ?? []) { row in NavigationLink(row.name) { WatchStrainDetail(row: row) } }
                if store.state.snapshot?.strains.isEmpty != false { Text("Search the iPhone catalog or type a strain while logging.").font(.footnote) }
            }
        }.navigationTitle("Strains")
    }
}
struct WatchStrainDetail: View {
    let row: SeshWatchStrain
    var body: some View {
        List {
            Text(row.name).font(.headline); Text(row.type)
            if let thc = row.thc { LabeledContent("THC", value: "\(thc.formatted())%") }
            if let cbd = row.cbd { LabeledContent("CBD", value: "\(cbd.formatted())%") }
            if !row.detail.isEmpty { Text(row.detail).font(.footnote) }
            NavigationLink("Log this strain") { WatchLogForm(strain: row.name) }
            Text("Catalog descriptions are reference information, not a prediction of your experience.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Strain")
    }
}
struct WatchGoals: View {
    @EnvironmentObject private var store: SeshWatchStore
    var body: some View {
        List {
            NavigationLink("Add personal goal") { WatchGoalForm() }
            NavigationLink("Browse all goals") { WatchBrowse(area: .goals) }
            ForEach(store.state.snapshot?.goals ?? []) { row in NavigationLink(row.title) { WatchGoalDetail(row: row) } }
            if store.state.snapshot?.goals.isEmpty != false { Text("Set your own limits or intentions. No health outcome is predicted.").font(.footnote) }
        }.navigationTitle("Goals")
    }
}
struct WatchGoalDetail: View {
    @EnvironmentObject private var store: SeshWatchStore
    let row: SeshWatchGoal
    private var current: SeshWatchGoal { store.page?.goals.first { $0.id == row.id } ?? store.state.snapshot?.goals.first { $0.id == row.id } ?? row }
    var body: some View {
        let row = current
        List {
            Text(row.title).font(.headline); Text(row.kind); Text(row.active ? "Active" : "Paused").foregroundStyle(seshGreen)
            if let actual = row.actual, let target = row.target {
                Text("This week: \(actual.formatted()) of \(target.formatted()) \(row.kind == "Spend less" ? "USD" : "sessions")")
                ProgressView(value: target == 0 ? (actual == 0 ? 0 : 1) : min(1, actual / target)).accessibilityLabel("Recorded usage against personal weekly limit")
                Text(actual > target ? "Above your chosen weekly limit." : "Within your chosen weekly limit.").font(.footnote)
            }
            if !row.note.isEmpty { Text(store.state.hidePrivateText ? "Private goal note hidden" : row.note).privacySensitive() }
            Button(row.active ? "Pause goal" : "Resume goal") { store.setFlag(.goalActive, id: row.id, value: !row.active) }
                .disabled(store.state.pending.contains { $0.command.recordID == row.id })
            Text("Edit targets and review your full progress on iPhone.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Personal goal")
    }
}
struct WatchGoalForm: View {
    @EnvironmentObject private var store: SeshWatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "Custom"
    @State private var target = ""
    @State private var note = ""
    var body: some View {
        Form {
            TextField("Goal name", text: $title)
            Picker("Kind", selection: $kind) { ForEach(["Custom", "Smoke less", "Spend less", "Tolerance break", "Sleep better", "Be more present"], id: \.self) { Text($0) } }
            if kind == "Smoke less" || kind == "Spend less" { TextField(kind == "Smoke less" ? "Sessions per week" : "USD per week", text: $target) }
            TextField("Personal note", text: $note, axis: .vertical)
            Button("Save goal") {
                let number = kind == "Smoke less" || kind == "Spend less" ? SeshWatchContract.decimal(target) : nil
                if store.saveGoal(SeshWatchGoal(id: UUID(), title: title, kind: kind, target: number, actual: nil, note: note, active: true)) { dismiss() }
            }.buttonStyle(.borderedProminent).disabled(store.state.snapshot?.enabled != true)
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.navigationTitle("New goal")
        .onAppear { let saved = store.state.goalDraft; title = saved.title; kind = saved.kind; target = saved.target; note = saved.note }
        .onChange(of: [title, kind, target, note]) { _, _ in store.goalDraft(SeshWatchGoalDraft(title: title, kind: kind, target: target, note: note)) }
    }
}
struct WatchBrowse: View {
    @EnvironmentObject private var store: SeshWatchStore
    let area: SeshWatchPageRequest.Area
    @State private var query = ""
    var body: some View {
        List {
            TextField("Search \(area.rawValue)", text: $query).submitLabel(.search).onSubmit { store.browse(area, query: query) }
            Button("Search iPhone") { store.browse(area, query: query) }.disabled(store.loadingPage)
            if store.loadingPage { ProgressView("Loading page") }
            if let page = store.page, page.request.area == area {
                Text("\(page.total) matches · page \(page.request.offset / 20 + 1)").font(.footnote).foregroundStyle(.secondary)
                ForEach(page.entries) { row in NavigationLink { WatchEntryDetail(initial: row) } label: { entryLabel(row) } }
                ForEach(page.strains) { row in NavigationLink(row.name) { WatchStrainDetail(row: row) } }
                ForEach(page.stash) { row in NavigationLink { WatchStashDetail(row: row) } label: { stashLabel(row) } }
                ForEach(page.goals) { row in NavigationLink(row.title) { WatchGoalDetail(row: row) } }
                ForEach(page.thoughts) { row in thoughtLabel(row, hidden: store.state.hidePrivateText) }
                if page.request.offset > 0 { Button("Previous 20") { store.browse(area, query: page.request.query, offset: max(0, page.request.offset - 20)) } }
                if let next = page.nextOffset { Button("Next 20") { store.browse(area, query: page.request.query, offset: next) } }
                if page.total == 0 { Text("No matches. Try a shorter search.").font(.footnote) }
            }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.navigationTitle("Browse \(area.rawValue)").onAppear { if store.page?.request.area != area { store.browse(area, query: query) } }
    }
}
struct WatchQueue: View {
    @EnvironmentObject private var store: SeshWatchStore
    @State private var removeID: UUID?
    var body: some View {
        List {
            Text("Only “Saved privately on iPhone” confirms a durable journal save. Queued actions survive watch restarts.").font(.footnote)
            Button("Retry pending actions") { store.retryPending(); store.sync() }
            ForEach(store.state.pending) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.command.kind.rawValue.capitalized).font(.headline)
                    Text(row.command.createdAt, style: .date).font(.caption)
                    if let id = row.command.recordID {
                        Text(store.state.snapshot?.entries.first { $0.id == id }?.log.strain ?? store.state.snapshot?.goals.first { $0.id == id }?.title ?? "Record \(id.uuidString)")
                        if let flag = row.command.flag { Text(flag ? "Requested state: on" : "Requested state: off").font(.caption) }
                    }
                    if let log = row.command.log { Text(log.strain); Text("\(log.method) · \(log.rating.formatted())/10"); if let amount = log.amount { Text("\(amount.formatted()) \(log.unit)") }; if log.purchaseID != nil { Text("Includes stash deduction").font(.caption) }; if !log.notes.isEmpty { Text(store.state.hidePrivateText ? "Private notes hidden" : log.notes).privacySensitive() } }
                    if let text = row.command.text { Text(store.state.hidePrivateText ? "Private thought hidden" : text).privacySensitive() }
                    if let goal = row.command.goal { Text(goal.title); Text(goal.kind); if let target = goal.target { Text("Target: \(target.formatted())") }; if !goal.note.isEmpty { Text(store.state.hidePrivateText ? "Private note hidden" : goal.note) } }
                    if let stash = row.command.stash { Text(stash.strain); Text("\(stash.amount.formatted()) \(stash.unit) · \(stash.cost.formatted(.currency(code: "USD")))") }
                    Button("Remove from queue", role: .destructive) { removeID = row.id }
                    Text(row.message ?? "Waiting for iPhone acknowledgement").font(.footnote).foregroundStyle(row.message == nil ? Color.secondary : Color.orange)
                }
            }
            if store.state.pending.isEmpty { Label("No pending actions", systemImage: "checkmark.circle") }
        }.navigationTitle("Pending").privacySensitive()
        .confirmationDialog("Remove this queued action? An already-delivered action may still save. Check iPhone history before creating it again.", isPresented: Binding(get: { removeID != nil }, set: { if !$0 { removeID = nil } }), titleVisibility: .visible) {
            Button("Remove action", role: .destructive) { if let id = removeID { store.dismissPending(id) }; removeID = nil }
        }
    }
}
struct WatchSettings: View {
    @EnvironmentObject private var store: SeshWatchStore
    @State private var erase = false
    var body: some View {
        List {
            Label(store.reachable ? "iPhone reachable" : "Offline copy", systemImage: store.reachable ? "iphone" : "wifi.slash")
            if let snapshot = store.state.snapshot { Text("Copy updated \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote) }
            if store.syncing { ProgressView("Syncing") }
            Button("Refresh from iPhone") { store.sync() }.disabled(store.syncing)
            NavigationLink("Pending: \(store.state.pending.count)") { WatchQueue() }
            Toggle("Haptics", isOn: Binding(get: { store.state.haptics }, set: { store.preference(haptics: $0) }))
            Toggle("Hide private text", isOn: Binding(get: { store.state.hidePrivateText }, set: { store.preference(hideText: $0) }))
            Button("Retry reading saved data") { store.reload() }
            Text("Community, music, photo imports, full note editing and notebooks are available on iPhone. Open The SESH. there; no remote action has been taken.").font(.footnote)
            Text("Personal recording for adults. No medical advice or suggested dose.").font(.footnote)
            Text(store.status).font(.footnote)
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange) }
            Button("Erase watch copy", role: .destructive) { erase = true }
        }.navigationTitle("Settings").confirmationDialog("Erase local cache, draft and pending actions? Already-sent actions may still save on iPhone. Saved iPhone data is unchanged.", isPresented: $erase, titleVisibility: .visible) {
            Button("Erase watch copy", role: .destructive) { store.eraseLocalCopy() }
        }
    }
}
