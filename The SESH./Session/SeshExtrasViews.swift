//
//  SeshExtrasViews.swift
//  The SESH
//
//  The feature-pack screens. Each is self-contained and reads from the existing
//  AppSession / StrainStore. They're gathered under `SeshExtrasHub` so a single
//  entry point (added to the Me tab) exposes them without restructuring the app.
//
//  Screens:
//   • Smart Picks            — strain recommendations scored from your ratings
//   • Sesh Presets           — saved strain+method setups (one-tap start)
//   • Tolerance / T-Break    — gauge + break tracker
//   • Monthly Budget         — set a budget, track spend against it
//   • Sesh Calendar          — GitHub-style activity heatmap
//   • Rhythm                 — time-of-day + weekday patterns
//   • Your Strains + dossier — per-strain stats, spend, top songs, favorite star
//   • Weekly Recap           — this-week summary with a share sheet
//   • Surprise Me            — pick a random strain from the catalog
//

import SwiftUI

// MARK: - Hub

struct SeshExtrasHub: View {
    var body: some View {
        List {
            Section {
                NavigationLink { SmartPicksView() } label: {
                    row("sparkles", "Smart Picks", "Strains scored from your ratings", Palette.gold)
                }
                NavigationLink { SeshPresetsView() } label: {
                    row("bolt.circle.fill", "Sesh Presets", "One-tap saved setups", Palette.greenBright)
                }
                NavigationLink { YourStrainsView() } label: {
                    row("leaf.circle.fill", "Your Strains", "Per-strain stats & dossiers", Palette.green)
                }
                NavigationLink { MusicStationsView() } label: {
                    row("music.note.list", "Music Stations", "Stations from your song history", Palette.purple)
                }
                NavigationLink { StashInventoryView() } label: {
                    row("shippingbox.fill", "Inventory", "Grams tracking & low-stock", Palette.greenBright)
                }
            } header: { Text("Discover") }

            Section {
                NavigationLink { ToleranceView() } label: {
                    row("gauge.with.dots.needle.33percent", "Tolerance & T-Break", "Track a break", Palette.purple)
                }
                NavigationLink { BudgetView() } label: {
                    row("dollarsign.circle.fill", "Monthly Budget", "Spend vs. your limit", Palette.gold)
                }
                NavigationLink { SeshCalendarView() } label: {
                    row("calendar", "Sesh Calendar", "Your activity heatmap", Palette.greenBright)
                }
                NavigationLink { RhythmView() } label: {
                    row("clock.arrow.circlepath", "Rhythm", "Time & weekday patterns", Palette.purple)
                }
            } header: { Text("Track") }

            Section {
                NavigationLink { WeeklyRecapView() } label: {
                    row("chart.bar.doc.horizontal", "Weekly Recap", "Your week, shareable", Palette.green)
                }
                NavigationLink { SurpriseMeView() } label: {
                    row("dice.fill", "Surprise Me", "Pick a random strain", Palette.gold)
                }
            } header: { Text("Fun") }
        }
        .navigationTitle("Extras")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Smart Picks

struct SmartPicksView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains

    private var picks: [SmartPick] { session.smartPicks(limit: 8) }

    var body: some View {
        ScrollView {
            if picks.isEmpty {
                EmptyStateView(icon: "sparkles", title: "Not enough data yet",
                               message: "Log a few seshes with ratings and Smart Picks will start recommending strains you've loved.")
            } else {
                VStack(spacing: 12) {
                    Text("Scored from your own ratings, how often you reach for a strain, and how long it's been.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    ForEach(picks) { pick in
                        card(pick)
                    }
                }
                .padding(16)
            }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Smart Picks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ pick: SmartPick) -> some View {
        let profile = strains.strain(named: pick.strainName)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Palette.field).frame(width: 44, height: 44)
                Text("\(Int(pick.score * 100))")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.greenBright)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pick.strainName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Text(pick.reason).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                if let t = profile?.type, t != .unknown {
                    Text(t.rawValue).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(t.tint)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Sesh Presets

struct SeshPresetsView: View {
    @Environment(AppSession.self) private var session
    @State private var showAdd = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if session.seshPresets.isEmpty {
                    EmptyStateView(icon: "bolt.circle", title: "No presets yet",
                                   message: "Save a strain + method combo you reach for often, then start it in one tap.",
                                   actionTitle: "New Preset", actionIcon: "plus") { showAdd = true }
                } else {
                    ForEach(session.seshPresets) { preset in
                        presetCard(preset)
                    }
                    Button { Haptics.tap(); showAdd = true } label: {
                        Label("New Preset", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Sesh Presets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddPresetSheet() }
        .toast($toast)
    }

    private func start(_ preset: SeshPreset) {
        if session.startPreset(preset) {
            Haptics.success()
            toast = "Started · \(preset.strainName)"
        } else {
            Haptics.warning()
            toast = "A sesh is already active"
        }
    }

    private func presetCard(_ preset: SeshPreset) -> some View {
        HStack(spacing: 12) {
            Text(preset.sessionType.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Text(preset.subtitle).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                start(preset)
            } label: {
                Text("Start").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onGreen)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.green))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) { session.deletePreset(preset) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct AddPresetSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var strainName = ""
    @State private var method = "Joint"
    @State private var vibe: SessionType = .relaxing

    private let methods = ["Joint", "Blunt", "Bong", "Pipe", "Vape", "Edible", "Dab"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    TextField("Name (e.g. Wake & Bake)", text: $name)
                }
                Section("Setup") {
                    TextField("Strain", text: $strainName)
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.self) { Text($0) }
                    }
                    Picker("Vibe", selection: $vibe) {
                        ForEach(SessionType.allCases) { Text("\($0.emoji) \($0.rawValue)").tag($0) }
                    }
                }
                if !strainName.isEmpty {
                    Section {
                        ForEach(strains.suggestions(for: strainName, limit: 4)) { s in
                            Button { strainName = s.name } label: {
                                Text(s.name).foregroundStyle(Palette.text)
                            }
                        }
                    } header: { Text("Suggestions") }
                }
            }
            .navigationTitle("New Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let label = name.trimmingCharacters(in: .whitespaces)
                        let strain = strainName.trimmingCharacters(in: .whitespaces)
                        guard !strain.isEmpty else { return }
                        session.addPreset(SeshPreset(
                            name: label.isEmpty ? strain : label,
                            strainName: strain, method: method,
                            sessionTypeRaw: vibe.rawValue))
                        Haptics.success(); dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Tolerance & T-Break

struct ToleranceView: View {
    @Environment(AppSession.self) private var session
    @State private var goalDays = 7

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                gauge
                if session.isOnTBreak { activeBreak } else { startBreak }
                Text("This is a rough gauge from your logging frequency over the last 14 days — not medical advice.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Tolerance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { goalDays = session.tBreakGoalDays }
    }

    private var gauge: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Palette.field, lineWidth: 14).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: session.toleranceEstimate)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                VStack(spacing: 2) {
                    Text(session.toleranceLabel).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                    Text("tolerance").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private var gaugeColor: Color {
        switch session.toleranceEstimate {
        case ..<0.2: return Palette.greenBright
        case ..<0.45: return Palette.gold
        case ..<0.7: return Palette.gold
        default: return Palette.moodAngry
        }
    }

    private var startBreak: some View {
        VStack(spacing: 14) {
            Stepper("Goal: \(goalDays) days", value: $goalDays, in: 1...60)
                .font(.system(size: 15)).foregroundStyle(Palette.text)
            Button {
                session.startTBreak(goalDays: goalDays); Haptics.success()
            } label: {
                Label("Start a T-Break", systemImage: "pause.circle.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.green))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }

    private var activeBreak: some View {
        VStack(spacing: 12) {
            Text("Day \(session.tBreakDays) of \(session.tBreakGoalDays)")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
            ProgressView(value: session.tBreakProgress)
                .tint(Palette.greenBright)
            if session.tBreakProgress >= 1 {
                Text("🎉 Goal reached — nice work!")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.greenBright)
            }
            Button(role: .destructive) {
                session.endTBreak(); Haptics.warning()
            } label: {
                Text("End Break").font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Monthly Budget

struct BudgetView: View {
    @Environment(AppSession.self) private var session
    @State private var budgetText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if session.hasBudget { summary } 
                editor
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Monthly Budget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if session.hasBudget { budgetText = String(Int(session.monthlyBudget)) } }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent this month").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Text(Fmt.currency(session.spentThisMonth))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(session.isOverBudget ? Palette.moodAngry : Palette.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.isOverBudget ? "Over by" : "Left").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Text(Fmt.currency(session.isOverBudget ? session.spentThisMonth - session.monthlyBudget : session.budgetRemaining))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(session.isOverBudget ? Palette.moodAngry : Palette.greenBright)
                }
            }
            ProgressView(value: session.budgetProgress)
                .tint(session.isOverBudget ? Palette.moodAngry : Palette.greenBright)
            Text("Budget: \(Fmt.currency(session.monthlyBudget))")
                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set your monthly budget").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            HStack {
                Text("$").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                TextField("0", text: $budgetText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 18))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.field))
            Button {
                session.monthlyBudget = Double(budgetText) ?? 0
                Haptics.success()
            } label: {
                Text("Save Budget").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.green))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Sesh Calendar (heatmap)

struct SeshCalendarView: View {
    @Environment(AppSession.self) private var session

    private let cols = 17   // ~17 weeks * 7 = 119 days
    private var data: [(date: Date, count: Int)] { session.dailyActivity(days: cols * 7) }
    private var maxCount: Int { max(1, data.map(\.count).max() ?? 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(session.entries.count) sessions logged, all-time")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                grid
                legend
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Sesh Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var grid: some View {
        // Column-major: each column is a week (7 days).
        let columns = stride(from: 0, to: data.count, by: 7).map { start in
            Array(data[start..<min(start + 7, data.count)])
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day.count))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2).fill(levelColor(level)).frame(width: 12, height: 12)
            }
            Text("More").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return Palette.field }
        let ratio = Double(count) / Double(maxCount)
        return levelColor(min(4, 1 + Int(ratio * 3)))
    }
    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 0: return Palette.field
        case 1: return Palette.green.opacity(0.35)
        case 2: return Palette.green.opacity(0.6)
        case 3: return Palette.greenBright.opacity(0.8)
        default: return Palette.greenBright
        }
    }
}

