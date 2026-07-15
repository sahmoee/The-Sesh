//
//  SaveSeshView.swift
//  The SESH
//
//  Split out of StartSeshView.swift (#3 — file size). No code changes.
//

import SwiftUI

struct SaveSeshView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let strainName: String
    let sessionType: SessionType
    let durationMinutes: Int
    let companions: [String]
    let attachedThought: String
    var capturedThoughts: [String] = []   // thoughts added during the live sesh
    var onDone: () -> Void

    @State private var rating: Double = 7
    @State private var method = "Joint"
    @State private var effects: Set<String> = []
    @State private var notes = ""
    @State private var vault: SeshCategory?
    @State private var photoName: String?

    private let methods = ["Joint", "Blunt", "Bong", "Pipe", "Vape", "Edible", "Other"]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Save this sesh", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Summary
                        DarkCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(strainName.isEmpty ? "Unknown strain" : strainName, systemImage: "leaf.fill")
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text("\(durationMinutes) min").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                }
                                HStack(spacing: 8) {
                                    Text(sessionType.emoji + " " + sessionType.rawValue).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                    if !companions.isEmpty {
                                        Text("· with " + companions.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                    }
                                }
                            }
                        }

                        // Method
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Method")
                            FlowLayout(spacing: 8) {
                                ForEach(methods, id: \.self) { m in
                                    Button { method = m; Haptics.selection() } label: {
                                        Text(m).font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(method == m ? Palette.onGreen : Palette.text)
                                            .padding(.horizontal, 13).padding(.vertical, 8)
                                            .background(Capsule().fill(method == m ? Palette.green : Palette.field))
                                            .overlay(Capsule().stroke(Palette.stroke, lineWidth: method == m ? 0 : 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Rating
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { FieldLabel(text: "Rating"); Spacer(); Text(String(format: "%.0f", rating)).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gold) }
                            Slider(value: $rating, in: 1...10, step: 1).tint(Palette.green)
                        }

                        // Effects
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Effects")
                            FlowLayout(spacing: 8) {
                                ForEach(SeshEffect.allCases) { eff in
                                    Button {
                                        if effects.contains(eff.rawValue) { effects.remove(eff.rawValue) } else { effects.insert(eff.rawValue) }
                                        Haptics.selection()
                                    } label: {
                                        HStack(spacing: 4) { Text(eff.emoji); Text(eff.rawValue).font(.system(size: 12, weight: .medium)) }
                                            .foregroundStyle(effects.contains(eff.rawValue) ? Palette.onGreen : Palette.text)
                                            .padding(.horizontal, 11).padding(.vertical, 7)
                                            .background(Capsule().fill(effects.contains(eff.rawValue) ? Palette.green : Palette.field))
                                            .overlay(Capsule().stroke(Palette.stroke, lineWidth: effects.contains(eff.rawValue) ? 0 : 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Vault
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Add to Vault")
                            FlowLayout(spacing: 8) {
                                ForEach(SeshCategory.allCases) { c in
                                    Button { vault = (vault == c ? nil : c); Haptics.selection() } label: {
                                        Label(c.rawValue, systemImage: c.symbol).font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(vault == c ? Palette.onGreen : Palette.text)
                                            .padding(.horizontal, 11).padding(.vertical, 7)
                                            .background(Capsule().fill(vault == c ? Palette.green : Palette.field))
                                            .overlay(Capsule().stroke(Palette.stroke, lineWidth: vault == c ? 0 : 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Notes")
                            InputField(label: "", placeholder: "How was it?…", value: $notes)
                        }

                        // Photo (optional)
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Add a photo")
                            PhotoField(photoName: $photoName, size: 64)
                        }

                        PrimaryButton(title: "Save to Journal", icon: "checkmark") { save() }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func save() {
        // Collect every thought captured during the sesh, plus any final draft.
        var allThoughts = capturedThoughts
        let trimmedDraft = attachedThought.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty { allThoughts.append(trimmedDraft) }

        var firstThoughtID: UUID? = nil
        for (i, text) in allThoughts.enumerated() {
            let t = HighThought(text: text)
            session.addThought(t)
            if i == 0 { firstThoughtID = t.id }
        }

        var entry = JournalEntry(
            strain: strainName.isEmpty ? "Unknown" : strainName,
            method: method,
            rating: rating,
            notes: notes
        )
        entry.mood = Mood.from(effect: effects.first ?? "")
        entry.smokeAgain = rating >= 7 ? .definitely : (rating >= 5 ? .maybe : .no)
        entry.category = vault
        entry.sessionType = sessionType.rawValue
        entry.durationMinutes = durationMinutes
        entry.companions = companions.isEmpty ? nil : companions
        entry.effects = effects.isEmpty ? nil : Array(effects)
        entry.photoName = photoName
        entry.attachedThoughtID = firstThoughtID

        session.add(entry)
        Haptics.success()
        dismiss()
        onDone()
    }
}
