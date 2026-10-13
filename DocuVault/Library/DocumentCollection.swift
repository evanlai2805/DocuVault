import SwiftUI
import SwiftData
import DocuVaultCore

/// A list or grid of library documents, the Files way (checkpoint 16): sort, list/grid, select mode
/// with an action bar, and a long-press menu with a page preview. Used by Recents and every folder.
struct DocumentCollection: View {
    let docs: [StoredDocument]
    var groupByRecency = false

    @Environment(AppChrome.self) private var chrome
    @Environment(VaultSession.self) private var vault
    @Environment(\.modelContext) private var context
    @AppStorage("library.layout") private var layout: Layout = .list
    @AppStorage("library.sort") private var sort: Sort = .date
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var moving: [StoredDocument] = []
    @State private var confirmDelete = false
    @State private var renaming: StoredDocument?
    @State private var newTitle = ""
    @State private var moveError: String?

    enum Layout: String { case list, grid }
    enum Sort: String, CaseIterable { case date = "Date", name = "Name", type = "Type" }

    private var sorted: [StoredDocument] {
        switch sort {
        case .date: docs.sorted { $0.capturedAt > $1.capturedAt }
        case .name: docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .type: docs.sorted { ($0.type.displayName, $1.capturedAt) < ($1.type.displayName, $0.capturedAt) }
        }
    }

