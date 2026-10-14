import SwiftUI
import UIKit
import DocuVaultCore

/// The keyboard surface (checkpoints 13c and 15). One bar: menu circle · Search · scan circle · lock
/// circle. Below it one of: the start page, the keys, the search pad, the menu, or the scan. A hold on
/// any key raises a menu drawn inside the keyboard, with the Home Screen's spring: the value on top,
/// then only the options that make sense for that field. Keep the finger down and slide onto an option
/// to pick it, or lift and tap. Bottom: globe · space · backspace · Done or Back.
/// Keys show no check status; the app judges. Values are never drawn on keys.
struct KeyboardRootView: View {
    static let height: CGFloat = 300
    /// Three columns, four rows of 40pt keys under the "Filling from" line: 14 + 6 + 4 × 40 + 3 × 6 = 198pt,
    /// exactly the room left at 300pt once the bar and bottom row are taken out. Ten keys max, nothing scrolls.
    static let columns = 3
    static let rows = 4
    static let keyHeight: CGFloat = 40
    static let keyInset: CGFloat = 12
    static let menuWidth: CGFloat = 220
    static let holdDelay: Duration = .milliseconds(350)

    /// Apple's English keyboard on iPhone 17 Pro, measured from Evan's Telegram screenshot (13 Oct, 3x):
    /// keys 43pt tall and 33.3pt wide, 6pt apart, rows 11pt apart, 6.7pt side margins, about 22pt type.
    /// Bottom row 43 · 43 · 191 · 93pt; here Back spans the first two slots.
    enum System {
        static let keyHeight: CGFloat = 43
        static let rowGap: CGFloat = 11
        static let keyGap: CGFloat = 6
        static let sideInset: CGFloat = 2.0 / 3.0   // on top of the keyboard's 6pt padding: 6.7pt in all
        static let modifierWidth: CGFloat = 45.3
        /// Bottom row, measured from Evan's screenshot of Apple's keyboard in Notes (14 Oct, IMG_3401): 123 and
        /// emoji keys 44pt each, space 105 to 297pt, return 93.7pt. Back spans the two 44pt slots.
        static let bottomModifierWidth: CGFloat = 44
        static let returnWidth: CGFloat = 93.7
        static let radius: CGFloat = 8.5
        static let font: CGFloat = 22
        /// Four rows: 4 × 43 + 3 × 11.
        static let padHeight: CGFloat = 4 * keyHeight + 3 * rowGap
    }

    /// Search matches sit in a card above the bar, Telegram style; each row adds to the keyboard's height.
    static let matchRowHeight: CGFloat = 44
    static let maxMatches = 4

    /// Card rows while search is open. The card fits its results (Evan, 14 Oct: "No match" left dead space),
    /// but the keyboard resizes only once typing pauses (`KeyboardModel.cardRows`), never under a moving
    /// finger: per-keystroke resizes jolted the keys (his first recording).
    static func matchCount(_ model: KeyboardModel) -> Int {
        model.panel == .search ? model.cardRows : 0
    }

    /// In search the bar sits straight on the letter pad, as Apple's suggestion bar does; the 41pt strip
    /// that held the Open hint is gone (Evan, 14 Oct). No bottom padding in search: on Evan's phone Apple's
    /// bottom row ends 71pt above the screen's bottom edge and ours ended 80pt above it, so the pad drops as far
    /// as the keyboard's frame allows (about 3pt still above Apple's). Top 8 + bar 34 + 6 + pad 205 = 253.
    static let searchBaseHeight: CGFloat = 8 + 34 + 6 + System.padHeight

    /// 300pt; in search, the bar and pad plus the fixed four-row match card.
    static func preferredHeight(_ model: KeyboardModel) -> CGFloat {
        let n = matchCount(model)
        return n == 0 ? height : searchBaseHeight + CGFloat(n) * matchRowHeight + 6
    }

    @Bindable var model: KeyboardModel
    let showsGlobe: Bool

    // Hold menu state. Frames are in the "content" coordinate space (the area under the bar).
    @State private var holdSpec: FillFormats.KeySpec?
    @State private var pressedKey: String?
    @State private var holdTask: Task<Void, Never>?
    @State private var highlighted: String?           // "preview" or an option id
    @State private var keyFrames: [String: CGRect] = [:]
    @State private var targetFrames: [String: CGRect] = [:]
    @State private var menuSize: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var scanScale: CGFloat = 1

