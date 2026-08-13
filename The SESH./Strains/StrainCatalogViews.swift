//
//  StrainCatalogViews.swift
//  The SESH
//
//  Split out of StrainLibraryView.swift (#3 — file size). No code changes.
//

import SwiftUI

struct StrainCatalogDetailView: View {
    @Environment(StrainStore.self) private var strains
    @Environment(AppSession.self) private var session
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
                                    StrainPhotoButton(strain: shown, size: 72)
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
                                Text("Batch potency and effects can vary. Missing fields mean not reported—not zero.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            }
                        }

                        // Smoke Again — quick re-sesh for a strain you've had before
                        if !session.entries(forStrain: shown.name).isEmpty {
                            Menu {
                                Button { startLiveAgain(shown) } label: {
                                    Label("Start a live sesh", systemImage: "play.circle")
                                }
                                Button { onLog(shown) } label: {
                                    Label("Quick-log a sesh", systemImage: "square.and.pencil")
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.onGreen).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Smoke Again").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onGreen)
                                        Text("You've sesh'd this \(session.entries(forStrain: shown.name).count)x").font(.system(size: 12)).foregroundStyle(Palette.onGreen.opacity(0.8))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.system(size: 13)).foregroundStyle(Palette.onGreen.opacity(0.8))
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.greenBright))
                            }
                            .buttonStyle(.plain)
                        }

                        // Listen — the strain's soundtrack (mood playlists)
                        NavigationLink {
                            StrainSoundtrackView(strain: shown)
                                .navigationBarBackButtonHidden(true)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list").font(.system(size: 18)).foregroundStyle(Palette.greenBright).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Listen").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("Your soundtrack for \(shown.name)").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

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
                            let ranked = shown.effects.allSatisfy { $0.intensity != nil }
                            if ranked {
                                VStack(spacing: 12) {
                                    ForEach(shown.effects) { e in
                                        HStack(spacing: 12) {
                                            Text(e.name).font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 90, alignment: .leading)
                                            EffectBar(value: (e.intensity ?? 0) * 10)
                                            Text(String(format: "%.1f", (e.intensity ?? 0) * 10))
                                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                                                .frame(width: 32, alignment: .trailing)
                                        }
                                    }
                                }
                            } else {
                                FlowLayout(spacing: 8) {
                                    ForEach(shown.effects) { effect in CategoryTag(text: effect.name) }
                                }
                                Text("Reported effects are not ranked because the source does not provide intensity.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
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
                        let shownTraits = Set((shown.effects + shown.flavors + shown.terpenes).map { $0.name.lowercased() })
                        let similar = strains.strains.filter { $0.type == shown.type && $0.id != shown.id }
                            .map { candidate in
                                let traits = Set((candidate.effects + candidate.flavors + candidate.terpenes).map { $0.name.lowercased() })
                                return (candidate, shownTraits.intersection(traits).count * 10 + candidate.completenessScore)
                            }
                            .sorted { $0.1 > $1.1 }.prefix(6).map(\.0)
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
                                                StoredImage(name: sim.photoName, size: 64, corner: Radius.sm, strainID: sim.id)
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

    private func startLiveAgain(_ strain: StrainProfile) {
        // Begin a live sesh pre-filled with this strain.
        let state = LiveSeshState(
            startedAt: Date(),
            stageRaw: SeshStage.allCases.first?.rawValue ?? "",
            sessionTypeRaw: SessionType.relaxing.rawValue,
            strainName: strain.name,
            attachedThought: "",
            rollFinalSeconds: nil,
            rollMethod: "Joint",
            invited: [])
        session.saveLiveSesh(state)
        Haptics.success()
        dismiss()
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
