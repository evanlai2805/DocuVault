import SwiftUI
import SwiftData
import CryptoKit
import DocuVaultCore

/// Move library documents to an owner, or into the Vault (checkpoint 16).
struct MoveSheet: View {
    let docs: [StoredDocument]
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(VaultSession.self) private var vault
    @Query(sort: \StoredPerson.name) private var people: [StoredPerson]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { Task { await moveToVault() } } label: {
                        Label("Move to Vault", systemImage: "lock.fill")
                    }
                } footer: {
                    Text("Sealed behind Face ID. Vault documents never leave the phone and are not sent to Claude.")
                }
                Section("Owner") {
                    ForEach(people) { p in
                        Button { assign(p) } label: {
                            HStack {
                                Text(p.name).foregroundStyle(Theme.Colors.ink)
                                Spacer()
                                Text(p.kind.displayName).foregroundStyle(Theme.Colors.ink2)
                                if docs.allSatisfy({ $0.person?.id == p.id }) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                    }
                    Button { assign(nil) } label: { Text("No owner").foregroundStyle(Theme.Colors.ink) }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.Colors.danger)
                }
            }
            .navigationTitle(docs.count == 1 ? "Move" : "Move \(docs.count) documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func assign(_ p: StoredPerson?) {
        for d in docs { d.person = p }
        try? context.save()
        finish()
    }

    private func moveToVault() async {
        if !vault.isUnlocked { await vault.unlock(reason: "Move to the vault") }
        guard let key = vault.key else { error = vault.lastError ?? "Face ID is required to move documents to the vault."; return }
        var plain: [String] = [], sealed: [String] = []
        do {
            for d in docs {
                let files = try VaultMove.seal(d, key: key)
                plain += files.plain; sealed += files.sealed
            }
            try context.save()
            plain.forEach(PageStore.delete)
            if ExportManager.shared.syncFolder { ExportManager.shared.exportAll(context: context, vaultKey: key) }
            finish()
        } catch {
            context.rollback()
            sealed.forEach(PageStore.delete)
            self.error = "Could not move to the vault. Nothing was changed."
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

/// Seal a library document the way a vault save does: text, field values and page images with the
/// vault key. The document then counts as sensitive everywhere, CloudGate included.
@MainActor
enum VaultMove {
    /// Returns the plain page files (delete them once the store is saved) and the sealed copies
    /// (delete them instead if the save fails).
    static func seal(_ doc: StoredDocument, key: SymmetricKey) throws -> (plain: [String], sealed: [String]) {
        guard !doc.sensitive else { return ([], []) }
        // Seal into new values and files first; only touch the document once every step has succeeded.
        var copies: [String] = []
        do {
            let text = try VaultCrypto.seal(doc.fullText, key: key)
            let values = try doc.fields.map { f in (f, try VaultCrypto.seal(f.value, key: key)) }
            var pages: [(StoredPage, String)] = []
            for p in doc.pages where !PageStore.isSealed(p.imageFileName) {
                let name = try PageStore.sealedCopy(p.imageFileName, key: key)
                copies.append(name)
                pages.append((p, name))
            }
            // Same shape as a fresh vault save: no plain text, OCR boxes or summary left behind.
            doc.sealedText = text
            doc.fullText = ""
            doc.summaryJSON = nil
            for (f, sealed) in values { f.sealedValue = sealed; f.value = "" }
            var plain: [String] = []
            for (p, name) in pages {
                plain.append(p.imageFileName)
                p.imageFileName = name
                p.text = ""
                p.ocrJSON = nil
            }
            doc.sensitive = true
            doc.favourite = false
            return (plain, copies)
        } catch {
            for name in copies { PageStore.delete(name) }
            throw error
        }
    }
}

/// Library documents deleted by hand, kept 30 days (checkpoint 16 Q4). Tap for Restore or Delete now.
struct RecentlyDeletedView: View {
    @Query(filter: #Predicate<StoredDocument> { $0.deletedAt != nil }, sort: \StoredDocument.capturedAt, order: .reverse)
    private var docs: [StoredDocument]
    @Environment(\.modelContext) private var context
    @State private var picked: StoredDocument?
    @State private var confirmAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Documents stay here for \(RetentionManager.recentlyDeletedDays) days, then are deleted for good.")
                    .font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
                if docs.isEmpty {
                    Text("Nothing here").font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(docs) { d in
                            Button { picked = d } label: {
                                HStack {
                                    DocumentRow(doc: d, showsChevron: false)
                                    Text(daysLeft(d)).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2).padding(.trailing, 16)
                                }
                            }
                            .buttonStyle(.plain)
                            if d.id != docs.last?.id { Divider().padding(.leading, 76) }
                        }
                    }
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Recently deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !docs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Delete all", role: .destructive) { confirmAll = true } }
            }
        }
        .confirmationDialog(picked?.title ?? "", isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }), titleVisibility: .visible) {
            Button("Restore") { if let d = picked { RetentionManager.restore(d, context: context) } }
            Button("Delete now", role: .destructive) {
                if let d = picked { RetentionManager.delete(d, context: context); try? context.save() }
            }
        }
        .confirmationDialog("Delete \(docs.count) document\(docs.count == 1 ? "" : "s") for good?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                for d in docs { RetentionManager.delete(d, context: context) }
                try? context.save()
            }
        }
    }

    private func daysLeft(_ d: StoredDocument) -> String {
        guard let at = d.deletedAt else { return "" }
        let left = RetentionManager.recentlyDeletedDays - (Calendar.current.dateComponents([.day], from: at, to: Date()).day ?? 0)
        return "\(max(left, 0)) d"
    }
}