    private static let spring = Animation.spring(response: 0.38, dampingFraction: 0.62)

    var body: some View {
        VStack(spacing: 6) {
            // No slide: the card appears with the resize, in one frame (Evan, 14 Oct).
            if Self.matchCount(model) > 0 { matchCard }
            bar
            ZStack(alignment: .topLeading) {
                content
                    .opacity(holdSpec == nil ? 1 : 0.35)
                    .animation(.easeOut(duration: 0.18), value: holdSpec == nil)
                if holdSpec != nil {
                    Color.clear.contentShape(Rectangle()).onTapGesture { closeMenu() }
                }
                if let spec = holdSpec {
                    holdMenu(spec)
                        .offset(menuOffset(for: spec))
                        .transition(.scale(scale: 0.4, anchor: menuAnchor(for: spec)).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: "content")
            .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
            .frame(maxHeight: .infinity)
            // The search pad brings its own bottom row, laid out like Apple's.
            if model.panel != .search { bottomRow }
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, model.panel == .search ? 0 : 6)
        // No fill of our own: iOS's keyboard backdrop runs through, so there is no edge at the top or above the
        // globe strip (Evan, 14 Oct: "awkward lines").
        .tint(Palette.accent)
        // No animation on panel changes: panels swap in one frame, as Apple's keyboard swaps to emoji.
    }

    @ViewBuilder private var content: some View {
        switch model.panel {
        case .home: homePanel
        case .keys: keyArea
        case .search: searchPanel
        case .scan: scanPanel
        case .vault: vaultPanel
        }
    }

    // MARK: Bar

    private var bar: some View {
        // Photo circle · Search · menu pill · vault pill (Evan, 14 Oct: menu and photo swapped; menu and vault
        // are small pills of one size, the photo stays a circle).
        HStack(spacing: 6) {
            circle("photo", style: model.panel == .scan ? .accent : (model.currentDoc?.firstPageFile == nil ? .dim : .ink)) { model.toggleScan() }
                .accessibilityLabel("Show the scan")
            Button { model.openSearch() } label: {
                HStack(spacing: 6) {
                    if model.panel == .search {
                        // Caret is grey and touches the last letter (Evan, 13 Oct).
                        HStack(spacing: 1) {
                            Text(model.searchText).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Rectangle().fill(Palette.ink2).frame(width: 1.5, height: 16)
                        }
                        Spacer(minLength: 0)
                    } else {
                        Text(probeOr("Search")).font(.system(size: 14)).foregroundStyle(Palette.ink2)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Palette.glass)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(model.panel == .search ? Palette.accent : Palette.glassEdge, lineWidth: model.panel == .search ? 2 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search people and documents")
            menuPill
            vaultDoor
        }
        .frame(height: 34)
    }

    /// Bar pills: the menu and the vault door share one size.
    static let pillSize = CGSize(width: 46, height: 32)

    /// Filled black on home, glass elsewhere: the way home (checkpoint 20).
    private var menuPill: some View {
        let home = model.panel == .home
        return Button { model.toggleHome() } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(home ? Palette.matteInk : Palette.ink)
                .frame(width: Self.pillSize.width, height: Self.pillSize.height)
                .background(home ? Palette.matte : Palette.glass)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.glassEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
    }

    private enum CircleStyle { case matte, ink, dim, accent, green }

    private func circle(_ symbol: String, style: CircleStyle, action: @escaping () -> Void) -> some View {
        let fill: Color, fg: Color
        switch style {
        case .matte: fill = Palette.matte; fg = Palette.matteInk
        case .accent: fill = Palette.accent; fg = .white
        case .ink: fill = Palette.glass; fg = Palette.ink
        case .dim: fill = Palette.glass; fg = Palette.ink3
        case .green: fill = Palette.glass; fg = Palette.verified
        }
        return Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(fg)
                .frame(width: 32, height: 32)
                .background(fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.glassEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The vault door (checkpoint 20, Evan 14 Oct): the one raised, filled button in the bar. Same texture
    /// open or shut, a gradient with a light top edge and a shadow; only the colour changes. Gunmetal with a
    /// closed lock when shut, green with an open lock when open.
    private var vaultDoor: some View {
        let open = model.isUnlocked
        return Button { model.openVault() } label: {
            Image(systemName: open ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: Self.pillSize.width, height: Self.pillSize.height)
                .background(Capsule().fill(open ? Palette.doorOpen : Palette.doorShut))
                .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? "Vault, open" : "Vault, locked")
    }

    // MARK: Home

    /// Four tabs: Recents, People, Documents, Favourites (checkpoint 20). Recents is last touched first,
    /// with a suggestion row on top when the field says what it wants.
    private var homePanel: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                ForEach(KeyboardModel.MenuTab.allCases, id: \.self) { tab in
                    chip(tab.rawValue, on: model.menuTab == tab) { model.showTab(tab) }
                }
            }
            .frame(height: 34)
            if let status = model.status {
                Text(status).font(.system(size: 13)).foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center).padding(.top, 16)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    switch model.menuTab {
                    case .recents:
                        if let s = model.suggestion, let h = model.fieldHint { suggestionRow(s, label: h.label) }
                        ForEach(model.recentEntries) { e in entryRow(e) }
                    case .people:
                        if let p = model.people.first(where: { $0.id == model.personFilter }) {
                            caption(p.name)
                            ForEach(model.personEntries) { e in entryRow(e) }
                        } else {
                            ForEach(model.people) { p in
                                folderRow(p.name, count: model.rowCount(for: p)) { model.personFilter = p.id }
                            }
                        }
                    case .documents:
                        if let g = model.groupFilter {
                            caption(g)
                            ForEach(model.groupEntries) { e in entryRow(e) }
                        } else {
                            ForEach(model.groups) { g in
                                folderRow(g.name, count: g.entries.count) { model.groupFilter = g.name }
                            }
                        }
                    case .favourites:
                        if model.favouriteEntries.isEmpty {
                            Text("Star a document in DocuVault to keep it here").font(.system(size: 13))
                                .foregroundStyle(Palette.ink2).padding(.top, 16)
                        }
                        ForEach(model.favouriteEntries) { e in entryRow(e, star: true) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Offered only when the field says what it wants ("Email"); one tap opens it with the key ringed.
    private func suggestionRow(_ e: FillEntry, label: String) -> some View {
        Button { model.select(e) } label: {
            HStack(spacing: 6) {
                Text(label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(Palette.accent)
                Text(Self.shortTitle(e.title)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let t = e.trailing {
                    Text(t).font(.system(size: 15, weight: .semibold)).foregroundStyle(e.personName.isEmpty ? Palette.ink2 : Palette.navy).lineLimit(1)
                }
            }
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(Palette.ink)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    /// A person or a document group: name on the left, row count on the right; tap narrows the list.
    private func folderRow(_ name: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 14)).foregroundStyle(Palette.ink2)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(Palette.ink).background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Vault

    /// Behind the door: the vault's own categories and people, as in the app's Vault tab. Lock seals it now;
    /// otherwise the lock window from the app's Settings applies.
    private var vaultPanel: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.verified)
                Text(vaultTitle).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Button { model.lock() } label: {
                    Label("Lock", systemImage: "lock.fill").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Palette.surfaceOff).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 4).frame(height: 30)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    if model.vaultFilter != nil {
                        ForEach(model.vaultFilteredEntries) { e in entryRow(e) }
                    } else {
                        if model.vaultEntries.isEmpty {
                            Text("Nothing in the vault yet").font(.system(size: 13)).foregroundStyle(Palette.ink2).padding(.top, 16)
                        }
                        ForEach(model.vaultGroups) { g in
                            folderRow(g.name, count: g.entries.count) { model.vaultFilter = .group(g.name) }
                        }
                        if !model.vaultPeople.isEmpty { caption("People") }
                        ForEach(model.vaultPeople) { p in
                            folderRow(p.name, count: model.vaultEntries.filter { $0.personID == p.id }.count) { model.vaultFilter = .person(p.id) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var vaultTitle: String {
        switch model.vaultFilter {
        case .group(let name): "Vault · \(name)"
        case .person(let id): "Vault · \(model.people.first { $0.id == id }?.name ?? "")"
        case nil: "Vault"
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 13)
            .padding(.horizontal, 4)
    }

    /// "Passport" on the left and the person's name on the right in navy, same size (Evan, 15). With no
    /// person, the detail in grey: a receipt's date, a card's company (checkpoint 20). Vault rows show a
    /// lock while the vault is shut; tapping one asks for Face ID once. The document's own suffix
    /// ("· CHAI") shows only on the Filling from line.
    private func entryRow(_ e: FillEntry, star: Bool = false) -> some View {
        Button { model.select(e) } label: {
            HStack(spacing: 6) {
                if model.isLocked(e) {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink2)
                }
                if star {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.amber)
                }
                if case .shared = e.kind {
                    Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Palette.ink)
                }
                Text(Self.shortTitle(e.title)).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let t = e.trailing {
                    Text(t).font(.system(size: 15, weight: e.personName.isEmpty ? .medium : .semibold))
                        .foregroundStyle(e.personName.isEmpty ? Palette.ink2 : Palette.navy)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(Palette.ink)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// "Passport · CHAI" → "Passport". Titles without a separator pass through.
    static func shortTitle(_ title: String) -> String {
        title.components(separatedBy: " · ").first ?? title
    }

    // MARK: Keys

    private var specs: [FillFormats.KeySpec] {
        guard model.currentEntry != nil else { return [] }
        if model.isSharedSelected { return FillFormats.sharedKeys }
        return model.currentDoc.map { FillFormats.keys(for: $0.type) } ?? []
    }

    private var keyArea: some View {
        VStack(spacing: 6) {
            fillingFrom
            if specs.isEmpty {
                linesList
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.columns), spacing: 6) {
                    ForEach(specs.prefix(Self.columns * Self.rows), id: \.fieldKey) { spec in
                        key(spec)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Documents with no keys show their text lines (checkpoint 20 Q6). Tap types the line. Hold a line with
    /// a label ("Booking reference: K7Q2LM") to pick the label or the value.
    @State private var splitLine: String?

    private var linesList: some View {
        let lines = model.currentLines
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 5) {
                if lines.isEmpty {
                    Text("No text in this document. The photo circle shows the scan").font(.system(size: 13))
                        .foregroundStyle(Palette.ink2).padding(.top, 16)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if splitLine == line, let parts = FillLines.split(line) {
                        HStack(spacing: 5) {
                            lineButton(parts.label) { model.insertLine(parts.label); splitLine = nil }
                            lineButton(parts.value, bold: true) { model.insertLine(parts.value); splitLine = nil }
                        }
                    } else {
                        lineButton(line) { model.insertLine(line) }
                            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                guard FillLines.split(line) != nil else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.snappy(duration: 0.18)) { splitLine = line }
                            })
                    }
                }
            }
        }
    }

    private func lineButton(_ text: String, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: bold ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 32)
                .foregroundStyle(Palette.ink).background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// Names the loaded document, so the search bar can always read Search (15 Q1).
    private var fillingFrom: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isSharedSelected ? "person.fill" : "doc.text.fill")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent)
            Text("Filling from").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            Text(model.currentEntry?.title ?? "").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Palette.ink)
            if let t = model.currentEntry?.trailing {
                Text("· \(t)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
        .frame(height: 14)
    }

    private func key(_ spec: FillFormats.KeySpec) -> some View {
        let enabled = model.hasValue(spec)
        let hint = enabled ? model.hint(for: spec) : nil
        let held = holdSpec == spec
        return VStack(spacing: 1) {
            Text(spec.label).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            if let hint { Text(hint).font(.system(size: 9.5)).tracking(0.2).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .padding(.horizontal, Self.keyInset)
        .frame(maxWidth: .infinity).frame(height: Self.keyHeight)
        .foregroundStyle(enabled ? Palette.ink : Palette.ink2)
        .background(enabled ? Palette.surface : Palette.surfaceOff)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        .overlay {
            // Held, or the key the field asks for (checkpoint 20 Q4): a ring; nothing moves.
            if held || (enabled && model.isHinted(spec)) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent, lineWidth: 2)
            }
        }
        .scaleEffect(pressedKey == spec.fieldKey && !held ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: pressedKey == spec.fieldKey)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("content")) } action: { keyFrames[spec.fieldKey] = $0 }
        .gesture(keyGesture(spec, enabled: enabled))
        .accessibilityLabel(spec.label)
        .accessibilityAddTraits(.isButton)
    }

    /// Tap inserts. Hold raises the menu; keep the finger down and slide onto the value card or an
    /// option, then lift, to pick it. Lift without sliding and the menu stays open for a tap.
    private func keyGesture(_ spec: FillFormats.KeySpec, enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("content"))
            .onChanged { v in
                guard enabled else { return }
                if holdSpec == nil, holdTask == nil, pressedKey == nil {
                    pressedKey = spec.fieldKey
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: Self.holdDelay)
                        guard !Task.isCancelled, pressedKey == spec.fieldKey else { return }
                        openMenu(spec)
                    }
                }
                if holdSpec == spec {
                    highlighted = targetFrames.first { $0.value.contains(v.location) }?.key
                }
            }
            .onEnded { _ in
                holdTask?.cancel(); holdTask = nil
                let wasPressed = pressedKey == spec.fieldKey
                pressedKey = nil
                guard enabled else { return }
                if holdSpec == spec {
                    if let h = highlighted { perform(h, for: spec) }
                    highlighted = nil
                } else if holdSpec == nil, wasPressed {
                    model.insert(spec)
                }
            }
    }

    private func openMenu(_ spec: FillFormats.KeySpec) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(Self.spring) { holdSpec = spec }
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.16)) { holdSpec = nil }
        highlighted = nil
        targetFrames = [:]
    }

    private func perform(_ target: String, for spec: FillFormats.KeySpec) {
        if target == "preview" {
            model.insertPreview(spec)
        } else if let o = model.holdOptions(for: spec).first(where: { $0.id == target }) {
            o.action()
        }
        UISelectionFeedbackGenerator().selectionChanged()
        closeMenu()
    }

    /// Below the key when it fits, else above it; never off the sides.
    private func menuOffset(for spec: FillFormats.KeySpec) -> CGSize {
        guard let f = keyFrames[spec.fieldKey], contentSize.width > 0 else { return .zero }
        let x = min(max(f.minX, 0), max(contentSize.width - Self.menuWidth, 0))
        let below = f.maxY + 4
        let y: CGFloat
        if menuSize.height == 0 || below + menuSize.height <= contentSize.height { y = below }
        else if f.minY - 4 - menuSize.height >= 0 { y = f.minY - 4 - menuSize.height }
        else { y = max(contentSize.height - menuSize.height, 0) }
        return CGSize(width: x, height: y)
    }

    private func menuAnchor(for spec: FillFormats.KeySpec) -> UnitPoint {
        guard let f = keyFrames[spec.fieldKey], contentSize.width > 0 else { return .top }
        let below = menuSize.height == 0 || f.maxY + 4 + menuSize.height <= contentSize.height
        let left = min(max(f.minX, 0), max(contentSize.width - Self.menuWidth, 0))
        let x = min(max((f.midX - left) / Self.menuWidth, 0), 1)
        return UnitPoint(x: x, y: below ? 0 : 1)
    }

    /// Hold menu: the value on top (tap inserts), then the field's options. Drawn by the keyboard
    /// itself because an extension cannot present a system context menu above the host app.
    private func holdMenu(_ spec: FillFormats.KeySpec) -> some View {
        let options = model.holdOptions(for: spec)
        return VStack(spacing: 0) {
            Button { perform("preview", for: spec) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(Palette.ink2)
                    Text(model.rendered(spec) ?? "").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.ink)
                        .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                    Text("Tap to insert").font(.system(size: 11)).foregroundStyle(Palette.ink2)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlighted == "preview" ? Palette.accent.opacity(0.12) : Palette.surface)
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("content")) } action: { targetFrames["preview"] = $0 }
            ForEach(options) { o in
                Divider().overlay(Palette.hairline)
                Button { perform(o.id, for: spec) } label: {
                    HStack {
                        Text(o.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 6)
                        if o.selected {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                        } else if let d = o.detail {
                            Text(d).font(.system(size: 11.5)).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(highlighted == o.id ? Palette.accent.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("content")) } action: { targetFrames[o.id] = $0 }
            }
        }
        .frame(width: Self.menuWidth)
        .background(Palette.menu)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.glassEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
    }