    /// Today · This week · then one group per month, as Files groups Recents. Only when sorted by date.
    private var groups: [(String, [StoredDocument])] {
        guard groupByRecency, sort == .date else { return [("", sorted)] }
        let cal = Calendar.current
        let now = Date()
        var out: [(String, [StoredDocument])] = []
        for d in sorted {
            let key: String
            if cal.isDateInToday(d.capturedAt) { key = "Today" }
            else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d.capturedAt), to: cal.startOfDay(for: now)).day, days < 7 { key = "This week" }
            else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_GB")
                f.dateFormat = cal.component(.year, from: d.capturedAt) == cal.component(.year, from: now) ? "MMMM" : "MMMM yyyy"
                key = f.string(from: d.capturedAt)
            }
            if out.last?.0 == key { out[out.count - 1].1.append(d) } else { out.append((key, [d])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tools
            if docs.isEmpty {
                Text("No documents").font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(groups, id: \.0) { title, items in
                if !title.isEmpty {
                    Text(title.uppercased()).font(.system(size: 14)).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                        .padding(.horizontal, 4).padding(.bottom, -6)
                }
                switch layout {
                case .list: list(items)
                case .grid: grid(items)
                }
            }
        }
        .toolbar {
            if selecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { endSelecting() }.fontWeight(.semibold)
                }
            }
        }
        .onChange(of: selected) { publishBar() }
        .onChange(of: selecting) { publishBar() }
        .onDisappear { endSelecting() }
        .sheet(isPresented: Binding(get: { !moving.isEmpty }, set: { if !$0 { moving = [] } })) {
            MoveSheet(docs: moving) { endSelecting() }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for d in docs where selected.contains(d.id) { RetentionManager.trash(d, context: context) }
                endSelecting()
            }
        } message: { Text("They stay in Recently deleted for \(RetentionManager.recentlyDeletedDays) days.") }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                if let d = renaming, !t.isEmpty { d.title = t; try? context.save() }
            }
        }
    }

    private var deleteTitle: String {
        selected.count == 1 ? "Delete 1 document?" : "Delete \(selected.count) documents?"
    }

    // MARK: Tools

    private var tools: some View {
        HStack(spacing: 16) {
            Text(selecting ? "\(selected.count) selected" : "\(docs.count) document\(docs.count == 1 ? "" : "s")")
                .font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
            Spacer()
            if !selecting {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                Button { layout = layout == .list ? .grid : .list } label: {
                    Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                }
                Menu {
                    Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
                } label: { Image(systemName: "ellipsis.circle") }
            } else {
                Button(selected.count == docs.count ? "Deselect all" : "Select all") {
                    selected = selected.count == docs.count ? [] : Set(docs.map(\.id))
                }
            }
        }
        .font(.system(size: 18))
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, 4)
    }

    // MARK: List and grid

    private func list(_ items: [StoredDocument]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { doc in
                item(doc) {
                    HStack(spacing: 0) {
                        if selecting { checkmark(doc).padding(.leading, 16) }
                        DocumentRow(doc: doc, showsChevron: !selecting)
                    }
                }
                if doc.id != items.last?.id { Divider().padding(.leading, selecting ? 116 : 76) }
            }
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func grid(_ items: [StoredDocument]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 16) {
            ForEach(items) { doc in
                item(doc) {
                    VStack(spacing: 4) {
                        PageThumb(doc: doc)
                            .frame(height: 124)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected.contains(doc.id) ? Theme.Colors.accent : Theme.Colors.hairline, lineWidth: selected.contains(doc.id) ? 2 : 0.5))
                            .overlay(alignment: .bottomTrailing) { if selecting { checkmark(doc).padding(6) } }
                        Text(doc.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(Theme.Colors.ink)
                        Text(doc.capturedAt.dvDisplay()).font(.system(size: 12)).foregroundStyle(Theme.Colors.ink2)
                    }
                }
            }
        }
    }

    /// Tap opens, or toggles in select mode. Long press: page preview and the Files menu.
    @ViewBuilder private func item<Label: View>(_ doc: StoredDocument, @ViewBuilder _ label: () -> Label) -> some View {
        if selecting {
            Button { toggle(doc) } label: { label().contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            NavigationLink(value: doc.id) { label().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .contextMenu { menu(doc) } preview: { DocumentPreview(doc: doc) }
        }
    }

    @ViewBuilder private func menu(_ doc: StoredDocument) -> some View {
        ShareLink(item: doc.fullText) { Label("Share", systemImage: "square.and.arrow.up") }
        Button { newTitle = doc.title; renaming = doc } label: { Label("Rename", systemImage: "pencil") }
        Button { Clipboard.copy(doc.fullText, sensitive: false) } label: { Label("Copy text", systemImage: "doc.on.doc") }
        Button { moving = [doc] } label: { Label("Move", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { RetentionManager.trash(doc, context: context) } label: { Label("Delete", systemImage: "trash") }
    }

    private func checkmark(_ doc: StoredDocument) -> some View {
        let on = selected.contains(doc.id)
        return Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(on ? Theme.Colors.accent : Theme.Colors.ink2)
            .background(Circle().fill(.white).padding(2))
    }

    private func toggle(_ doc: StoredDocument) {
        if selected.contains(doc.id) { selected.remove(doc.id) } else { selected.insert(doc.id) }
    }

    // MARK: Action bar

    private func endSelecting() {
        selecting = false
        selected = []
        moving = []
        chrome.selection = nil
    }

    private func publishBar() {
        guard selecting else { chrome.selection = nil; return }
        let picked = sorted.filter { selected.contains($0.id) }
        chrome.selection = .init(
            count: picked.count,
            shareText: picked.map { "\($0.title)\n\n\($0.fullText)" }.joined(separator: "\n\n"),
            csvURL: !picked.isEmpty && picked.allSatisfy { $0.type == .receipt } ? ReceiptCSV.file(for: picked) : nil,
            move: { moving = picked },
            delete: { confirmDelete = true }
        )
    }
}

/// First page of a document, or a document glyph when it has none. Library pages are never sealed.
struct PageThumb: View {
    let doc: StoredDocument
    var body: some View {
        Group {
            if let first = doc.orderedPages.first, let cg = PageStore.load(first.imageFileName) {
                Image(decorative: cg, scale: 1).resizable().scaledToFill()
            } else {
                Theme.Colors.surface.overlay(Image(systemName: "doc.text").font(.system(size: 24)).foregroundStyle(Theme.Colors.ink2))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The long-press preview: the first page at reading size.
struct DocumentPreview: View {
    let doc: StoredDocument
    var body: some View {
        if let first = doc.orderedPages.first, let cg = PageStore.load(first.imageFileName) {
            Image(decorative: cg, scale: 1).resizable().scaledToFit().frame(maxWidth: 360, maxHeight: 480)
        } else {
            Text(doc.fullText.prefix(600)).font(.system(size: 13)).padding(16).frame(width: 320, alignment: .topLeading)
        }
    }
}

/// expenses.csv for a selection of receipts, in the same columns as the export mirror.
enum ReceiptCSV {
    static func file(for docs: [StoredDocument]) -> URL? {
        var csv = ""
        for d in docs where d.type == .receipt {
            let r = ExtractionResult(type: .receipt, fields: d.orderedFields.map(\.asExtracted))
            csv = MarkdownExporter.appendCSV(existing: csv, row: ReceiptExtractor.csvRow(r))
        }
        guard !csv.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expenses.csv")
        do { try Data(csv.utf8).write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
