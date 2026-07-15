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

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Your Stash", onBack: { dismiss() }) {
                    Button { showAdd = true; Haptics.tap() } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)

                if session.purchases.isEmpty {
                    EmptyStateView(icon: "shippingbox",
                                   title: "Nothing in your stash",
                                   message: "Log what you bought and how much. Sessions will draw it down as you smoke.",
                                   actionTitle: "Add a purchase", actionIcon: "plus") { showAdd = true }
                    Spacer()
                } else {
                    List {
                        // In-stock first
                        let inStock = session.purchases.filter { !$0.isEmpty }
                        let empties = session.purchases.filter { $0.isEmpty }
                        if !inStock.isEmpty {
                            Section {
                                ForEach(inStock) { purchaseRow($0) }
                                    .onDelete { idx in idx.map { inStock[$0] }.forEach(session.deletePurchase) }
                            } header: { Text("In Stock").foregroundStyle(Palette.textTertiary) }
                            .listRowBackground(Palette.card)
                        }
                        if !empties.isEmpty {
                            Section {
                                ForEach(empties) { purchaseRow($0) }
                                    .onDelete { idx in idx.map { empties[$0] }.forEach(session.deletePurchase) }
                            } header: { Text("Used Up").foregroundStyle(Palette.textTertiary) }
                            .listRowBackground(Palette.card)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddPurchaseView().environment(session) }
    }

    private func purchaseRow(_ p: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.strain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text(String(format: "$%.0f", p.cost)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.gold)
            }
            HStack {
                Text(p.amountLine).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(Fmt.shortDate(p.date)).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            // Remaining bar
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.field).frame(height: 6)
                Capsule().fill(p.isEmpty ? Palette.textTertiary : Palette.green).frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: p.amount > 0 ? max(0.02, p.remaining / p.amount) : 0, anchor: .leading)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
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

    private var canSave: Bool {
        !strain.trimmingCharacters(in: .whitespaces).isEmpty && (Double(amount) ?? 0) > 0
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Add Purchase", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Strain with type-ahead
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Strain")
                            InputField(label: "", placeholder: "Strain name…", value: $strain)
                            if !strain.isEmpty {
                                let matches = strains.strains.filter { $0.name.lowercased().contains(strain.lowercased()) }.prefix(4)
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
                            }
                        }

                        // Cost
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Cost")
                            HStack(spacing: 8) {
                                Text("$").foregroundStyle(Palette.textSecondary)
                                TextField("", text: $cost, prompt: Text("0.00").foregroundStyle(Palette.textTertiary))
                                    .keyboardType(.decimalPad).foregroundStyle(Palette.text)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
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
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func save() {
        let p = Purchase(date: date,
                         strain: strain.trimmingCharacters(in: .whitespaces),
                         amount: Double(amount) ?? 0,
                         unit: unit,
                         cost: Double(cost.filter { "0123456789.".contains($0) }) ?? 0)
        session.addPurchase(p)
        Haptics.success()
        dismiss()
    }
}