    // MARK: Search

    /// The keyboard's own letter pad: letters go to the query, never to the form (13c Q3). Laid out like
    /// Apple's English keyboard and never resized (Evan, 13 Oct). The bar sits straight on it; matches show
    /// in the card above the bar, and the tinted top row is what Open loads.
    private var searchPanel: some View {
        searchPad
            .frame(height: System.padHeight)
            .padding(.horizontal, System.sideInset)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// One UIKit touch surface (see `SearchPad`): nearest-key hits, callouts, clicks and rollover.
    private var searchPad: some View {
        SearchPad(showsGlobe: showsGlobe, openEnabled: model.topMatch != nil,
                  onLetter: { model.typeSearch($0) },
                  onDelete: { model.backspaceSearch() },
                  onSpace: { model.typeSearch(" ") },
                  onBack: { model.back() },
                  onOpen: { model.openTopMatch() },
                  onGlobe: { model.globe() })
    }

    /// Up to four matches above the bar, Telegram style. The top row is tinted: Open loads it. Matched
    /// letters show in full colour and the rest dimmed, as in Spotlight.
    /// The card keeps a fixed four-row slot and hugs its rows at the bottom, next to the bar; fewer rows leave
    /// the canvas above them empty. Before you type it shows the four most recent rows.
    private var matchCard: some View {
        let typing = !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let results: [CardRow]
        if typing {
            results = model.searchMatches.prefix(model.cardRows)
                .map { CardRow(entry: $0.entry, titleHighlight: $0.titleHighlight, personHighlight: $0.personHighlight) }
        } else {
            results = model.recentEntries.prefix(model.cardRows).map { CardRow(entry: $0, titleHighlight: [], personHighlight: []) }
        }
        return VStack(spacing: 0) {
            if typing, results.isEmpty {
                Text("No match").font(.system(size: 15)).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).frame(height: Self.matchRowHeight)
            }
            ForEach(Array(results.enumerated()), id: \.element.entry.id) { i, m in
                let e = m.entry
                Button { model.select(e) } label: {
                    HStack(spacing: 8) {
                        if model.isLocked(e) {
                            Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink2)
                        }
                        if case .shared = e.kind {
                            Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(Palette.ink)
                        }
                        Self.highlighted(Self.shortTitle(e.title), m.titleHighlight, on: Palette.ink, off: Palette.ink2)
                        Spacer(minLength: 4)
                        if let t = e.trailing {
                            let side = e.personName.isEmpty ? Palette.ink2 : Palette.navy
                            Self.highlighted(t, m.personHighlight, on: side, off: side.opacity(0.6))
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity).frame(height: Self.matchRowHeight)
                    .background(typing && i == 0 ? Palette.accent.opacity(0.10) : Color.clear)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Palette.hairline).frame(height: 0.5).padding(.leading, 14) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .frame(height: CGFloat(Self.matchCount(model)) * Self.matchRowHeight, alignment: .bottom)
        .clipped()
        .animation(.snappy(duration: 0.18), value: results.map(\.entry.id))
    }

    private struct CardRow {
        let entry: FillEntry
        let titleHighlight: [Range<Int>]
        let personHighlight: [Range<Int>]
    }

    /// A title or name with the matched characters in `on` and the rest in `off`. With no match in this
    /// string, the whole string is `on`, so a row matched by the person keeps a readable title.
    static func highlighted(_ s: String, _ ranges: [Range<Int>], on: Color, off: Color) -> Text {
        guard !ranges.isEmpty else { return Text(s).foregroundStyle(on) }
        var out = Text("")
        for (i, ch) in s.enumerated() {
            let hit = ranges.contains { $0.contains(i) }
            out = out + Text(String(ch)).foregroundStyle(hit ? on : off)
        }
        return out
    }

    // MARK: Tabs

    /// App chip rule: selected is a white pill with a hairline, unselected is grey text (15 Q3).
    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 34)
                .foregroundStyle(on ? Palette.ink : Palette.ink2)
                .background(on ? Palette.surface : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Palette.hairline : Color.clear, lineWidth: 1))
                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Scan

