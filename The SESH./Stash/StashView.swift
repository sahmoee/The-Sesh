//
//  StashView.swift
//  The SESH
//
//  The stash / purchase log (Home → Your Stash). Log what you bought, how much,
//  and what it cost; sessions draw down the remaining amount. Replaces the
//  per-sesh price field. Purchases can be deleted with a swipe.
//

import SwiftUI

struct StashView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var query = ""
    @State private var pendingDeletion: Purchase?

    private var visiblePurchases: [Purchase] {
        session.purchases.filter { JournalInputPolicy.matches(query, fields: [$0.strain, $0.unit]) }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Your Stash", onBack: { dismiss() }) {
                    Button { showAdd = true; Haptics.tap() } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text).minimumTapTarget()
                    }.buttonStyle(.plain).accessibilityLabel("Add a historical stash record")
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)

                if session.purchases.isEmpty {
                    ScrollView {
                        EmptyStateView(icon: "shippingbox",
                                   title: "Nothing in your stash",
                                   message: "Keep a private record of existing items and review their recorded history.",
                                       actionTitle: "Add a purchase", actionIcon: "plus") { showAdd = true }.padding(.bottom, 32)
                    }
                } else {
                    HStack {
                        InputField(label: "Search stash records", placeholder: "Strain or unit", value: $query)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").minimumTapTarget()
                            }.buttonStyle(.plain).foregroundStyle(Palette.textSecondary).accessibilityLabel("Clear stash search")
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 8)
                    if visiblePurchases.isEmpty {
                        ScrollView {
                            EmptyStateView(icon: "magnifyingglass", title: "No matching records", message: "Try another strain name or clear your search.", actionTitle: "Clear search") { query = "" }.padding(.bottom, 32)
                        }
                    } else {
                        List {
                        // In-stock first
                        let inStock = visiblePurchases.filter { !$0.isEmpty }
                        let empties = visiblePurchases.filter { $0.isEmpty }
                        if !inStock.isEmpty {
                            Section {
                                ForEach(inStock) { purchaseRow($0) }
                            } header: { Text("In Stock").foregroundStyle(Palette.textTertiary) }
                            .listRowBackground(Palette.card)
                        }
                        if !empties.isEmpty {
                            Section {
                                ForEach(empties) { purchaseRow($0) }
                            } header: { Text("Used Up").foregroundStyle(Palette.textTertiary) }
                            .listRowBackground(Palette.card)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddPurchaseView().environment(session) }
        .confirmationDialog("Delete this stash record?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            if let purchase = pendingDeletion {
                Button("Delete Record", role: .destructive) { session.deletePurchase(purchase); pendingDeletion = nil }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { Text("This removes only the selected stash record. Your journal entries remain.") }
    }

    private func purchaseRow(_ p: Purchase) -> some View {
        let fraction = p.amount > 0 ? min(max(p.remaining / p.amount, 0), 1) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text(p.cost, format: .currency(code: "USD")).font(.seshScaled(14, weight: .medium)).foregroundStyle(Palette.gold)
            }
            HStack {
                Text(p.amountLine).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(Fmt.shortDate(p.date)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            // Remaining bar — clamped so an inconsistent remaining/amount can
            // never scale the fill past the capsule.
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.field).frame(height: 6)
                Capsule().fill(p.isEmpty ? Palette.textTertiary : Palette.green).frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: fraction, anchor: .leading)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = p }
        }
        .contextMenu { Button("Delete Record", systemImage: "trash", role: .destructive) { pendingDeletion = p } }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((p.amount > 0 ? (min(max(p.remaining / p.amount, 0), 1)) : 0) * 100)) percent remaining")
    }
}

// MARK: - Add purchase

struct AddPurchaseView: View {
    @Environment(AppSession.self) private var session
    @Environment(StrainStore.self) private var strains
    @Environment(\.dismiss) private var dismiss

    @State private var strain = ""
    @State private var amount = ""
    @State private var unit = "g"
    @State private var cost = ""
    @State private var date = Date()
    @State private var initialDate = Date()
    @State private var didLoad = false
    @State private var confirmDiscard = false
    @State private var saving = false

