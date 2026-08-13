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
    @State private var detailedOnly = false
    @State private var showAdd = false
    @State private var editingStrain: StrainProfile?

    private var results: [StrainProfile] {
        strains.search(query, type: typeFilter, detailedOnly: detailedOnly)
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
                    resultsSummary
                    libraryListContent
                }
                floatingAddButton
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAdd) {
            StrainEditorView().environment(strains)
        }
        .sheet(item: $editingStrain) { s in
            StrainEditorView(editing: s).environment(strains)
        }
    }

    private var resultsSummary: some View {
        HStack {
            Text("\(results.count.formatted()) strain\(results.count == 1 ? "" : "s")")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Button { detailedOnly.toggle() } label: {
                Label("Detailed profiles", systemImage: detailedOnly ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(detailedOnly ? Palette.greenBright : Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityValue(detailedOnly ? "On" : "Off")
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
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
                            StoredImage(name: f.photoName, size: 84, corner: Radius.md, strainID: f.id)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(f.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                                }
                                Text(f.type.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(f.type.tint)
                                Label("Detailed profile", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.greenBright)
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
            Text("WELL-DOCUMENTED PICKS").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
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
            StoredImage(name: s.photoName, size: 40, corner: Radius.sm, strainID: s.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(s.type.rawValue).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.greenBright)
        }
        .padding(.vertical, 9)
    }

    private func featuredStrain(from all: [StrainProfile]) -> StrainProfile? {
        let documented = all.filter { $0.completenessScore >= 4 }
        guard !documented.isEmpty else { return nil }
        // Stable daily-ish pick: index by day-of-year.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return documented[day % documented.count]
    }
    private func popularStrains(from all: [StrainProfile]) -> [StrainProfile] {
        // Familiar, well-documented entries—never synthetic popularity.
        let faves = ["Blue Dream", "Wedding Cake", "Runtz", "Permanent Marker", "Gelato"]
        let picked = faves.compactMap { name in all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.completenessScore >= 4 } }
        if picked.count >= 4 { return Array(picked.prefix(4)) }
        return Array(all.sorted { $0.completenessScore > $1.completenessScore }.prefix(4))
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
                StoredImage(name: profile.photoName, size: 44, corner: Radius.sm, strainID: profile.id)
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
                StoredImage(name: profile.photoName, size: 56, corner: Radius.sm, strainID: profile.id)
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
