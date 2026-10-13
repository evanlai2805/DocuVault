import SwiftUI
import SwiftData
import DocuVaultCore

/// Library tab, the Files model (checkpoint 16): Recents is the home, Browse holds folders by type,
/// people and Recently deleted. Vault documents never appear here.
struct LibraryView: View {
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]
    @Query(filter: #Predicate<StoredDocument> { $0.sensitive }) private var vaultDocs: [StoredDocument]
    @Query(filter: #Predicate<StoredDocument> { $0.deletedAt != nil }) private var deleted: [StoredDocument]
    @AppStorage("library.mode") private var mode: Mode = .recents

    enum Mode: String { case recents, browse }

    var body: some View {
        Group {
            if docs.isEmpty && vaultDocs.isEmpty && deleted.isEmpty {
                emptyState
            } else {
                // Recents and Browse are two pages you swipe between (checkpoint 17).
                VStack(spacing: 0) {
                    Picker("View", selection: $mode) {
                        Text("Recents").tag(Mode.recents)
                        Text("Browse").tag(Mode.browse)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    TabView(selection: $mode) {
                        ScrollView { DocumentCollection(docs: docs, groupByRecency: true).padding(16) }
                            .tag(Mode.recents)
                        ScrollView { browse.padding(16) }
                            .tag(Mode.browse)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: mode)
                }
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Library")
        .navigationDestination(for: UUID.self) { id in
            if let doc = (docs + deleted).first(where: { $0.id == id }) { DocumentDetailView(doc: doc) }
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .folder(let f): LibraryFolderPager(start: f)
            case .person(let id, let name): LibraryFolderView(title: name) { $0.person?.id == id }
            case .deleted: RecentlyDeletedView()
            }
        }
    }

    // MARK: Browse

    private var owners: [StoredPerson] {
        var seen = Set<UUID>()
        return docs.compactMap(\.person).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }

    private var browse: some View {
        VStack(spacing: 14) {
            section("Folders") {
                ForEach(LibraryFolder.allCases.filter { f in f != .other || docs.contains(where: f.contains) }, id: \.self) { f in
                    folderRow(f.title, subtitle: f.subtitle, icon: "folder.fill", count: docs.filter(f.contains).count, route: .folder(f))
                }
            }
            if !owners.isEmpty {
                section("People") {
                    ForEach(owners) { p in
                        folderRow(p.name, subtitle: p.kind.displayName, icon: p.kind == .client ? "building.2" : "person.fill",
                                  count: docs.filter { $0.person?.id == p.id }.count, route: .person(p.id, p.name), plainIcon: true)
                    }
                }
            }
            section(nil) {
                folderRow("Recently deleted", subtitle: "Kept \(RetentionManager.recentlyDeletedDays) days", icon: "trash",
                          count: deleted.filter { !$0.sensitive }.count, route: .deleted, plainIcon: true)
            }
        }
    }

    private func section<C: View>(_ title: String?, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased()).font(.system(size: 14)).tracking(0.5).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
            }
            VStack(spacing: 0) { rows() }
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func folderRow(_ title: String, subtitle: String?, icon: String, count: Int, route: LibraryRoute, plainIcon: Bool = false) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: plainIcon ? 17 : 26, weight: .medium))
                    .foregroundStyle(plainIcon ? Theme.Colors.ink : Theme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(plainIcon ? Theme.Colors.canvas : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.ink)
                    if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2) }
                }
                Spacer()
                Text("\(count)").font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 6) {
                Text("Nothing scanned yet").font(.system(size: 22, weight: .semibold))
                Text("Tap Scan to add your first document").font(.system(size: 17))
            }
            .foregroundStyle(Theme.Colors.ink2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

enum LibraryRoute: Hashable {
    case folder(LibraryFolder)
    case person(UUID, String)
    case deleted
}

/// Folders are built from the document type, so nothing is filed by hand (checkpoint 16 Q3).
enum LibraryFolder: String, CaseIterable, Hashable {
    case contracts, receipts, cards, chinese, other

    var title: String {
        switch self {
        case .contracts: "Contracts and letters"
        case .receipts: "Receipts"
        case .cards: "Business cards"
        case .chinese: "中文"
        case .other: "Other"
        }
    }
    var subtitle: String? { self == .chinese ? "Chinese and mixed" : nil }

    func contains(_ d: StoredDocument) -> Bool {
        switch self {
        case .contracts: d.type == .contract || d.type == .letter
        case .receipts: d.type == .receipt
        case .cards: d.type == .businessCard
        case .chinese: d.language != "en"
        case .other: ![.contract, .letter, .receipt, .businessCard].contains(d.type)
        }
    }
}

/// The folders as pages: swipe left or right to the next folder, chips on top show where you are
/// (Evan's example, checkpoint 17). The left-edge swipe still goes back.
struct LibraryFolderPager: View {
    @State private var current: LibraryFolder
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]

    init(start: LibraryFolder) { _current = State(initialValue: start) }

    private var folders: [LibraryFolder] {
        LibraryFolder.allCases.filter { f in f != .other || docs.contains(where: f.contains) || current == .other }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(folders, id: \.self) { f in
                            let on = f == current
                            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { current = f } } label: {
                                Text(f.title).font(.system(size: 15, weight: on ? .semibold : .regular))
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .foregroundStyle(on ? Theme.Colors.ink : Theme.Colors.ink2)
                                    .background(on ? Theme.Colors.surface : .clear)
                                    .overlay(Capsule().stroke(on ? Theme.Colors.hairline : .clear))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(f)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                .onChange(of: current) { _, f in withAnimation { proxy.scrollTo(f, anchor: .center) } }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            TabView(selection: $current) {
                ForEach(folders, id: \.self) { f in
                    ScrollView { DocumentCollection(docs: docs.filter(f.contains)).padding(16) }.tag(f)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One person's library documents, in the same list or grid as Recents.
struct LibraryFolderView: View {
    let title: String
    let include: (StoredDocument) -> Bool
    @Query(filter: #Predicate<StoredDocument> { !$0.sensitive && $0.deletedAt == nil }, sort: \StoredDocument.capturedAt, order: .reverse) private var docs: [StoredDocument]

    init(title: String, include: @escaping (StoredDocument) -> Bool) {
        self.title = title
        self.include = include
    }

    var body: some View {
        ScrollView {
            DocumentCollection(docs: docs.filter(include)).padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DocumentRow: View {
    let doc: StoredDocument
    var showsChevron = true
    var body: some View {
        HStack(spacing: 16) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.rowTitle).lineLimit(1).foregroundStyle(Theme.Colors.ink)
                Text(subtitle).font(.rowSubtitle).foregroundStyle(Theme.Colors.ink2).lineLimit(1)
            }
            Spacer()
            if !doc.allChecksPassed { ReviewFlag() }
            if doc.sensitive { Image(systemName: "lock.fill").foregroundStyle(Theme.Colors.ink2) }
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    private var subtitle: String {
        let lang = doc.language == "en" ? "EN" : (doc.language == "mixed" ? "Mixed" : "中文")
        return "\(doc.type.displayName) · \(lang) · \(doc.pages.count) page\(doc.pages.count == 1 ? "" : "s") · \(doc.capturedAt.dvDisplay())"
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