    /// The loaded document's first page, decrypted only while shown. Pinch to zoom.
    private var scanPanel: some View {
        Group {
            if let cg = model.scanImage() {
                Image(decorative: cg, scale: 1)
                    .resizable().aspectRatio(contentMode: .fit)
                    .scaleEffect(scanScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .gesture(MagnifyGesture().onChanged { v in scanScale = min(max(v.magnification, 1), 4) })
                    .overlay(alignment: .topTrailing) {
                        Text("Pinch to zoom").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.black.opacity(0.55)).clipShape(Capsule())
                            .padding(8)
                    }
            } else {
                Text("No scan for this document").font(.system(size: 13)).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDisappear { scanScale = 1 }
    }

    /// Field-hint test build (14 Oct, throwaway): Debug builds show the field's hints in place of the search
    /// placeholder. Remove with `KeyboardViewController.probe`.
    private func probeOr(_ text: String) -> String {
        #if DEBUG
        if !model.fieldHintProbe.isEmpty { return model.fieldHintProbe }
        #endif
        return text
    }

    // MARK: Bottom

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if showsGlobe {
                bottomKey("globe") { model.globe() }.frame(width: 52)
            }
            Button { model.space() } label: {
                Text("space").font(.system(size: 15)).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).frame(height: 42).background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            }.buttonStyle(.plain)
            RepeatingKey(systemImage: "delete.left", action: { model.backspace() }).frame(width: 52)
            Button { dismissOrBack() } label: {
                Text(isShowingBack ? "Back" : "Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 70, height: 42)
                    .background(Palette.accentFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            }.buttonStyle(.plain)
        }
    }

    private var isShowingBack: Bool { holdSpec != nil || model.showsBack }

    private func dismissOrBack() {
        if holdSpec != nil { closeMenu() }
        else if model.showsBack { model.back() }
        else { model.done() }
    }

    private func bottomKey(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 18)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Palette.surfaceOff)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        }.buttonStyle(.plain)
    }
}

