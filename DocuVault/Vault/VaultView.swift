import SwiftUI
import SwiftData
import DocuVaultCore

/// Vault tab: Face ID gate → people list, retention card, tombstones.
struct VaultView: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredPerson.createdAt) private var people: [StoredPerson]
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]
    @Query(sort: \StoredTombstone.deletedAt, order: .reverse) private var tombstones: [StoredTombstone]
    @State private var filter: PersonKind? = nil
    @State private var showAddPerson = false
    @State private var showExport = false
    @State private var unlocking = false

    var body: some View {
        Group {
            if vault.isUnlocked { content } else { lockScreen }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Vault")
        .toolbar {
            if vault.isUnlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        Button { vault.lock() } label: { Label("Lock now", systemImage: "lock.fill") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showAddPerson) { AddPersonSheet() }
        .sheet(isPresented: $showExport) { NavigationStack { ExportView() } }
        .task { if !vault.isUnlocked && !unlocking { await tryUnlock() } }
    }

    private func tryUnlock() async {
        unlocking = true
        await vault.unlock()
        unlocking = false
        if vault.isUnlocked { RetentionManager.sweep(context: context) }
    }

    private var lockScreen: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "faceid").font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white).frame(width: 88, height: 88)
                .background(Theme.Colors.graphite).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Vault locked").font(.system(size: 22, weight: .semibold))
            Text("Face ID to open").font(.system(size: 16)).foregroundStyle(Theme.Colors.ink2)
            if let e = vault.lastError { Text(e).font(.system(size: 14)).foregroundStyle(Theme.Colors.danger).multilineTextAlignment(.center).padding(.horizontal, 32) }
            Button { Task { await tryUnlock() } } label: {
                Text(unlocking ? "Unlocking…" : "Unlock").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Theme.Colors.accent).foregroundStyle(.white).clipShape(Capsule())
            }
            .disabled(unlocking)
            Text("Locks again \(Int(VaultSession.autoLockSeconds)) s after you leave").font(.system(size: 13)).foregroundStyle(Theme.Colors.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var filtered: [StoredPerson] { filter.map { k in people.filter { $0.kind == k } } ?? people }
    private var unassigned: [StoredDocument] { docs.filter { $0.person == nil } }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChipRow(items: [(Optional<PersonKind>.none, "Everyone")] + PersonKind.allCases.map { (Optional($0), $0.displayName) },
                        selection: $filter)
                    .padding(.horizontal, -16)

                let warnings = RetentionManager.warnings(in: docs)
                if let w = warnings.first {
                    GradientCard(style: .red) {
                        Text("\(warnings.count)").font(.system(size: 44, weight: .bold)).monospacedDigit()
                        Text(warnings.count == 1 ? "document expiring soon" : "documents expiring soon").font(.system(size: 21, weight: .semibold))
                        Text("\(w.doc.person?.name ?? "Client") · \(w.doc.title) · deletes in \(w.daysLeft) d").font(.system(size: 16)).opacity(0.85)
                        HStack(spacing: 8) {
                            ForEach(Retention.Action.allCases, id: \.self) { a in
                                Button(a.rawValue) { RetentionManager.apply(a, to: w.doc, context: context) }
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(Color.white.opacity(a == .deleteNow ? 0.08 : 0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.top, 14)
                    }
                }

                if people.isEmpty && unassigned.isEmpty {
                    emptyState
                } else {
                    sectionHeader("People", trailing: "\(docs.count) document\(docs.count == 1 ? "" : "s")")
                    VStack(spacing: 0) {
                        ForEach(filtered) { p in
                            NavigationLink { PersonView(person: p) } label: { personRow(p) }.buttonStyle(.plain)
                            if p.id != filtered.last?.id { Divider().padding(.leading, 76) }
                        }
                        Button { showAddPerson = true } label: {
                            IconRow(title: "Add person or entity", subtitle: "Me · Family · Client · Partner", systemImage: "plus", tint: Theme.Colors.accent)
                                .padding(.horizontal, 16)
                        }.buttonStyle(.plain)
                    }
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if !unassigned.isEmpty {
                        sectionHeader("Unassigned", trailing: "assign an owner")
                        VStack(spacing: 0) {
                            ForEach(unassigned) { d in
                                NavigationLink { DocumentDetailView(doc: d) } label: { DocumentRow(doc: d) }.buttonStyle(.plain)
                                if d.id != unassigned.last?.id { Divider().padding(.leading, 76) }
                            }
                        }
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                if !tombstones.isEmpty {
                    sectionHeader("Deleted by retention", trailing: "\(tombstones.count)")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tombstones.prefix(10)) { t in
                            Text(t.line.replacingOccurrences(of: "~~", with: "").dropFirst(2)).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
    }

    private func personRow(_ p: StoredPerson) -> some View {
        let n = p.documents.count
        let types = Array(Set(p.documents.map { $0.type.displayName })).sorted().prefix(3).joined(separator: " · ")
        let icon = switch p.kind { case .me: "person.fill"; case .family: "person.2.fill"; case .client: "building.2.fill"; case .partner: "handshake.fill"; case .other: "person.crop.circle" }
        let nearest = p.documents.compactMap { d -> Int? in if case .warning(let l) = Retention.status(expiresAt: d.expiresAt) { return l }; return nil }.min()
        return HStack(spacing: 16) {
            IconRow(title: p.name, subtitle: n == 0 ? "No documents yet" : (types.isEmpty ? "\(n) documents" : types), systemImage: icon, light: true)
            if let nearest { StatusPill(text: "\(p.kind.displayName) · \(nearest) d", tone: .unverified) }
            else { StatusPill(text: p.kind.displayName, tone: .neutral) }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack { Text(title.uppercased()).tracking(0.5); Spacer(); Text(trailing) }
            .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
            .padding(.horizontal, 4).padding(.bottom, -8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing in the vault yet").font(.system(size: 22, weight: .semibold))
            Text("Scan a passport, ID or card. It lands here automatically.").font(.system(size: 16)).multilineTextAlignment(.center)
            Button { showAddPerson = true } label: { Text("Add a person first").font(.system(size: 16, weight: .semibold)) }.padding(.top, 6)
        }
        .foregroundStyle(Theme.Colors.ink2)
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kind: PersonKind = .client
    @State private var retention: Int? = RetentionPolicy.clientDefaultDays

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (person or entity)", text: $name)
                    Picker("Kind", selection: $kind) { ForEach(PersonKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                        .onChange(of: kind) { _, k in retention = k.defaultAutoExpireDays }
                }
                Section("Retention") {
                    Picker("Auto-delete after", selection: $retention) {
                        Text("Never").tag(Optional<Int>.none)
                        Text("30 days").tag(Optional(30)); Text("60 days").tag(Optional(60)); Text("90 days").tag(Optional(90))
                    }
                    Text("Clients default to \(RetentionPolicy.clientDefaultDays) days with a warning \(RetentionPolicy.warnDaysBefore) days before. A one-line record stays in index.md after deletion.")
                        .font(.footnote).foregroundStyle(Theme.Colors.ink2)
                }
            }
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(StoredPerson(name: name.trimmingCharacters(in: .whitespaces), kind: kind, retentionDays: retention))
                        try? context.save(); dismiss()
                    }
                    .fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
