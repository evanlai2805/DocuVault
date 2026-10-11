import SwiftUI
import SwiftData
import DocuVaultCore

struct LibraryView: View {
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive }) private var vaultDocs: [StoredDocument]
    @State private var filter: Filter = .all

    enum Filter: Hashable { case all, contracts, receipts, chinese, cards }
    private let chips: [(Filter, String)] = [(.all, "All"), (.contracts, "Contracts"), (.receipts, "Receipts"), (.chinese, "中文"), (.cards, "Business cards")]

    private var filtered: [StoredDocument] {
        switch filter {
        case .all: docs
        case .contracts: docs.filter { $0.type == .contract || $0.type == .letter }
        case .receipts: docs.filter { $0.type == .receipt }
        case .chinese: docs.filter { $0.language != "en" }
        case .cards: docs.filter { $0.type == .businessCard }
        }
    }

    var body: some View {
        Group {
            if docs.isEmpty && vaultDocs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ChipRow(items: chips, selection: $filter).padding(.horizontal, -16)
                        summaryCard
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { doc in
                                NavigationLink(value: doc.id) { DocumentRow(doc: doc) }
                                    .buttonStyle(.plain)
                                if doc.id != filtered.last?.id { Divider().padding(.leading, 76) }
                            }
                        }
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Library")
        .navigationDestination(for: UUID.self) { id in
            if let doc = docs.first(where: { $0.id == id }) { DocumentDetailView(doc: doc) }
        }
    }

    private var summaryCard: some View {
        let pages = docs.reduce(0) { $0 + $1.pages.count }
        let zh = docs.filter { $0.language != "en" }.count
        let receipts = docs.filter { $0.type == .receipt }.count
        return GradientCard(style: .navy) {
            CardHeader(title: "All-time DocuVault", subtitle: "Documents · 文件 · Pages")
            HStack(alignment: .top, spacing: 10) {
                StatBlock(label: "Documents", value: "\(docs.count)", footnote: "\(zh) in Chinese")
                StatBlock(label: "Pages read", value: "\(pages)", footnote: "0 uploads")
            }
            HStack(alignment: .top, spacing: 10) {
                StatBlock(label: "Receipts", value: "\(receipts)", small: true)
                StatBlock(label: "In vault", value: "\(vaultDocs.count)", footnote: "Face ID", small: true)
            }
            .padding(.top, 14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 6) {
                Text("Nothing scanned yet").font(.system(size: 22, weight: .semibold))
                Text("Tap the blue Scan button to add your first document").font(.system(size: 17))
            }
            .foregroundStyle(Theme.Colors.ink2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DocumentRow: View {
    let doc: StoredDocument
    var body: some View {
        HStack(spacing: 16) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.rowTitle).lineLimit(1).foregroundStyle(Theme.Colors.ink)
                Text(subtitle).font(.rowSubtitle).foregroundStyle(Theme.Colors.ink2).lineLimit(1)
            }
            Spacer()
            if doc.sensitive { Image(systemName: "lock.fill").foregroundStyle(Theme.Colors.ink2) }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    private var subtitle: String {
        let lang = doc.language == "en" ? "EN" : (doc.language == "mixed" ? "Mixed" : "中文")
        return "\(doc.type.displayName) · \(lang) · \(doc.pages.count) page\(doc.pages.count == 1 ? "" : "s") · \(doc.capturedAt.formatted(.dateTime.day().month(.abbreviated)))"
    }
    @ViewBuilder private var thumb: some View {
        if let first = doc.orderedPages.first, let cg = PageStore.load(first.imageFileName) {
            Image(decorative: cg, scale: 1).resizable().scaledToFill()
                .frame(width: 44, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Theme.Colors.canvas).frame(width: 44, height: 56)
                .overlay(Image(systemName: "doc").foregroundStyle(Theme.Colors.ink2))
        }
    }
}
