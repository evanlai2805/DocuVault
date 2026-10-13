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
        static let returnWidth: CGFloat = 93
        static let radius: CGFloat = 8.5
        static let font: CGFloat = 22
        /// Four rows: 4 × 43 + 3 × 11.
        static let padHeight: CGFloat = 4 * keyHeight + 3 * rowGap
    }

    /// Search matches sit in a card above the bar, Telegram style; each row adds to the keyboard's height.
    static let matchRowHeight: CGFloat = 44
    static let maxMatches = 4

    static func matchCount(_ model: KeyboardModel) -> Int {
        guard model.isUnlocked, model.panel == .search, !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        return max(1, min(maxMatches, model.searchResults.count))   // "No match" takes one row
    }

    /// 300pt, plus the match card while a search has letters in it.
    static func preferredHeight(_ model: KeyboardModel) -> CGFloat {
        let n = matchCount(model)
        return n == 0 ? height : height + CGFloat(n) * matchRowHeight + 6
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
            if model.isUnlocked {
                if Self.matchCount(model) > 0 {
                    matchCard.transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
            } else {
                unlockPanel
            }
            // The search pad brings its own bottom row, laid out like Apple's.
            if !(model.isUnlocked && model.panel == .search) { bottomRow }
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
        .background(Palette.canvas)
        .tint(Palette.accent)
        .animation(.snappy(duration: 0.22), value: Self.matchCount(model) > 0)
    }

    @ViewBuilder private var content: some View {
        switch model.panel {
        case .start: startPage
        case .keys: keyArea
        case .search: searchPanel
        case .menu: menuPanel
        case .scan: scanPanel
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 6) {
            // Glass like the scan circle until the menu is open; then filled black, no ring (Evan, 13 Oct).
            circle("line.3.horizontal", style: model.panel == .menu ? .matte : .ink) { model.toggleMenu() }
                .accessibilityLabel("Menu")
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
                        Text("Search").font(.system(size: 14)).foregroundStyle(Palette.ink2)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Palette.glass)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(model.panel == .search ? Palette.accent : Palette.glassEdge, lineWidth: model.panel == .search ? 2 : 1))
                .opacity(model.panel == .menu ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search people and documents")
            circle("photo", style: model.panel == .scan ? .accent : (model.currentDoc?.firstPageFile == nil ? .dim : .ink)) { model.toggleScan() }
                .accessibilityLabel("Show the scan")
            circle("lock.open.fill", style: .green) { model.lock() }
                .accessibilityLabel("Lock the keyboard")
        }
        .frame(height: 34)
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

    // MARK: Start page

    /// Two most used, then two most recent (13c). Captions 13pt, rows 36pt: 195pt in all. With
    /// favourites starred in the app, up to two favourites take the Most used slot (checkpoint 16 Q8).
    private var startPage: some View {
        let page = startPageRows
        return VStack(spacing: 5) {
            if page.mostUsed.isEmpty, page.recent.isEmpty {
                Text(model.status ?? "Nothing in the vault yet")
                    .font(.system(size: 13)).foregroundStyle(Palette.ink2).padding(.top, 20)
            }
            if !page.mostUsed.isEmpty {
                caption(model.favouriteEntries.isEmpty ? "Most used" : "Favourites")
                ForEach(page.mostUsed) { e in entryRow(e, height: 36) }
            }
            if !page.recent.isEmpty {
                caption(page.mostUsed.isEmpty && !model.hasUsage ? "Documents" : "Recent")
                ForEach(page.recent) { e in entryRow(e, height: 36) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var startPageRows: FillPicker.StartPage {
        let page = model.startPage
        let favs = Array(model.favouriteEntries.prefix(2))
        guard !favs.isEmpty else { return page }
        let ids = Set(favs.map(\.id))
        let rest = (page.mostUsed + page.recent + model.entries).filter { !ids.contains($0.id) }
        var seen = Set<String>()
        let recent = rest.filter { seen.insert($0.id).inserted }.prefix(2)
        return FillPicker.StartPage(mostUsed: favs, recent: Array(recent))
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 13)
            .padding(.horizontal, 4)
    }

    /// "Passport" on the left and the person's name on the right in navy, same size (Evan, 15). The
    /// document's own suffix ("· CHAI") shows only on the Filling from line.
    private func entryRow(_ e: FillEntry, height: CGFloat, trailing: String? = nil) -> some View {
        Button { model.select(e) } label: {
            HStack(spacing: 6) {
                if case .shared = e.kind {
                    Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Palette.ink)
                }
                Text(Self.shortTitle(e.title)).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(trailing ?? e.personName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.navy).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: height)
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
        guard model.isUnlocked else { return [] }
        if model.selectedDoc == nil { return FillFormats.sharedKeys }
        return model.currentDoc.map { FillFormats.keys(for: $0.type) } ?? []
    }

    private var keyArea: some View {
        VStack(spacing: 6) {
            fillingFrom
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.columns), spacing: 6) {
                ForEach(specs.prefix(Self.columns * Self.rows), id: \.fieldKey) { spec in
                    key(spec)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Names the loaded document, so the search bar can always read Search (15 Q1).
    private var fillingFrom: some View {
        HStack(spacing: 6) {
            Image(systemName: model.selectedDoc == nil ? "person.fill" : "doc.text.fill")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent)
            Text("Filling from").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            Text(model.currentEntry?.title ?? "").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Palette.ink)
            Text("· \(model.currentEntry?.personName ?? "")").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
        .frame(height: 14)
    }

    private func key(_ spec: FillFormats.KeySpec) -> some View {
        let enabled = model.isUnlocked && model.hasValue(spec)
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
            if held { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent, lineWidth: 2) }
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
    /// Apple's English keyboard and never resized (Evan, 13 Oct). Above it, a strip of recent documents
    /// before you type, and the Open hint once you do; matches show in the card above the bar.
    private var searchPanel: some View {
        VStack(spacing: 5) {
            searchStrip.frame(height: 36)
            searchPad
                .frame(height: System.padHeight)
                .padding(.horizontal, System.sideInset)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var searchStrip: some View {
        if let top = model.topMatch {
            Text("Open loads \(Self.shortTitle(top.title)) · \(top.personName)")
                .font(.system(size: 13)).foregroundStyle(Palette.ink2).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.searchText.isEmpty {
            Color.clear
        } else {
            // Most recent first, like the system keyboard's three suggestion slots.
            let recent = Array(model.entries.prefix(3))
            HStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Rectangle().fill(Palette.ink3).frame(width: 1, height: 22) }
                    Button { model.select(e) } label: {
                        VStack(spacing: 1) {
                            Text(Self.shortTitle(e.title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(e.personName).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.navy)
                        }
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
    private var matchCard: some View {
        let results = Array(model.searchMatches.prefix(Self.maxMatches))
        return VStack(spacing: 0) {
            if results.isEmpty {
                Text("No match").font(.system(size: 15)).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).frame(height: Self.matchRowHeight)
            }
            ForEach(Array(results.enumerated()), id: \.element.entry.id) { i, m in
                let e = m.entry
                Button { model.select(e) } label: {
                    HStack(spacing: 8) {
                        if case .shared = e.kind {
                            Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(Palette.ink)
                        }
                        Self.highlighted(Self.shortTitle(e.title), m.titleHighlight, on: Palette.ink, off: Palette.ink2)
                        Spacer(minLength: 4)
                        Self.highlighted(e.personName, m.personHighlight, on: Palette.navy, off: Palette.navy.opacity(0.6))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity).frame(height: Self.matchRowHeight)
                    .background(i == 0 ? Palette.accent.opacity(0.10) : Color.clear)
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
        .frame(height: CGFloat(Self.matchCount(model)) * Self.matchRowHeight)
        .animation(.snappy(duration: 0.18), value: results.map(\.entry.id))
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

    // MARK: Menu

    private var menuPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(KeyboardModel.MenuTab.allCases, id: \.self) { tab in
                    chip(tab.rawValue, on: model.menuTab == tab) {
                        model.menuTab = tab
                        if tab != .documents { model.personFilter = nil }
                    }
                }
            }
            .frame(height: 34)
            switch model.menuTab {
            case .people:
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(model.people) { p in
                            Button { model.showDocuments(of: p) } label: {
                                HStack {
                                    Text(p.name).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 4)
                                    Text("\(model.documentCount(for: p)) rows").font(.system(size: 12)).foregroundStyle(Palette.ink2)
                                }
                                .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 36)
                                .foregroundStyle(Palette.ink).background(Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.people.isEmpty {
                            Text(model.status ?? "No people in the vault yet").font(.system(size: 13)).foregroundStyle(Palette.ink2).padding(.top, 16)
                        }
                    }
                }
            case .documents:
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        if let p = model.people.first(where: { $0.id == model.personFilter }) {
                            caption(p.name)
                        }
                        ForEach(model.menuEntries) { e in entryRow(e, height: 36) }
                    }
                }
            case .settings:
                settingsCard
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

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

    /// Date format for this keyboard session. A format picked by holding a date key is remembered for
    /// that row and field and wins over this card. Long-term settings stay in the app.
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DATE FORMAT").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.ink2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                smallChip("Auto: \(model.dateOverride == nil ? model.datePlan.reason : model.fieldContext.region + " region")", on: model.dateOverride == nil) { model.setDateStyle(nil) }
                ForEach(FillFormats.DateStyle.menu, id: \.self) { st in
                    smallChip(st.rawValue, on: model.dateOverride == st) { model.setDateStyle(st) }
                }
            }
            Text("Start page and lock window: DocuVault app, Settings, Keyboard.")
                .font(.system(size: 11)).foregroundStyle(Palette.ink2).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }

    private func smallChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 30)
                .foregroundStyle(on ? Palette.ink : Palette.ink2)
                .background(on ? Palette.surface : Palette.canvasDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Palette.hairline : Color.clear, lineWidth: 1))
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

    // MARK: Locked

    /// One large target instead of greyed-out keys that belong to no document.
    private var unlockPanel: some View {
        Button {
            guard model.hasFullAccess else { return }
            Task { await model.unlock() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "faceid").font(.system(size: 34, weight: .light))
                Text(model.hasFullAccess ? "Unlock with Face ID" : "Full Access is off")
                    .font(.system(size: 17, weight: .semibold))
                Text(model.status ?? (model.hasFullAccess
                                      ? "Values stay on this phone"
                                      : "Turn it on in Settings, then Keyboards"))
                    .font(.system(size: 12)).foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Palette.ink)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFullAccess)
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
                    .sheen(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private var isShowingBack: Bool { holdSpec != nil || (model.isUnlocked && model.showsBack) }

    private func dismissOrBack() {
        if holdSpec != nil { closeMenu() }
        else if model.isUnlocked, model.showsBack { model.back() }
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
    static let sheen = LinearGradient(
        colors: [Color(red: 0x22/255, green: 0x28/255, blue: 0x2F/255),
                 Color(red: 0x5C/255, green: 0x66/255, blue: 0x72/255),
                 Color(red: 0x22/255, green: 0x28/255, blue: 0x2F/255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
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
    static let canvas = Color(light: 0xE8EAEF, dark: 0x2B2B2B)
    static let canvasDeep = Color(light: 0xEEF0F3, dark: 0x3A3A3A)
    static let glass = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.14)
    static let glassEdge = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.95, darkAlpha: 0.10)
    static let menu = Color(light: 0xF6F7FA, dark: 0x3A3A3C)
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

extension View {
    /// The app's gunmetal sheen for the return keys (Open, Done, Back). Mirrors `accentSheen(in:)` in
    /// the app's Theme, which this target cannot import.
    func sheen<S: Shape>(in shape: S) -> some View {
        self
            .background(shape.fill(Palette.sheen))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.2)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}
