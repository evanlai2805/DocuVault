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
    @State private var showAddPerson = false
    @State private var showTombstones = false
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
                        Button { showTombstones = true } label: { Label("Deleted by retention", systemImage: "clock.arrow.circlepath") }
                        Button { vault.lock() } label: { Label("Lock now", systemImage: "lock.fill") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showAddPerson) { AddPersonSheet() }
        .sheet(isPresented: $showExport) { NavigationStack { ExportView() } }
        .sheet(isPresented: $showTombstones) { NavigationStack { TombstoneList(tombstones: tombstones) } }
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

    private var unassigned: [StoredDocument] { docs.filter { $0.person == nil } }
    private var favourites: [StoredDocument] { docs.filter(\.favourite) }

    /// Vault home, the 1Password model (checkpoint 16): what needs you, favourites, categories, people.
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                let items = attention
                if !items.isEmpty { attentionCard(items) }

                if docs.isEmpty && people.isEmpty {
                    emptyState
                } else {
                    if !favourites.isEmpty {
                        sectionHeader("Favourites", trailing: "")
                        card { ForEach(favourites) { d in docLink(d, last: d.id == favourites.last?.id) } }
                    }

                    let cats = VaultCategory.allCases.filter { c in docs.contains(where: c.contains) }
                    if !cats.isEmpty {
                        sectionHeader("Categories", trailing: "")
                        card {
                            ForEach(cats, id: \.self) { c in
                                NavigationLink { VaultCategoryView(category: c) } label: {
                                    HStack(spacing: 12) {
                                        IconRow(title: c.title, subtitle: c.subtitle, systemImage: c.icon, light: true)
                                        Text("\(docs.filter(c.contains).count)").font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2)
                                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 4).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if c != cats.last { Divider().padding(.leading, 76) }
                            }
                        }
                    }

                    sectionHeader("People", trailing: "\(docs.count) document\(docs.count == 1 ? "" : "s")")
                    card {
                        ForEach(people) { p in
                            NavigationLink { PersonView(person: p) } label: { personRow(p) }.buttonStyle(.plain)
                            Divider().padding(.leading, 76)
                        }
                        Button { showAddPerson = true } label: {
                            IconRow(title: "Add person or entity", subtitle: "Me · Family · Client · Partner", systemImage: "plus", tint: Theme.Colors.accent)
                                .padding(.horizontal, 16)
                        }.buttonStyle(.plain)
                    }

                    if !unassigned.isEmpty {
                        sectionHeader("Unassigned", trailing: "Assign an owner")
                        card { ForEach(unassigned) { d in docLink(d, last: d.id == unassigned.last?.id) } }
                    }
                }
            }
            .padding(16)
        }
    }

    private func card<C: View>(@ViewBuilder _ rows: () -> C) -> some View {
        VStack(spacing: 0) { rows() }
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func docLink(_ d: StoredDocument, last: Bool) -> some View {
        Group {
            NavigationLink { DocumentDetailView(doc: d) } label: { VaultDocRow(doc: d) }.buttonStyle(.plain)
            if !last { Divider().padding(.leading, 76) }
        }
    }

    // MARK: Attention (checkpoint 16 Q5)

    struct AttentionItem: Identifiable {
        let doc: StoredDocument
        let line: String
        var id: UUID { doc.id }
    }

    /// Everything that needs Evan, one line per document: retention deleting soon, an expiry inside its
    /// window, or a check that failed. Retention first, then expiry, then checks.
    private var attention: [AttentionItem] {
        var out: [AttentionItem] = []
        var seen = Set<UUID>()
        func add(_ d: StoredDocument, _ line: String) { if seen.insert(d.id).inserted { out.append(.init(doc: d, line: line)) } }
        for w in RetentionManager.warnings(in: docs) { add(w.doc, "Deletes in \(w.daysLeft) d") }
        for d in docs {
            let fields = Dictionary(d.fields.map { ($0.key, vault.reveal($0) ?? "") }, uniquingKeysWith: { a, _ in a })
            if let phrase = DocumentExpiry.phrase(DocumentExpiry.status(type: d.type, fields: fields)) { add(d, phrase) }
        }
        for d in docs where !d.allChecksPassed { add(d, "A check failed") }
        return out
    }

    private func attentionCard(_ items: [AttentionItem]) -> some View {
        GradientCard(style: .red) {
            Text(items.count == 1 ? "1 needs attention" : "\(items.count) need attention").font(.system(size: 21, weight: .semibold))
            ForEach(items.prefix(5)) { item in
                NavigationLink { DocumentDetailView(doc: item.doc) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.doc.title).font(.system(size: 16, weight: .semibold))
                            Text([item.doc.person?.name, item.line].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).opacity(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).opacity(0.6)
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5).padding(.top, 5) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