/// The app's design tokens, mirrored for the keyboard target (it cannot import the app's Theme).
/// Keep in step with `DocuVault/Design/Theme.swift`. Every colour has a light and a dark value and the
/// keyboard follows the phone's setting (checkpoint 19); the key greys match Apple's own keyboard.
enum Palette {
    static let accent = Color(light: 0x3A424C, dark: 0xA9B4C2)   // gunmetal, checkpoint 17b; steel in dark
    /// Done and Back: flat gunmetal, no sheen (Evan, 14 Oct). Same value as the app's `accentFill`.
    static let accentFill = Color(light: 0x3A424C, dark: 0x3A424C)
    /// The menu circle while the menu is open: black with a white glyph, inverted in dark.
    static let matte = Color(light: 0x1C1C1E, dark: 0xFFFFFF)
    static let matteInk = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let navy = Color(light: 0x1B0F55, dark: 0x9AA9F0)
    static let verified = Color(light: 0x1B7F4C, dark: 0x4CC38A)
    static let ink = Color(light: 0x0A0A0C, dark: 0xFFFFFF)
    static let ink2 = Color(light: 0x8A8A8E, dark: 0x98989F)
    static let ink3 = Color(light: 0xB0B3BA, dark: 0x5A5A5F)
    static let hairline = Color(light: 0xE5E5EA, dark: 0x48484A)
    /// Rows, cards and letter keys.
    static let surface = Color(light: 0xFFFFFF, dark: 0x6B6B6B)
    static let surfaceOff = Color(light: 0xECEDF0, dark: 0x464646)
    static let key = surface
    static let keyModifier = Color(light: 0xACB1B9, dark: 0x464646)
    static let keyShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.30, darkAlpha: 0.55)
    static let glass = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.14)
    static let glassEdge = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.95, darkAlpha: 0.10)
    static let menu = Color(light: 0xF6F7FA, dark: 0x3A3A3C)
    static let amber = Color(light: 0xB5731B, dark: 0xE3A341)
    /// The vault door (checkpoint 20): gunmetal shut, green open, the app's existing gradients. Fixed in both
    /// modes because they carry a white glyph.
    static let doorShut = LinearGradient(colors: [Color(uiColor: UIColor(hex: 0x3A424C)), Color(uiColor: UIColor(hex: 0x5C6672))], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let doorOpen = LinearGradient(colors: [Color(uiColor: UIColor(hex: 0x0C4A2E)), Color(uiColor: UIColor(hex: 0x1B7F4C))], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// A colour with a light and a dark value, resolved by the phone's setting. Mirrors the app's Theme.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha) })
    }
}

/// Backspace that behaves like Apple's: one delete on tap, then after a short hold it repeats,
/// speeding up the longer you hold.
struct RepeatingKey: View {
    let systemImage: String
    var height: CGFloat = 42
    var radius: CGFloat = 12
    var fill: Color = Palette.surfaceOff
    let action: () -> Void
    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(pressed ? (fill == Palette.surface ? Palette.surfaceOff : Palette.surface) : fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        repeater = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))      // initial delay, like UIKit
                            var interval = 90
                            var fired = 0
                            while !Task.isCancelled {
                                action()
                                fired += 1
                                if fired == 15 { interval = 45 }               // speed up after ~1.5 s
                                try? await Task.sleep(for: .milliseconds(interval))
                            }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeater?.cancel()
                        repeater = nil
                    }
            )
    }
}

