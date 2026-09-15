import SwiftUI
import UniformTypeIdentifiers

/// A private workspace for organizing and reflecting on existing journal entries.
struct JournalStudioView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var store = JournalStudioStore.shared
    @State private var filter = JournalStudioFilter()
    @State private var mode = "Browse"
    @State private var name = ""
    @State private var namingNotebook = false
    @State private var showName = false
    @State private var message: String?
    @State private var editing: JournalEntry?
    @State private var reflecting: JournalEntry?
    @State private var comparison: [UUID] = []
    @State private var showExportOptions = false
    @State private var includeNotes = false
    @State private var exportDocument: JournalCSVDocument?
    @State private var exporting = false
    @State private var deleteNotebook: JournalNotebook?

    private var methods: [String] { Set(session.entries.map(\.method).filter { !$0.isEmpty }).sorted() }
    private var matching: [JournalEntry] {
        let members = filter.notebookID.flatMap { id in store.snapshot.notebooks.first { $0.id == id }?.entryIDs }
        let now = Date()
        return session.entries.filter { entry in
            JournalStudioPolicy.includes(entry.date, days: filter.days, now: now) &&
            (filter.method.isEmpty || entry.method == filter.method) &&
            (!filter.pinnedOnly || store.snapshot.pinned.contains(entry.id)) &&
            (filter.notebookID == nil || members?.contains(entry.id) == true) &&
            JournalInputPolicy.matches(filter.query, fields: [entry.strain, entry.notes, entry.method] + (entry.effects ?? []) + (entry.sessionTags ?? []))
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    private var pending: [(JournalEntry, JournalReflection)] {
        let byID = Dictionary(session.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return store.snapshot.reflections.compactMap { reflection in
            guard reflection.completedAt == nil, reflection.dueAt != nil, let entry = byID[reflection.id] else { return nil }
            return (entry, reflection)
        }.sorted { ($0.1.dueAt ?? .distantFuture) < ($1.1.dueAt ?? .distantFuture) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Journal Studio", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Private tools · stored on this device", systemImage: "lock.shield")
                            .font(.seshScaled(13)).foregroundStyle(Palette.textSecondary)
                        if let error = store.error {
                            studioCard {
                                Text(error).foregroundStyle(Palette.text)
                                Button("Try reading again") { store.load() }.minimumTapTarget()
                            }
                        }
                        modePicker
                        switch mode {
                        case "Reflect": reflectionInbox
                        case "Compare": comparisonContent
                        case "Review": duplicateReview
                        default: browse
                        }
                    }
                    .font(.seshScaled(15)).padding(18).seshReadableForm()
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarBackButtonHidden(true)
        .tint(Palette.green)
        .onChange(of: session.entries.map(\.id)) { _, ids in
            let existing = Set(ids)
            comparison.removeAll { !existing.contains($0) }
        }
        .toast($message)
        .sheet(item: $editing) { LogSeshView(editing: $0).environment(session) }
        .sheet(item: $reflecting) { entry in
            JournalReflectionEditor(entry: entry, store: store).environment(session)
        }
        .alert(namingNotebook ? "New notebook" : "Save this view", isPresented: $showName) {
            TextField("Name", text: $name)
            Button("Save") { saveName() }
            Button("Cancel", role: .cancel) { name = "" }
        } message: { Text("Choose a unique name of up to 60 characters.") }
        .confirmationDialog("Remove notebook?", isPresented: Binding(get: { deleteNotebook != nil }, set: { if !$0 { deleteNotebook = nil } }), titleVisibility: .visible) {
            Button("Remove notebook", role: .destructive) {
                guard let notebook = deleteNotebook else { return }
                if store.change({ snapshot in
                    snapshot.notebooks.removeAll { $0.id == notebook.id }
                    for index in snapshot.savedViews.indices where snapshot.savedViews[index].filter.notebookID == notebook.id {
                        snapshot.savedViews[index].filter.notebookID = nil
                    }
                }) {
                    if filter.notebookID == notebook.id { filter.notebookID = nil }
                    message = "Notebook removed. Your journal entries are unchanged."
                }
                deleteNotebook = nil
            }
        } message: { Text("Only this notebook's grouping is removed. Its journal entries remain in your journal.") }
        .sheet(isPresented: $showExportOptions, onDismiss: {
            if exportDocument != nil { exporting = true }
        }) { exportOptions }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "Sesh-Journal-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: message = "Journal CSV exported."
            case .failure: message = "Export did not finish. Your journal is unchanged; try exporting again."
            }
            exportDocument = nil
        }
    }

    private var modePicker: some View {
        FlowLayout(spacing: 8) {
            ForEach(["Browse", "Reflect", "Compare", "Review"], id: \.self) { item in
                Button { mode = item; Haptics.selection() } label: {
                    HStack(spacing: 6) {
                        if mode == item { Image(systemName: "checkmark") }
                        Text(item)
                    }
                    .font(.seshScaled(14, weight: .semibold))
                    .foregroundStyle(mode == item ? Palette.onGreen : Palette.text)
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                    .background(Capsule().fill(mode == item ? Palette.green : Palette.field))
                }
                .buttonStyle(.plain).accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 16) {
            studioCard {
                TextField("Search sessions, notes, and effects", text: $filter.query)
                    .font(.seshScaled(15)).textFieldStyle(.plain).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).submitLabel(.search)
                    .accessibilityLabel("Search journal studio").frame(minHeight: 44)
                Picker("Date range", selection: $filter.days) {
                    Text("All time").tag(0); Text("Today").tag(1)
                    Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90)
                }
                Picker("Method", selection: $filter.method) {
                    Text("Any method").tag("")
                    ForEach(methods, id: \.self) { Text($0).tag($0) }
                    if !filter.method.isEmpty && !methods.contains(filter.method) { Text("\(filter.method) (not in journal)").tag(filter.method) }
                }
                Picker("Notebook", selection: $filter.notebookID) {
                    Text("All notebooks").tag(nil as UUID?)
                    ForEach(store.snapshot.notebooks) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Pinned sessions only", isOn: $filter.pinnedOnly)
                FlowLayout(spacing: 12) {
                    Button("Save view", systemImage: "bookmark") { name = ""; namingNotebook = false; showName = true }.minimumTapTarget()
                    Button("New notebook", systemImage: "folder.badge.plus") { name = ""; namingNotebook = true; showName = true }.minimumTapTarget()
                    if filter != JournalStudioFilter() {
                        Button("Reset filters", systemImage: "arrow.counterclockwise") { filter = JournalStudioFilter() }.minimumTapTarget()
                    }
                }
            }
            savedViews
            if let id = filter.notebookID, let notebook = store.snapshot.notebooks.first(where: { $0.id == id }) {
                Button("Remove “\(notebook.name)” notebook", role: .destructive) { deleteNotebook = notebook }.minimumTapTarget()
            }
            let results = matching
            HStack {
                Text("\(results.count) \(results.count == 1 ? "session" : "sessions")").font(.seshScaled(13)).foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Export CSV", systemImage: "square.and.arrow.up") { includeNotes = false; showExportOptions = true }
                    .minimumTapTarget().disabled(results.isEmpty)
            }
            if results.isEmpty {
                EmptyStateView(icon: "line.3.horizontal.decrease", title: "No sessions here yet", message: "Change the filters, or add existing sessions to this notebook from their menu.", actionTitle: "Show all sessions", actionIcon: "arrow.counterclockwise", action: { filter = JournalStudioFilter() })
            } else {
                LazyVStack(spacing: 12) { ForEach(results) { entry in entryRow(entry) } }
            }
        }
    }

    private var savedViews: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.snapshot.savedViews.isEmpty {
                Text("Saved views").font(.seshScaled(14, weight: .semibold))
                ForEach(store.snapshot.savedViews) { saved in
                    HStack(alignment: .top) {
                        Button { filter = saved.filter; mode = "Browse" } label: {
                            Label(saved.name, systemImage: "bookmark").frame(maxWidth: .infinity, alignment: .leading).minimumTapTarget()
                        }.buttonStyle(.plain).foregroundStyle(Palette.text)
                        Button { store.change { $0.savedViews.removeAll { $0.id == saved.id } } } label: {
                            Image(systemName: "minus.circle").minimumTapTarget()
                        }.accessibilityLabel("Remove saved view \(saved.name)")
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        studioCard {
            HStack(alignment: .top, spacing: 12) {
                Button { editing = entry } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.strain.isEmpty ? "Untitled session" : entry.strain).font(.seshScaled(17, weight: .semibold))
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.seshScaled(12)).foregroundStyle(Palette.textSecondary)
                        Text(entry.method.isEmpty ? "Method not recorded" : entry.method).font(.seshScaled(13)).foregroundStyle(Palette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(Palette.text).accessibilityHint("Edit this session")
                Button { store.togglePin(entry.id) } label: {
                    Image(systemName: store.snapshot.pinned.contains(entry.id) ? "pin.fill" : "pin").minimumTapTarget()
                }.accessibilityLabel(store.snapshot.pinned.contains(entry.id) ? "Unpin \(entry.strain)" : "Pin \(entry.strain)")
                Menu {
                    Button("Reflect or plan a follow-up", systemImage: "text.bubble") { reflecting = entry }
                    Button(comparison.contains(entry.id) ? "Remove from comparison" : "Compare this session", systemImage: "rectangle.split.2x1") { selectComparison(entry.id) }
                    if !store.snapshot.notebooks.isEmpty {
                        Section("Notebooks") {
                            ForEach(store.snapshot.notebooks) { notebook in
                                Button { store.toggleMembership(entry.id, notebook: notebook.id) } label: {
                                    Label(notebook.name, systemImage: notebook.entryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle").minimumTapTarget() }
                .accessibilityLabel("Options for \(entry.strain)")
            }
            FlowLayout(spacing: 8) {
                Text("\(entry.rating.formatted(.number.precision(.fractionLength(0...1)))) / 10")
                ForEach(store.snapshot.notebooks.filter { $0.entryIDs.contains(entry.id) }) { notebook in Label(notebook.name, systemImage: "folder") }
                if comparison.contains(entry.id) { Label("In comparison", systemImage: "checkmark.circle") }
                if let reflection = store.snapshot.reflections.first(where: { $0.id == entry.id }), !reflection.text.isEmpty { Label("Reflection saved", systemImage: "text.bubble") }
            }.font(.seshScaled(12)).foregroundStyle(Palette.textSecondary)
        }
    }

    private var reflectionInbox: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reflection inbox").font(.seshScaled(22, weight: .bold, design: .serif))
            Text("Choose a session's menu to set a follow-up or capture what you noticed. Dates appear here; these are not push notifications.")
                .foregroundStyle(Palette.textSecondary)
            if pending.isEmpty { Text("No pending follow-ups.").foregroundStyle(Palette.textSecondary) }
            ForEach(pending, id: \.0.id) { entry, reflection in
                studioCard {
                    Text(entry.strain).font(.seshScaled(17, weight: .semibold))
                    if let due = reflection.dueAt {
                        Label(due <= Date() ? "Ready to reflect" : "Upcoming", systemImage: due <= Date() ? "clock.badge.checkmark" : "calendar")
                        Text(due.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Palette.textSecondary)
                    }
                    Button("Open reflection") { reflecting = entry }.minimumTapTarget()
                }
            }
            let completed = store.snapshot.reflections.filter { !$0.text.isEmpty || $0.completedAt != nil }
            if !completed.isEmpty {
                Text("Saved reflections").font(.seshScaled(18, weight: .semibold))
                ForEach(completed) { reflection in
                    if let entry = session.entries.first(where: { $0.id == reflection.id }) {
                        Button { reflecting = entry } label: {
                            studioCard {
                                Text(entry.strain).font(.seshScaled(16, weight: .semibold))
                                Text(reflection.text.isEmpty ? "Follow-up completed" : reflection.text).foregroundStyle(Palette.textSecondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var comparisonContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compare two sessions").font(.seshScaled(22, weight: .bold, design: .serif))
            Text("Choose two sessions from Browse to compare your recorded experience. Differences describe your own notes, not a prediction.").foregroundStyle(Palette.textSecondary)
            let selected = comparison.compactMap { id in session.entries.first { $0.id == id } }
            ForEach(selected) { entry in
                studioCard {
                    Text(entry.strain).font(.seshScaled(18, weight: .semibold))
                    detail("Date", entry.date.formatted(date: .abbreviated, time: .shortened))
                    detail("Method", entry.method.isEmpty ? "Not recorded" : entry.method)
                    detail("Rating", "\(entry.rating.formatted()) / 10")
                    detail("Amount", entry.amountLine ?? "Not recorded")
                    detail("Duration", entry.durationMinutes.map { "\($0) minutes" } ?? "Not recorded")
                    detail("Mood before / after", "\(entry.moodBefore.map(String.init) ?? "—") / \(entry.moodAfter.map(String.init) ?? "—")")
                    detail("Effects", entry.effects?.joined(separator: ", ").nonEmpty ?? "Not recorded")
                    detail("Notes", entry.notes.isEmpty ? "Not recorded" : entry.notes)
                    Button("Remove from comparison") { comparison.removeAll { $0 == entry.id } }.minimumTapTarget()
                }
            }
            if selected.count == 2 {
                Text("Rating difference: \(abs(selected[0].rating - selected[1].rating).formatted(.number.precision(.fractionLength(0...1)))) points.").foregroundStyle(Palette.textSecondary)
            }
            Button("Choose sessions") { mode = "Browse" }.minimumTapTarget()
        }
    }

    private var duplicateGroups: [[JournalEntry]] {
        var byKey: [String: [JournalEntry]] = [:]
        for entry in session.entries {
            let day = Calendar.current.startOfDay(for: entry.date).timeIntervalSince1970
            let fields = [JournalStudioPolicy.normalized(entry.strain),
                          JournalStudioPolicy.normalized(entry.method),
                          JournalStudioPolicy.normalized(entry.notes), String(entry.rating), String(day)]
            byKey[JournalInputPolicy.fingerprint(fields), default: []].append(entry)
        }
        var result: [[JournalEntry]] = []
        for group in byKey.values where group.count > 1 {
            let key = JournalStudioPolicy.duplicateKey(ids: group.map(\.id))
            if !store.snapshot.dismissedDuplicateGroups.contains(key) {
                result.append(group.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date })
            }
        }
        return result.sorted { ($0.first?.date ?? .distantPast) > ($1.first?.date ?? .distantPast) }
    }

    private var duplicateReview: some View {
        let grouped = duplicateGroups
        return VStack(alignment: .leading, spacing: 16) {
            Text("Possible duplicate sessions").font(.seshScaled(22, weight: .bold, design: .serif))
            Text("These logs share a day, strain, method, rating, and notes. They may be separate sessions. Nothing is removed automatically.").foregroundStyle(Palette.textSecondary)
            if grouped.isEmpty { Text("No unreviewed matches.").foregroundStyle(Palette.textSecondary) }
            ForEach(grouped, id: \.first!.id) { group in
                studioCard {
                    Text(group.first?.strain ?? "Sessions").font(.seshScaled(17, weight: .semibold))
                    ForEach(group) { entry in
                        Button(entry.date.formatted(date: .abbreviated, time: .standard)) { editing = entry }.minimumTapTarget()
                    }
                    Button("These are separate sessions", systemImage: "checkmark") {
                        store.change { $0.dismissedDuplicateGroups.insert(JournalStudioPolicy.duplicateKey(ids: group.map(\.id))) }
                    }.minimumTapTarget()
                }
            }
            if !store.snapshot.dismissedDuplicateGroups.isEmpty {
                Button("Review dismissed matches again") { store.change { $0.dismissedDuplicateGroups.removeAll() } }.minimumTapTarget()
            }
        }
    }

    private var exportOptions: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Export \(matching.count) filtered sessions").font(.seshScaled(22, weight: .bold))
                        Text("Includes dates, strain, method, rating, amount, duration, and effects. Photos, companions, and your Studio reflections are excluded.")
                        Toggle("Include private session notes", isOn: $includeNotes)
                        Text("The exported file contains personal information. Choose where to save it.").foregroundStyle(Palette.textSecondary)
                        PrimaryButton(title: "Choose export location", icon: "square.and.arrow.up") {
                            exportDocument = JournalCSVDocument(text: makeCSV(matching))
                            showExportOptions = false
                        }
                    }.font(.seshScaled(15)).padding(20).seshReadableForm()
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showExportOptions = false } } }
        }
        .seshEditorPresentation()
    }

    private func makeCSV(_ entries: [JournalEntry]) -> String {
        var rows = [["Date (ISO 8601)", "Strain", "Method", "Rating / 10", "Amount", "Unit", "Duration (minutes)", "Effects"] + (includeNotes ? ["Notes"] : [])]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            rows.append([formatter.string(from: entry.date), entry.strain, entry.method, String(entry.rating), entry.amount.map { String($0) } ?? "", entry.amountUnit ?? "", entry.durationMinutes.map(String.init) ?? "", entry.effects?.joined(separator: "; ") ?? ""] + (includeNotes ? [entry.notes] : []))
        }
        return JournalStudioPolicy.csv(rows: rows)
    }

    private func saveName() {
        let existing = namingNotebook ? store.snapshot.notebooks.map(\.name) : store.snapshot.savedViews.map(\.name)
        guard let clean = JournalStudioPolicy.validName(name, existing: existing) else { message = "Use a unique name between 1 and 60 characters."; return }
        let success: Bool
        if namingNotebook { success = store.change { $0.notebooks.append(JournalNotebook(name: clean)) } }
        else { success = store.change { $0.savedViews.append(JournalStudioSavedView(name: clean, filter: filter)) } }
        if success { message = namingNotebook ? "Notebook created. Add sessions using their menu." : "View saved."; name = "" }
    }

    private func selectComparison(_ id: UUID) {
        if comparison.contains(id) { comparison.removeAll { $0 == id } }
        else if comparison.count < 2 { comparison.append(id); if comparison.count == 2 { mode = "Compare" } }
        else { message = "Remove one of the two selected sessions before choosing another."; mode = "Compare" }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.seshScaled(12)).foregroundStyle(Palette.textSecondary)
            Text(value).font(.seshScaled(15)).foregroundStyle(Palette.text).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }

    private func studioCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .foregroundStyle(Palette.text).background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct JournalCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

private struct JournalReflectionEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let entry: JournalEntry
    let store: JournalStudioStore
    @State private var draft: JournalReflection
    @State private var baseline: JournalReflection
    @State private var hasFollowUp: Bool
    @State private var due: Date
    @State private var error: String?
    @State private var discard = false
    private let prompts = ["What would you like to remember?", "What felt different from your expectations?", "What did the setting or company change?", "What would you choose differently next time?"]

    init(entry: JournalEntry, store: JournalStudioStore) {
        self.entry = entry; self.store = store
        let existing = store.snapshot.reflections.first { $0.id == entry.id } ?? JournalReflection(id: entry.id)
        _draft = State(initialValue: existing); _baseline = State(initialValue: existing)
        _hasFollowUp = State(initialValue: existing.dueAt != nil)
        _due = State(initialValue: existing.dueAt ?? Date().addingTimeInterval(86400))
    }
    private var hasEdits: Bool {
        draft.text != baseline.text || draft.prompt != baseline.prompt || hasFollowUp != (baseline.dueAt != nil) || (hasFollowUp && due != baseline.dueAt)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(entry.strain).font(.seshScaled(23, weight: .bold, design: .serif))
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Palette.textSecondary)
                        Picker("Reflection prompt", selection: $draft.prompt) { ForEach(prompts, id: \.self) { Text($0).tag($0) } }
                        TextField("Your private reflection", text: $draft.text, axis: .vertical)
                            .lineLimit(5...20).textFieldStyle(.plain).padding(14)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                            .accessibilityLabel("Private reflection")
                        Toggle("Plan a follow-up in Journal Studio", isOn: $hasFollowUp)
                        if hasFollowUp { DatePicker("Follow-up date", selection: $due) }
                        Text("Only stored on this device. This does not post, send a notification, or change the original session.").font(.seshScaled(13)).foregroundStyle(Palette.textSecondary)
                        if let error { Text(error).foregroundStyle(Palette.moodAngry).accessibilityAddTraits(.isStaticText) }
                        PrimaryButton(title: "Save reflection", icon: "checkmark") { save(complete: false) }
                        if baseline.dueAt != nil && baseline.completedAt == nil {
                            Button("Mark follow-up complete", systemImage: "checkmark.circle") { save(complete: true) }.minimumTapTarget()
                        }
                    }.font(.seshScaled(15)).foregroundStyle(Palette.text).padding(20).seshReadableForm()
                }.scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Reflection")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if hasEdits { discard = true } else { dismiss() } } } }
        }
        .interactiveDismissDisabled(hasEdits).seshEditorPresentation()
        .confirmationDialog("Discard reflection changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
    }
    private func save(complete: Bool) {
        guard session.entries.contains(where: { $0.id == entry.id }) else { error = "This session was removed. Copy your reflection before closing."; return }
        guard draft.text.count <= 20000 else { error = "Keep reflections under 20,000 characters."; return }
        draft.dueAt = hasFollowUp ? due : nil
        if complete { draft.completedAt = Date() }
        else if draft.dueAt != baseline.dueAt { draft.completedAt = nil }
        if store.saveReflection(draft) { baseline = draft; dismiss() } else { error = store.error }
    }
}