    /// Locale-aware currency-ish parsing. `Double("3,50")` returns nil and the
    /// old digit-filter hack turned "3,50" into 350 — parse with the user's
    /// locale instead, and block saving when the text can't be parsed at all.
    /// nil = unparseable input (save blocked). Empty input is a valid $0.
    private var parsedCost: Double? {
        let trimmed = JournalInputPolicy.trimmed(cost)
        if trimmed.isEmpty { return 0 }
        return JournalInputPolicy.decimal(trimmed)
    }

    private var canSave: Bool {
        !JournalInputPolicy.trimmed(strain).isEmpty && (JournalInputPolicy.decimal(amount) ?? 0) > 0 && parsedCost != nil && !saving
    }

    private var hasEdits: Bool { didLoad && (!strain.isEmpty || !amount.isEmpty || !cost.isEmpty || unit != "g" || !Calendar.current.isDate(date, inSameDayAs: initialDate)) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Add Purchase", onBack: { if hasEdits { confirmDiscard = true } else { dismiss() } })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Strain with type-ahead
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Strain")
                            InputField(label: "", placeholder: "Strain name…", value: $strain)
                            if !strain.isEmpty {
                                let matches = strains.suggestions(for: strain, limit: 4)
                                ForEach(Array(matches)) { m in
                                    Button { strain = m.name; Haptics.selection() } label: {
                                        HStack { Text(m.name).font(.system(size: 14)).foregroundStyle(Palette.text); Spacer() }.padding(.vertical, 5)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        // Amount + unit
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Amount bought")
                            HStack(spacing: 8) {
                                TextField("", text: $amount, prompt: Text("0").foregroundStyle(Palette.textTertiary))
                                    .keyboardType(.decimalPad).foregroundStyle(Palette.text)
                                    .accessibilityLabel("Recorded original amount")
                                    .padding(.horizontal, 14).padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                Menu {
                                    ForEach(["g", "eighth", "quarter", "half", "oz", "mg", "ml"], id: \.self) { u in
                                        Button(u) { unit = u }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(unit).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                                }
                                .accessibilityLabel("Recorded amount unit").accessibilityValue(unit)
                            }
                            if !amount.isEmpty && (JournalInputPolicy.decimal(amount) ?? 0) <= 0 {
                                Text("Enter a number greater than zero using your region’s decimal separator; omit unit text.")
                                    .font(.footnote).foregroundStyle(Palette.moodAngry)
                            }
                        }

                        // Cost
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Cost")
                            HStack(spacing: 8) {
                                Text("$").foregroundStyle(Palette.textSecondary)
                                TextField("", text: $cost, prompt: Text("0.00").foregroundStyle(Palette.textTertiary))
                                    .keyboardType(.decimalPad).foregroundStyle(Palette.text)
                                    .accessibilityLabel("Recorded cost in US dollars, optional")
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                            if parsedCost == nil {
                                Text("Enter a nonnegative cost without a currency symbol or group separators.")
                                    .font(.footnote).foregroundStyle(Palette.moodAngry)
                            }
                        }

                        // Date
                        DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                            FieldLabel(text: "When")
                        }
                        .tint(Palette.green)

                        PrimaryButton(title: "Add to Stash", icon: "plus") { save() }
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.5)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                    .seshReadableForm()
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .seshEditorPresentation()
        .interactiveDismissDisabled(hasEdits)
        .onAppear { if !didLoad { initialDate = date; didLoad = true } }
        .confirmationDialog("Discard this record draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
    }

    private func save() {
        guard canSave, let parsedCost, let parsedAmount = JournalInputPolicy.decimal(amount), parsedAmount > 0 else { return }
        saving = true
        let p = Purchase(date: date,
                         strain: JournalInputPolicy.trimmed(strain),
                         amount: parsedAmount,
                         unit: unit,
                         cost: parsedCost)
        session.addPurchase(p)
        Haptics.success()
        dismiss()
    }
}