// MARK: - Rhythm

struct RhythmView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let peak = session.peakTimeOfDay {
                    Text("You sesh most in the \(peak.lowercased()).")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                barCard("Time of Day", session.timeOfDayRhythm())
                barCard("By Weekday", session.weekdayRhythm())
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Rhythm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func barCard(_ title: String, _ buckets: [RhythmBucket]) -> some View {
        let maxV = max(1, buckets.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
            ForEach(buckets) { b in
                HStack(spacing: 10) {
                    Text(b.label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        .frame(width: 74, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.field)
                            Capsule().fill(Palette.greenBright)
                                .frame(width: max(4, geo.size.width * CGFloat(b.count) / CGFloat(maxV)))
                        }
                    }
                    .frame(height: 14)
                    Text("\(b.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Your Strains + dossier

struct YourStrainsView: View {
    @Environment(AppSession.self) private var session
    @State private var favoritesOnly = false

    private var rows: [StrainInsight] {
        let base = session.insights
        return favoritesOnly ? base.filter { session.isFavoriteStrain($0.name) } : base
    }

    var body: some View {
        List {
            if session.insights.isEmpty {
                Section {
                    EmptyStateView(icon: "leaf", title: "No strains logged yet",
                                   message: "Log some seshes and your strains — with stats, spend, and top songs — will appear here.")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Toggle("Favorites only", isOn: $favoritesOnly)
                        .font(.system(size: 14)).tint(Palette.green)
                }
                Section {
                    ForEach(rows) { insight in
                        NavigationLink { StrainDossierView(strainName: insight.name) } label: {
                            HStack(spacing: 10) {
                                if session.isFavoriteStrain(insight.name) {
                                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("\(insight.sessions) seshes · \(Fmt.rating(insight.averageRating))★ avg")
                                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Your Strains")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StrainDossierView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    let strainName: String

    private var entries: [JournalEntry] { session.entries(forStrain: strainName) }
    private var profile: StrainProfile? { strains.strain(named: strainName) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                statsGrid
                if !session.recentRatings(forStrain: strainName).isEmpty {
                    sparkCard
                }
                let songs = session.topSongs(forStrain: strainName, limit: 5)
                if !songs.isEmpty { songsCard(songs) }
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle(strainName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.toggleFavoriteStrain(strainName); Haptics.selection()
                } label: {
                    Image(systemName: session.isFavoriteStrain(strainName) ? "star.fill" : "star")
                        .foregroundStyle(Palette.gold)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let p = profile, p.type != .unknown {
                Text(p.type.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.type.tint)
            }
            if let thc = profile?.thc, thc > 0 {
                Text("THC \(Int(thc))%").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var statsGrid: some View {
        let avg = entries.map(\.rating).reduce(0, +) / Double(max(1, entries.count))
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            stat("Sessions", "\(entries.count)")
            stat("Avg Rating", "\(Fmt.rating(avg))★")
            stat("Total Spend", Fmt.currency(session.spend(forStrain: strainName)))
            stat("Last Used", session.lastUsed(forStrain: strainName).map(Fmt.shortDate) ?? "—")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.stroke, lineWidth: 1))
    }

    private var sparkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating trend").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            Sparkline(values: session.recentRatings(forStrain: strainName, limit: 10))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }

    private func songsCard(_ songs: [SongTally]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top songs while smoking this").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            ForEach(songs) { s in
                HStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(Palette.greenBright)
                    Text("\(s.title) — \(s.artist)").font(.system(size: 13)).foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("×\(s.count)").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Weekly Recap (with share)

struct WeeklyRecapView: View {
    @Environment(AppSession.self) private var session

    private var recapText: String {
        """
        My week on The Sesh 🌿
        • \(session.sessionsThisWeek) seshes
        • \(Fmt.rating(session.avgRatingThisWeek))★ average
        • \(Fmt.currency(session.spentThisWeek)) spent
        • \(session.currentStreak)-day streak
        """
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                recapRow("flame.fill", "\(session.sessionsThisWeek)", "seshes this week", Palette.greenBright)
                recapRow("star.fill", "\(Fmt.rating(session.avgRatingThisWeek))★", "average rating", Palette.gold)
                recapRow("dollarsign.circle.fill", Fmt.currency(session.spentThisWeek), "spent", Palette.green)
                recapRow("bolt.fill", "\(session.currentStreak) days", "current streak", Palette.purple)

                ShareLink(item: recapText) {
                    Label("Share Recap", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.green))
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Weekly Recap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recapRow(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint).frame(width: 30)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Surprise Me

struct SurpriseMeView: View {
    @Environment(StrainStore.self) private var strains
    @State private var pick: StrainProfile?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            if let pick {
                VStack(spacing: 10) {
                    Text(pick.name).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                    if pick.type != .unknown {
                        Text(pick.type.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(pick.type.tint)
                    }
                    if let thc = pick.thc, thc > 0 {
                        Text("THC \(Int(thc))%").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    if let summary = pick.summary, !summary.isEmpty {
                        Text(summary).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center).padding(.top, 4).padding(.horizontal, 8)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.stroke, lineWidth: 1))
            } else {
                Image(systemName: "dice.fill").font(.system(size: 56)).foregroundStyle(Palette.gold)
                Text("Tap for a random strain").font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button { roll() } label: {
                Label(pick == nil ? "Surprise Me" : "Again", systemImage: "dice.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.green))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle("Surprise Me")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roll() {
        Haptics.tap()
        pick = strains.strains.randomElement()
    }
}
