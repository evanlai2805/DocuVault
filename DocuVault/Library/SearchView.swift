import SwiftUI
import SwiftData

/// Full-text search across titles and OCR text. English and Chinese substrings both work.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [StoredDocument] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return docs.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.fullText.localizedCaseInsensitiveContains(q) }
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
                    Text("Matches titles and recognised text. Vault documents are not searched.").font(.system(size: 17)).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                .foregroundStyle(Theme.Colors.ink2)
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text("No matches").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
                Spacer()
            } else {
                ScrollView {
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

    private func snippet(_ doc: StoredDocument) -> String? {
        let text = doc.fullText
        guard let r = text.range(of: query, options: [.caseInsensitive]) else { return nil }
        let start = text.index(r.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[start..<end].replacingOccurrences(of: "\n", with: " ") + "…"
    }
}
