import SwiftUI
import SwiftData
import DocuVaultCore

/// One person or entity: summary card, their documents, shared fields (feed the keyboard in Phase 5).
struct PersonView: View {
    @Bindable var person: StoredPerson
    @Environment(VaultSession.self) private var vault
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editingShared = false
    @State private var confirmDelete = false

    private var docs: [StoredDocument] { person.documents.sorted { $0.capturedAt > $1.capturedAt } }
    private var allPass: Bool { docs.allSatisfy(\.allChecksPassed) }
    private var anyWarning: Bool { docs.contains { if case .warning = Retention.status(expiresAt: $0.expiresAt) { return true }; return false } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GradientCard(style: anyWarning ? .red : (allPass ? .green : .graphite)) {
                    CardHeader(title: person.fullName.isEmpty ? person.name : person.fullName,
                               subtitle: "\(person.kind.displayName) · \(docs.count) document\(docs.count == 1 ? "" : "s") · \(allPass ? "All checks pass" : "A check failed")")
                    HStack(alignment: .top, spacing: 10) {
                        StatBlock(label: "Next expiry", value: nextExpiry ?? "—", footnote: nextExpiryNote, small: true)
                        StatBlock(label: "Retention", value: person.retentionDays.map { "\($0) d" } ?? "Never", footnote: person.kind.displayName, small: true)
                    }
                    CardButton(title: "Autofill shared fields from documents", systemImage: "wand.and.stars") { autofillShared() }
                }

                sectionHeader("Documents", trailing: "")
                if docs.isEmpty {
                    Text("No documents yet. Scan one and pick \(person.name) as the owner.").font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        ForEach(docs) { d in
                            NavigationLink { DocumentDetailView(doc: d) } label: { docRow(d) }.buttonStyle(.plain)
                            if d.id != docs.last?.id { Divider().padding(.leading, 76) }
                        }
                    }
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                sectionHeader("Shared fields", trailing: "Used by the keyboard")
                VStack(spacing: 0) {
                    shared("Full name", person.fullName)
                    Divider().padding(.leading, 16)
                    shared("Address", person.address)
                    Divider().padding(.leading, 16)
                    shared("Phone", person.phone)
                    Divider().padding(.leading, 16)
                    shared("Email", person.email)
                }
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture { editingShared = true }
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editingShared = true } label: { Label("Edit shared fields", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete person", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingShared) { SharedFieldsSheet(person: person) }
        .confirmationDialog("Delete \(person.name)? Their \(docs.count) document(s) become unassigned.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete person", role: .destructive) { context.delete(person); try? context.save(); dismiss() }
        }
    }

    /// Earliest ISO expiry across the person's documents, shown as 12/MAR/1990. Card expiries (MM/YY)
    /// and free text such as 长期 are skipped, since a string sort only orders ISO dates correctly.
    private var nextExpiry: String? {
        docs.compactMap { d in d.orderedFields.first { ["expiry", "validTo"].contains($0.key) }.flatMap { vault.reveal($0) } }
            .filter { TextRules.firstISODate(in: $0) == $0 }.sorted().first.map(FillFormats.display)
    }
    private var nextExpiryNote: String? {
        guard let e = nextExpiry, e.count >= 4 else { return nil }
        return "Earliest document"
    }

    private func docRow(_ d: StoredDocument) -> some View {
        let icon = switch d.type { case .passport: "airplane"; case .nric, .chinaID: "person.text.rectangle"; case .bankCard: "creditcard"; default: "doc.text" }
        let sub: String = {
            let keys = ["passportNumber", "nric", "idNumber", "last4"]
            if let f = d.orderedFields.first(where: { keys.contains($0.key) }), let v = vault.reveal(f), !v.isEmpty {
                return f.key == "last4" ? "•\(v)" : v
            }
            return d.type.displayName
        }()
        return HStack(spacing: 12) {
            IconRow(title: d.title, subtitle: sub, systemImage: icon, light: true)
            StatusPill(text: d.checksTotal == 0 ? "—" : "\(d.checksPassed)/\(d.checksTotal)", tone: d.checksTotal == 0 ? .neutral : (d.allChecksPassed ? .verified : .missing))
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 4).contentShape(Rectangle())
    }

    private func shared(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).frame(width: 100, alignment: .leading)
            Text(value.isEmpty ? "—" : value).font(.system(size: 16, design: .monospaced)).foregroundStyle(value.isEmpty ? Theme.Colors.danger : Theme.Colors.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer()
            StatusPill(text: value.isEmpty ? "Add" : "Set", tone: value.isEmpty ? .missing : .info)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack { Text(title.uppercased()).tracking(0.5); Spacer(); Text(trailing) }
            .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4).padding(.bottom, -8)
    }

    /// Fill empty shared fields from the person's documents: name from passport/NRIC/ID, address from NRIC/ID, phone/email from a business card.
    private func autofillShared() {
        func first(_ keys: [String], types: [DocumentType]) -> String? {
            for d in docs where types.contains(d.type) {
                for k in keys {
                    if let f = d.orderedFields.first(where: { $0.key == k }), let v = vault.reveal(f), !v.isEmpty { return v }
                }
            }
            return nil
        }
        if person.fullName.isEmpty {
            if let s = first(["surname"], types: [.passport]), let g = first(["givenNames"], types: [.passport]) { person.fullName = "\(g) \(s)" }
            else if let n = first(["name", "namePinyin"], types: [.nric, .chinaID, .businessCard]) { person.fullName = n }
        }
        if person.address.isEmpty, let a = first(["address"], types: [.nric, .chinaID]) { person.address = a }
        if person.phone.isEmpty, let p = first(["phone"], types: [.businessCard]) { person.phone = p }
        if person.email.isEmpty, let e = first(["email"], types: [.businessCard]) { person.email = e }
        try? context.save()
    }
}

struct SharedFieldsSheet: View {
    @Bindable var person: StoredPerson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var body: some View {
        NavigationStack {
            Form {
                Section("Shared fields") {
                    TextField("Full name", text: $person.fullName)
                    TextField("Address", text: $person.address, axis: .vertical)
                    TextField("Phone", text: $person.phone).keyboardType(.phonePad)
                    TextField("Email", text: $person.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section("Person") {
                    TextField("Short name", text: $person.name)
                    Picker("Kind", selection: $person.kind) { ForEach(PersonKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                    Picker("Auto-delete after", selection: $person.retentionDays) {
                        Text("Never").tag(Optional<Int>.none); Text("30 days").tag(Optional(30)); Text("60 days").tag(Optional(60)); Text("90 days").tag(Optional(90))
                    }
                }
            }
            .navigationTitle("Edit \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { try? context.save(); dismiss() }.fontWeight(.semibold) } }
        }
    }
}
