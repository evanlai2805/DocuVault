import SwiftUI
import SwiftData

/// Full-text search across titles and OCR text. English and Chinese substrings both work.
/// The vault is searched too, only while it is open (Evan, 13 Oct): locked, it shows one Face ID row
/// that says nothing about what is inside.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSession.self) private var vault
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse) private var vaultDocs: [StoredDocument]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [StoredDocument] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return docs.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.fullText.localizedCaseInsensitiveContains(q) }
    }

    /// Vault matches on title, owner and the sealed text, opened in memory with the vault key.
    private var vaultResults: [StoredDocument] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, vault.isUnlocked else { return [] }
        return vaultDocs.filter { d in
            d.title.localizedCaseInsensitiveContains(q)
                || (d.person?.name.localizedCaseInsensitiveContains(q) ?? false)
                || (vault.revealText(d)?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.ink2)
                TextField("Title, text, 中文…", text: $query)
                    .font(.system(size: 21))
                    .focused($focused)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.ink2) }
                }
            }
            .padding(.horizontal, 18).frame(height: 60)
            .background(Theme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
            .padding(16)

            if query.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("Search your library").font(.system(size: 22, weight: .semibold))
                    Text("Matches titles and recognised text, and the Vault once Face ID opens it.").font(.system(size: 17)).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                .foregroundStyle(Theme.Colors.ink2)
                Spacer()
            } else {
                ScrollView {
                  VStack(alignment: .leading, spacing: 16) {
                    if results.isEmpty && vault.isUnlocked && vaultResults.isEmpty {
                        Text("No matches").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    if !results.isEmpty {
                    sectionLabel("Library")
                    LazyVStack(spacing: 0) {
                        ForEach(results) { doc in
                            NavigationLink { DocumentDetailView(doc: doc) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    DocumentRow(doc: doc)
                                    if let snippet = snippet(doc) {
                                        Text(snippet).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
                                            .lineLimit(2).padding(.horizontal, 16).padding(.bottom, 12)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    vaultSection
                  }
                  .padding(.horizontal, 16)
                }
            }
        }
        .background(Theme.Colors.surface)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .onAppear { focused = true }
    }

    @ViewBuilder private var vaultSection: some View {
        if !vault.isUnlocked {
            sectionLabel("Vault")
            Button { Task { await vault.unlock(reason: "Search the vault") } } label: {
                CardRow(title: "Search the Vault", icon: "lock.fill", tint: Theme.Colors.graphite, value: "Face ID", chevron: true)
            }
            .buttonStyle(.plain)
            .background(Theme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if !vaultResults.isEmpty {
            sectionLabel("Vault")
            VStack(spacing: 0) {
                ForEach(vaultResults) { d in
                    NavigationLink { DocumentDetailView(doc: d) } label: { VaultDocRow(doc: d) }.buttonStyle(.plain)
                    if d.id != vaultResults.last?.id { Divider().padding(.leading, 76) }
                }
            }
            .background(Theme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 14)).tracking(0.5).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
    }

    private func snippet(_ doc: StoredDocument) -> String? {
        let text = doc.fullText
        guard let r = text.range(of: query, options: [.caseInsensitive]) else { return nil }
        let start = text.index(r.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[start..<end].replacingOccurrences(of: "\n", with: " ") + "…"
    }
}
