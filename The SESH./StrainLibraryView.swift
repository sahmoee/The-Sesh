//
//  StrainLibraryView.swift
//  HighThoughts
//
//  Browsable strain reference, backed by the LOCAL database (bundled strains +
//  your own custom strains). Search, type filter, add/edit custom strains, and
//  a detail page. Tapping "Log this strain" jumps into a sesh.
//

import SwiftUI

struct StrainLibraryView: View {
    @Environment(StrainStore.self) private var strains
    @Environment(AppSession.self) private var session
    let onLog: (StrainProfile) -> Void

    @State private var query = ""
    @State private var typeFilter: StrainType?
    @State private var showAdd = false
    @State private var editingStrain: StrainProfile?
    /// Seed for the randomized Featured / Popular picks. Set once per appearance
    /// so the picks are stable while you browse, but reshuffle each time you open
    /// the tab (until real community data drives a true ranking).
    @State private var shuffleSeed: UInt64 = 0

    private var results: [StrainProfile] {
        let base = strains.filtered(by: typeFilter)
        guard !query.isEmpty else { return base }
        let key = query.lowercased()
        return base.filter { $0.matchKeys.contains { $0.contains(key) } }
    }

    private var filterLabels: [String] { ["All"] + StrainType.allCases.filter { $0 != .unknown }.map(\.rawValue) }
    private var filterBinding: Binding<String> {
        Binding(
            get: { typeFilter?.rawValue ?? "All" },
            set: { typeFilter = $0 == "All" ? nil : StrainType(rawValue: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppBackground()
                VStack(spacing: 0) {
                    libraryHeader
                    librarySearchBar
                    StrainToolsBar()
                        .padding(.bottom, 10)
                    FilterPills(items: filterLabels, selection: filterBinding)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                    libraryListContent
                }
                floatingAddButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // Reshuffle Featured / Popular each time the tab is opened.
                shuffleSeed = UInt64.random(in: 1...UInt64.max)
            }
        }
        .sheet(isPresented: $showAdd) {
            StrainEditorView().environment(strains)
        }
        .sheet(item: $editingStrain) { s in
            StrainEditorView(editing: s).environment(strains)
        }
    }

    @ViewBuilder private var libraryHeader: some View {
        ZStack {
            Text("Strains")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            HStack {
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
    }

    @ViewBuilder private var librarySearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
            TextField("", text: $query,
                      prompt: Text("Search strains...").foregroundStyle(Palette.textTertiary))
                .foregroundStyle(Palette.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .contentShape(Rectangle())
        .padding(.horizontal, 18).padding(.bottom, 10)
    }

    @ViewBuilder private var libraryListContent: some View {
        if results.isEmpty {
            emptyState
            Spacer()
        } else {
            List {
                if query.isEmpty && typeFilter == nil {
                    StrainFunFactCard()
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 8, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    featuredSection
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(results) { s in
                    StrainListRow(profile: s, onLog: onLog, onEdit: { editingStrain = $0 })
                }
                Color.clear.frame(height: 80).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var floatingAddButton: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("Add Strain").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Palette.onGreen)
            .padding(.horizontal, 20).padding(.vertical, 13)
            .background(Capsule().fill(Palette.green))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: query.isEmpty ? "books.vertical" : "magnifyingglass",
            title: query.isEmpty ? "No strains" : "No strains match",
            message: query.isEmpty
                ? "Tap Add Strain to create your first custom strain."
                : "No strain matches \"\(query)\". Tap Add Strain to create it."
        )
    }

    // MARK: Featured + Popular (mockup header)

    /// A stable "featured" pick + a "popular this week" ranked list, derived
    /// from the catalog so they're consistent without a backend.
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            forYouBlock
            featuredStrainBlock
            popularBlock
            Text("ALL STRAINS").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var forYouBlock: some View {
        let all = strains.strains
        let recs = session.recommendedStrains(limit: 4)
        if !recs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOR YOU").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                VStack(spacing: 0) {
                    ForEach(Array(recs.enumerated()), id: \.element.id) { idx, rec in
                        if let profile = all.first(where: { $0.name.caseInsensitiveCompare(rec.name) == .orderedSame }) {
                            ForYouRow(rec: rec, profile: profile, onLog: onLog, onEdit: { editingStrain = $0 })
                            if idx < recs.count - 1 { Divider().overlay(Palette.stroke) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            }
        }
    }

    @ViewBuilder private var featuredStrainBlock: some View {
        if let f = featuredStrain(from: strains.strains) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FEATURED STRAIN").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                NavigationLink {
                    StrainCatalogDetailView(profile: f, onLog: onLog, onEdit: { editingStrain = $0 })
                        .navigationBarBackButtonHidden(true)
                } label: {
                    DarkCard {
                        HStack(spacing: 14) {
                            StoredImage(name: f.photoName, size: 84, corner: Radius.md)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(f.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                                }
                                Text(f.type.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(f.type.tint)
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.gold)
                                    Text(communityRating(f)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                                }
                                if let summary = f.summary {
                                    Text(summary).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var popularBlock: some View {
        let popular = popularStrains(from: strains.strains)
        VStack(alignment: .leading, spacing: 8) {
            Text("POPULAR THIS WEEK").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
            VStack(spacing: 0) {
                ForEach(Array(popular.enumerated()), id: \.element.id) { idx, s in
                    NavigationLink {
                        StrainCatalogDetailView(profile: s, onLog: onLog, onEdit: { editingStrain = $0 })
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        popularRow(index: idx, strain: s)
                    }.buttonStyle(.plain)
                    if idx < popular.count - 1 { Divider().overlay(Palette.stroke) }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    private func popularRow(index idx: Int, strain s: StrainProfile) -> some View {
        HStack(spacing: 12) {
            Text("\(idx + 1)").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gold).frame(width: 20)
            BudThumb(size: 40, seed: abs(s.id.hashValue % 60))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(s.type.rawValue).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.gold)
                Text(shortRating(s)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
            }
        }
        .padding(.vertical, 9)
    }

    private func featuredStrain(from all: [StrainProfile]) -> StrainProfile? {
        guard !all.isEmpty else { return nil }
        // Seeded random pick — stable within an appearance, reshuffled on each open.
        var rng = SeededRNG(seed: shuffleSeed)
        return all.randomElement(using: &rng)
    }
    private func popularStrains(from all: [StrainProfile]) -> [StrainProfile] {
        // Randomized until real community submissions drive a true ranking.
        // Seeded shuffle so the list is stable while browsing but reshuffles on open.
        guard !all.isEmpty else { return [] }
        var rng = SeededRNG(seed: shuffleSeed &+ 1)
        return Array(all.shuffled(using: &rng).prefix(4))
    }
    /// Deterministic synthetic community rating like "4.6 (2,463)".
    private func communityRating(_ s: StrainProfile) -> String {
        let seed = abs(s.id.hashValue)
        let rating = 4.0 + Double(seed % 10) / 10.0          // 4.0–4.9
        let count = 800 + (seed % 4200)                       // 800–4999
        return String(format: "%.1f (%d)", rating, count)
    }
    private func shortRating(_ s: StrainProfile) -> String {
        let seed = abs(s.id.hashValue)
        return String(format: "%.1f", 4.0 + Double(seed % 10) / 10.0)
    }
}

// MARK: - "For You" recommendation row (split out so forYouBlock type-checks fast)

private struct ForYouRow: View {
    let rec: AppSession.Recommendation
    let profile: StrainProfile
    let onLog: (StrainProfile) -> Void
    let onEdit: (StrainProfile) -> Void

    var body: some View {
        NavigationLink {
            StrainCatalogDetailView(profile: profile, onLog: onLog, onEdit: onEdit)
                .navigationBarBackButtonHidden(true)
        } label: {
            HStack(spacing: 12) {
                StoredImage(name: profile.photoName, size: 44, corner: Radius.sm)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rec.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(rec.reason).font(.system(size: 12)).foregroundStyle(Palette.greenBright)
                }
                Spacer()
                if rec.stats.averageRating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.gold)
                        Text(String(format: "%.1f", rec.stats.averageRating)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                }
            }
            .padding(.vertical, 9)
        }.buttonStyle(.plain)
    }
}

// MARK: - One row in the main strain list (split out so the List type-checks fast)

private struct StrainListRow: View {
    @Environment(StrainStore.self) private var strains
    let profile: StrainProfile
    let onLog: (StrainProfile) -> Void
    let onEdit: (StrainProfile) -> Void

    var body: some View {
        NavigationLink {
            StrainCatalogDetailView(profile: profile, onLog: onLog, onEdit: onEdit)
                .navigationBarBackButtonHidden(true)
        } label: {
            StrainRow(profile: profile, seed: abs(profile.id.hashValue % 60))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if strains.isCustom(profile) {
                Button(role: .destructive) {
                    Haptics.warning(); strains.deleteCustom(profile)
                } label: { Label("Delete", systemImage: "trash") }
                Button {
                    onEdit(profile)
                } label: { Label("Edit", systemImage: "pencil") }
                .tint(Palette.green)
            }
        }
        .contextMenu {
            Button { onLog(profile) } label: { Label("Log this strain", systemImage: "plus") }
            if strains.isCustom(profile) {
                Button { onEdit(profile) } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { strains.deleteCustom(profile) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }
}

struct StrainRow: View {
    @Environment(StrainStore.self) private var strains
    let profile: StrainProfile
    var seed: Int = 0

    var body: some View {
        DarkCard(padding: 12) {
            HStack(spacing: 12) {
                StoredImage(name: profile.photoName, size: 56, corner: Radius.sm)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        if strains.isCustom(profile) {
                            Text("Custom").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.gold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.gold.opacity(0.15)))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(profile.type.rawValue)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(profile.type.tint)
                        if let thc = profile.thc {
                            Text("THC \(Int(thc))%").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    if !profile.effects.isEmpty {
                        Text(profile.effects.prefix(3).map(\.name).joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    } else if let summary = profile.summary {
                        Text(summary).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Catalog detail

struct StrainCatalogDetailView: View {
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss
    let profile: StrainProfile
    @State private var selectedTerpene: TerpeneFact?
    /// The strain currently shown. Starts as `profile`; tapping a "similar"
    /// strain swaps this in place rather than pushing a new screen, so Back
    /// always returns to the library instead of retracing the chain.
    @State private var current: StrainProfile?
    let onLog: (StrainProfile) -> Void
    var onEdit: ((StrainProfile) -> Void)? = nil

    /// The effective profile being displayed.
    private var shown: StrainProfile { current ?? profile }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: shown.name, onBack: { dismiss() }) {
                    if strains.isCustom(shown), let onEdit {
                        Button { dismiss(); onEdit(shown) } label: {
                            Image(systemName: "pencil").font(.system(size: 17)).foregroundStyle(Palette.text)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DarkCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    StoredImage(name: shown.photoName, size: 64, corner: Radius.md)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(shown.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                                        HStack(spacing: 8) {
                                            infoPill(shown.type.rawValue, color: shown.type.tint)
                                            if let thc = shown.thc { infoPill("THC \(Int(thc))%", color: Palette.gold) }
                                            if let cbd = shown.cbd, cbd >= 1 { infoPill("CBD \(Int(cbd))%", color: Palette.greenBright) }
                                        }
                                    }
                                    Spacer()
                                }
                                if let summary = shown.summary {
                                    Text(summary).font(.system(size: 14)).foregroundStyle(Palette.text.opacity(0.9))
                                }
                            }
                        }

                        // Genetics & origin (from SeedFinder data)
                        if shown.breeder != nil || shown.lineage != nil || shown.floweringTime != nil {
                            DarkCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("GENETICS").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                                    if let lineage = shown.lineage {
                                        GeneticsTree(strain: shown.name, lineage: lineage,
                                                     known: { name in strains.strains.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } })
                                            .padding(.vertical, 4)
                                    }
                                    if let breeder = shown.breeder {
                                        detailRow("Breeder", breeder, icon: "leaf.arrow.triangle.circlepath")
                                    }
                                    if let flowering = shown.floweringTime {
                                        detailRow("Flowering", flowering, icon: "clock")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !shown.effects.isEmpty {
                            Text("Effects").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                            VStack(spacing: 12) {
                                ForEach(shown.effects) { e in
                                    HStack(spacing: 12) {
                                        Text(e.name).font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 90, alignment: .leading)
                                        EffectBar(value: (e.intensity ?? 0.6) * 10)
                                        Text(String(format: "%.1f", (e.intensity ?? 0.6) * 10))
                                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                                            .frame(width: 32, alignment: .trailing)
                                    }
                                }
                            }
                        }

                        if !shown.flavors.isEmpty {
                            Text("Flavors").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
                            FlowLayout(spacing: 8) { ForEach(shown.flavors) { CategoryTag(text: $0.name) } }
                        }

                        if !shown.terpenes.isEmpty {
                            Text("Terpenes").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
                            FlowLayout(spacing: 8) {
                                ForEach(shown.terpenes) { terp in
                                    Button { selectedTerpene = TerpeneLibrary.fact(for: terp.name) ?? TerpeneFact(name: terp.name, aroma: "—", effect: "No details available for this terpene yet.", alsoIn: "—") } label: {
                                        HStack(spacing: 4) {
                                            Text(terp.name)
                                            if TerpeneLibrary.fact(for: terp.name) != nil {
                                                Image(systemName: "info.circle").font(.system(size: 11)).opacity(0.7)
                                            }
                                        }
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(Palette.field))
                                        .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Potency bars (THC / CBD)
                        if shown.thc != nil || (shown.cbd ?? 0) >= 0.1 {
                            Text("Potency").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
                            VStack(spacing: 10) {
                                if let thc = shown.thc {
                                    potencyBar("THC", value: thc, max: 30, color: Palette.gold)
                                }
                                if let cbd = shown.cbd, cbd >= 0.1 {
                                    potencyBar("CBD", value: cbd, max: 20, color: Palette.greenBright)
                                }
                            }
                        }

                        // Similar strains (same type)
                        let similar = strains.strains.filter {
                            $0.type == shown.type && $0.id != shown.id
                        }.prefix(6)
                        if !similar.isEmpty {
                            Text("Similar Strains").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(similar)) { sim in
                                        Button {
                                            // Swap content in place — no new screen is pushed, so
                                            // Back returns to the library, not the browse chain.
                                            withAnimation(.easeInOut(duration: 0.2)) { current = sim }
                                            Haptics.tap()
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                StoredImage(name: sim.photoName, size: 64, corner: Radius.sm)
                                                Text(sim.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
                                                    .lineLimit(1).frame(width: 64, alignment: .leading)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        PrimaryButton(title: "Log this strain", icon: "plus") {
                            dismiss()
                            onLog(shown)
                        }
                        .padding(.top, 4)

                        if !shown.sources.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle").font(.system(size: 11))
                                Text(shown.isCustom ? "Your custom strain" : "Strain data: \(shown.sources.joined(separator: ", "))")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
            .sheet(item: $selectedTerpene) { fact in
                TerpeneSheet(fact: fact).presentationDetents([.height(300), .medium])
            }
        }
    }

    private func infoPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Palette.field))
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func detailRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Palette.green)
                .frame(width: 18).accessibilityHidden(true)
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                .frame(width: 76, alignment: .leading)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func potencyBar(_ label: String, value: Double, max: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text).frame(width: 40, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.field).frame(height: 10)
                Capsule().fill(color).frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: Swift.max(0, Swift.min(1, value / max)), anchor: .leading)
            }
            Text(String(format: "%.1f%%", value)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(String(format: "%.1f", value)) percent")
    }
}

// MARK: - Manual strain entry / edit

struct StrainEditorView: View {
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss
    var editing: StrainProfile? = nil

    @State private var name = ""
    @State private var type: StrainType = .hybrid
    @State private var thc = ""
    @State private var cbd = ""
    @State private var effects = ""     // comma-separated
    @State private var flavors = ""
    @State private var summary = ""
    @State private var photoName: String?
    @State private var didLoad = false

    private var isEditing: Bool { editing != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: isEditing ? "Edit Strain" : "Add Strain", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 18) {
                        HStack(spacing: 14) {
                            PhotoField(photoName: $photoName, size: 72)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Strain Photo").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("Snap a pic of your strain or add one from your library.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        InputField(label: "Name", placeholder: "e.g. Blue Dream", value: $name)

                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Type")
                            Picker("", selection: $type) {
                                ForEach(StrainType.allCases.filter { $0 != .unknown }) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(spacing: 12) {
                            numberField("THC %", $thc)
                            numberField("CBD %", $cbd)
                        }

                        InputField(label: "Effects (comma-separated)", placeholder: "Relaxed, Happy, Creative", value: $effects)
                        InputField(label: "Flavors (comma-separated)", placeholder: "Sweet, Citrus", value: $flavors)
                        NotesField(label: "Notes (optional)", placeholder: "Describe the strain...", text: $summary, minHeight: 80)

                        PrimaryButton(title: isEditing ? "Save Changes" : "Add Strain") { save() }
                            .opacity(canSave ? 1 : 0.5)
                            .disabled(!canSave)

                        if isEditing, let e = editing {
                            Button(role: .destructive) {
                                Haptics.warning(); strains.deleteCustom(e); dismiss()
                            } label: {
                                Text("Delete Strain").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.moodAngry)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.moodAngry.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear(perform: load)
    }

    private func numberField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            TextField("", text: text, prompt: Text("—").foregroundStyle(Palette.textTertiary))
                .keyboardType(.decimalPad)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let e = editing else { return }
        name = e.name; type = e.type
        if let t = e.thc { thc = t.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(t)) : String(t) }
        if let c = e.cbd { cbd = c.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(c)) : String(c) }
        effects = e.effects.map(\.name).joined(separator: ", ")
        flavors = e.flavors.map(\.name).joined(separator: ", ")
        summary = e.summary ?? ""
        photoName = e.photoName
    }

    private func splitList(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let thcVal = Double(thc.filter { "0123456789.".contains($0) })
        let cbdVal = Double(cbd.filter { "0123456789.".contains($0) })
        let summaryText = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        var profile = editing ?? StrainProfile(id: StrainProfile.slug(from: trimmed), name: trimmed, type: type)
        profile.name = trimmed
        profile.type = type
        profile.thc = thcVal
        profile.cbd = cbdVal
        profile.effects = splitList(effects).map { StrainTrait(name: $0, intensity: nil) }
        profile.flavors = splitList(flavors).map { StrainTrait(name: $0, intensity: nil) }
        profile.summary = summaryText.isEmpty ? nil : summaryText
        profile.photoName = photoName
        profile.isCustom = true
        if profile.sources.isEmpty { profile.sources = ["My strains"] }

        strains.upsertCustom(profile)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Terpene info sheet (#12)

struct TerpeneSheet: View {
    let fact: TerpeneFact
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 26)).foregroundStyle(Palette.greenBright)
                        Text(fact.name).font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(Palette.textTertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
                terpRow("Aroma", fact.aroma, "nose")
                terpRow("Associated with", fact.effect, "sparkles")
                terpRow("Also found in", fact.alsoIn, "basket")
                Text("Educational only — not medical advice.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                Spacer()
            }
            .padding(20)
        }
    }

    private func terpRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Palette.green).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                Text(value).font(.system(size: 14)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Genetics tree (#11)

/// A simple visual family tree: the strain on top, a connector, then its parent
/// strains parsed from the lineage string. Parents known to the catalog are
/// highlighted. Built without GeometryReader.
struct GeneticsTree: View {
    let strain: String
    let lineage: String
    let known: (String) -> Bool

    /// Parse "OG Kush x Sour Diesel" / "A x (B x C)" into top-level parents.
    private var parents: [String] {
        // Split on " x " at the top level, strip parentheses for display.
        let cleaned = lineage.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "x×"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 1 }
        // De-dupe preserving order
        var seen = Set<String>(); return parts.filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        if parents.count >= 2 {
            VStack(spacing: 0) {
                node(strain, isRoot: true)
                // Connector
                Rectangle().fill(Palette.stroke).frame(width: 2, height: 14)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(parents.prefix(4).enumerated()), id: \.offset) { _, p in
                        node(p, isRoot: false)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            // Not a cross we can split — just show the lineage text.
            Text(lineage).font(.system(size: 13)).foregroundStyle(Palette.text)
        }
    }

    private func node(_ name: String, isRoot: Bool) -> some View {
        let inCatalog = known(name)
        return Text(name)
            .font(.system(size: isRoot ? 14 : 12, weight: isRoot ? .bold : .medium))
            .foregroundStyle(isRoot ? Palette.onGreen : (inCatalog ? Palette.text : Palette.textSecondary))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isRoot ? Palette.green : Palette.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isRoot ? Color.clear : (inCatalog ? Palette.green.opacity(0.5) : Palette.stroke), lineWidth: 1))
    }
}

// MARK: - Fun fact (top of Strains)

/// A rotating cannabis "did you know" shown at the top of the Strains tab.
enum StrainFunFacts {
    static let all: [String] = [
        "Terpenes — not just THC — shape a strain's effects. Myrcene leans relaxing; limonene lifts mood.",
        "\"Indica\" vs \"sativa\" describes the plant's shape more than its effects. Terpene and cannabinoid profiles are the better guide.",
        "Myrcene is the most common terpene in cannabis and is also found in mangoes and hops.",
        "Linalool, the terpene behind lavender's scent, also shows up in many calming strains.",
        "THC and CBD are just two of 100+ cannabinoids the plant produces.",
        "Pinene smells like pine and may help offset some of THC's short-term memory effects.",
        "Caryophyllene is the only terpene known to act like a cannabinoid, binding to CB2 receptors.",
        "A strain's potency depends as much on how it's grown and cured as on its genetics.",
        "Trichomes — the frosty crystals on buds — are where most cannabinoids and terpenes are made.",
        "The \"entourage effect\" is the idea that cannabis compounds work better together than in isolation.",
    ]
    /// A fact that rotates by day, so it feels fresh without being random each render.
    static var today: String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return all[day % all.count]
    }
}

struct StrainFunFactCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill").font(.system(size: 16)).foregroundStyle(Palette.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text("DID YOU KNOW").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
                Text(StrainFunFacts.today).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.gold.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Seeded RNG

/// A tiny deterministic random generator (SplitMix64) so seeded shuffles are
/// stable for a given seed. Used to keep Featured / Popular picks steady while
/// browsing, reshuffling only when the tab is re-opened.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
