import SwiftUI
import SwiftData
import DocuVaultCore

/// 1Password's categories, for the documents DocuVault seals (checkpoint 16).
enum VaultCategory: CaseIterable, Hashable {
    case passports, idCards, bankCards, other

    var title: String {
        switch self {
        case .passports: "Passports"
        case .idCards: "ID cards"
        case .bankCards: "Bank cards"
        case .other: "Other"
        }
    }
    var subtitle: String? { self == .idCards ? "NRIC / FIN · China ID" : nil }
    var icon: String {
        switch self {
        case .passports: "airplane"
        case .idCards: "person.text.rectangle"
        case .bankCards: "creditcard"
        case .other: "doc.text"
        }
    }

    func contains(_ d: StoredDocument) -> Bool {
        switch self {
        case .passports: d.type == .passport
        case .idCards: d.type == .nric || d.type == .chinaID
        case .bankCards: d.type == .bankCard
        case .other: ![.passport, .nric, .chinaID, .bankCard].contains(d.type)
        }
    }
}

struct VaultCategoryView: View {
    let category: VaultCategory
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]

    var body: some View {
        let items = docs.filter(category.contains)
        ScrollView {
            VStack(spacing: 0) {
                ForEach(items) { d in
                    NavigationLink { DocumentDetailView(doc: d) } label: { VaultDocRow(doc: d) }.buttonStyle(.plain)
                    if d.id != items.last?.id { Divider().padding(.leading, 76) }
                }
            }
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A vault row: type icon, title, the document number (or •last4 for a card), star when a favourite,
/// and the red flag when a check failed.
struct VaultDocRow: View {
    let doc: StoredDocument
    @Environment(VaultSession.self) private var vault

    var body: some View {
        HStack(spacing: 12) {
            IconRow(title: doc.title, subtitle: subtitle, systemImage: VaultDocRow.icon(doc.type), light: true)
            if doc.favourite { Image(systemName: "star.fill").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent) }
            if !doc.allChecksPassed { ReviewFlag() }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 4).contentShape(Rectangle())
    }

    static func icon(_ t: DocumentType) -> String {
        switch t {
        case .passport: "airplane"
        case .nric, .chinaID: "person.text.rectangle"
        case .bankCard: "creditcard"
        default: "doc.text"
        }
    }

    private var subtitle: String {
        let keys = ["passportNumber", "nric", "idNumber", "last4"]
        if let f = doc.orderedFields.first(where: { keys.contains($0.key) }), let v = vault.reveal(f), !v.isEmpty {
            return f.key == "last4" ? "•\(v)" : v
        }
        return [doc.person?.name, doc.type.displayName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The one-line records left when retention deletes a client document. Moved off the Vault home
/// into the menu (checkpoint 16).
struct TombstoneList: View {
    let tombstones: [StoredTombstone]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CardPage {
            Text("When a client's retention period ends, the document is deleted and one line stays here and in index.md.")
                .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
            CardSection {
                if tombstones.isEmpty { CardRow(title: "Nothing deleted by retention yet") }
                ForEach(tombstones) { t in
                    Text(DisplayText.displayDates(in: DisplayText.capitalisedSegments(String(t.line.replacingOccurrences(of: "~~", with: "").dropFirst(2)))))
                        .font(.system(size: 15)).padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Deleted by retention")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// The vault as a folder inside the Library (Evan, 13 Oct). Asks for Face ID on open; once unlocked,
/// the documents by category, the same rows as the Vault tab.
struct VaultFolderView: View {
    @Environment(VaultSession.self) private var vault
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse)
    private var docs: [StoredDocument]
    @State private var unlocking = false

    var body: some View {
        Group {
            if vault.isUnlocked {
                CardPage {
                    if docs.isEmpty {
                        Text("Nothing in the vault yet").font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(VaultCategory.allCases.filter { c in docs.contains(where: c.contains) }, id: \.self) { c in
                        CardSection(title: c.title) {
                            ForEach(docs.filter(c.contains)) { d in
                                NavigationLink { DocumentDetailView(doc: d) } label: { VaultDocRow(doc: d) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "faceid").font(.system(size: 40, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 80, height: 80).background(Theme.Colors.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("Vault locked").font(.system(size: 22, weight: .semibold))
                    if let e = vault.lastError { Text(e).font(.system(size: 14)).foregroundStyle(Theme.Colors.danger).multilineTextAlignment(.center).padding(.horizontal, 32) }
                    Button { Task { await unlock() } } label: {
                        Text(unlocking ? "Unlocking…" : "Unlock").font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .foregroundStyle(.white).accentSheen(in: Capsule())
                    }
                    .disabled(unlocking)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.canvas)
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !vault.isUnlocked { await unlock() } }
    }

    private func unlock() async {
        unlocking = true
        await vault.unlock(reason: "Open the vault")
        unlocking = false
    }
}
