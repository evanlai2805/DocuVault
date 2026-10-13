import SwiftUI
import DocuVaultCore

/// The keyboard surface (checkpoints 13c and 15). One bar: menu circle · Search · scan circle · lock
/// circle. Below it one of: the start page, the keys, the search pad, the menu, or the scan. A hold on
/// any key raises a menu drawn inside the keyboard: the value on top, then only the options that make
/// sense for that field. Bottom: globe · space · backspace · Done or Back.
/// Keys show no check status; the app judges. Values are never drawn on keys.
struct KeyboardRootView: View {
    static let height: CGFloat = 300
    /// Three columns, four rows of 40pt keys under the "Filling from" line: 14 + 6 + 4 × 40 + 3 × 6 = 198pt,
    /// exactly the room left at 300pt once the bar and bottom row are taken out. Ten keys max, nothing scrolls.
    static let columns = 3
    static let rows = 4
    static let keyHeight: CGFloat = 40
    static let keyInset: CGFloat = 12

    @Bindable var model: KeyboardModel
    let showsGlobe: Bool
    @State private var holdSpec: FillFormats.KeySpec?
    @State private var scanScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 6) {
            if model.isUnlocked {
                bar
                ZStack(alignment: .topLeading) {
                    content
                        .opacity(holdSpec == nil ? 1 : 0.35)
                    if let spec = holdSpec {
                        Color.clear.contentShape(Rectangle()).onTapGesture { holdSpec = nil }
                        holdMenu(spec)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                unlockPanel
            }
            bottomRow
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
        .background(Palette.canvas)
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
            circle("line.3.horizontal", style: model.panel == .menu ? .matteOpen : .matte) { model.toggleMenu() }
                .accessibilityLabel("Menu")
            Button { model.openSearch() } label: {
                HStack(spacing: 6) {
                    if model.panel == .search {
                        Text(model.searchText).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Rectangle().fill(Palette.accent).frame(width: 1.5, height: 16)
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

    private enum CircleStyle { case matte, matteOpen, ink, dim, accent, green }

    private func circle(_ symbol: String, style: CircleStyle, action: @escaping () -> Void) -> some View {
        let fill: Color, fg: Color
        switch style {
        case .matte, .matteOpen: fill = Palette.graphite; fg = .white
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
                .overlay(Circle().stroke(style == .matteOpen ? Palette.accent : Palette.glassEdge, lineWidth: style == .matteOpen ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Start page

    /// Two most used, then two most recent (13c). Captions 13pt, rows 36pt: 195pt in all.
    private var startPage: some View {
        let page = model.startPage
        return VStack(spacing: 5) {
            if page.mostUsed.isEmpty, page.recent.isEmpty {
                Text(model.status ?? "Nothing in the vault yet")
                    .font(.system(size: 13)).foregroundStyle(Palette.ink2).padding(.top, 20)
            }
            if !page.mostUsed.isEmpty {
                caption("Most used")
                ForEach(page.mostUsed) { e in entryRow(e, height: 36) }
            }
            if !page.recent.isEmpty {
                caption(page.mostUsed.isEmpty ? "Documents" : "Recent")
                ForEach(page.recent) { e in entryRow(e, height: 36) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 13)
            .padding(.horizontal, 4)
    }

    private func entryRow(_ e: FillEntry, height: CGFloat, trailing: String? = nil) -> some View {
        Button { model.select(e) } label: {
            HStack(spacing: 6) {
                if case .shared = e.kind {
                    Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(Palette.accent)
                }
                Text(e.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(trailing ?? e.personName).font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
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
        return Button {
            guard enabled, holdSpec == nil else { return }
            model.insert(spec)
        } label: {
            VStack(spacing: 1) {
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
                if holdSpec == spec {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            guard enabled else { return }
            holdSpec = spec
        })
        .accessibilityLabel(spec.label)
    }

    /// Hold menu: the value on top (tap inserts), then the field's options. Drawn by the keyboard
    /// itself because an extension cannot present a system context menu above the host app.
    private func holdMenu(_ spec: FillFormats.KeySpec) -> some View {
        let options = model.holdOptions(for: spec)
        return VStack(spacing: 0) {
            Button {
                model.insertPreview(spec); holdSpec = nil
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(Palette.ink2)
                    Text(model.rendered(spec) ?? "").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.ink)
                        .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                    Text("Tap to insert").font(.system(size: 11)).foregroundStyle(Palette.ink2)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface)
            }
            .buttonStyle(.plain)
            ForEach(options) { o in
                Divider().overlay(Palette.hairline)
                Button { o.action(); holdSpec = nil } label: {
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
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 220)
        .background(Palette.menu)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.glassEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .padding(.leading, 8).padding(.top, 4)
    }

    // MARK: Search

    /// The keyboard's own letter pad: letters go to the query, never to the form (13c Q3).
    private var searchPanel: some View {
        let results = model.searchResults
        return VStack(spacing: 6) {
            VStack(spacing: 4) {
                if results.isEmpty {
                    Text(model.searchText.isEmpty ? "Type a name or a document" : "No match")
                        .font(.system(size: 13)).foregroundStyle(Palette.ink2).frame(height: 32)
                } else {
                    ForEach(results.prefix(2)) { e in entryRow(e, height: 32) }
                }
            }
            .frame(height: 68, alignment: .top)
            VStack(spacing: 5) {
                padRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
                padRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"])
                HStack(spacing: 4) {
                    padKey("Back", wide: true) { model.back() }
                    padRow(["z", "x", "c", "v", "b", "n", "m"])
                    padKey("delete.left", wide: true, symbol: true) { model.backspaceSearch() }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func padRow(_ letters: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { l in padKey(l) { model.typeSearch(l) } }
        }
    }

    private func padKey(_ title: String, wide: Bool = false, symbol: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if symbol { Image(systemName: title).font(.system(size: 16)) }
                else { Text(title).font(.system(size: wide ? 13 : 17, weight: wide ? .medium : .regular)) }
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity).frame(width: wide ? 44 : nil, height: 36)
            .background(wide ? Palette.surfaceOff : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
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

    /// Date format for this keyboard session. Long-term settings stay in the app.
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
                    .frame(width: 70, height: 42).background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Palette.accent.opacity(0.35), radius: 4, y: 2)
            }.buttonStyle(.plain)
        }
    }

    private var isShowingBack: Bool { holdSpec != nil || (model.isUnlocked && model.showsBack) }

    private func dismissOrBack() {
        if holdSpec != nil { holdSpec = nil }
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
/// Keep in step with `DocuVault/Design/Theme.swift`.
enum Palette {
    static let accent = Color(red: 0x2F/255, green: 0x6B/255, blue: 0xFF/255)
    static let graphite = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let verified = Color(red: 0x1B/255, green: 0x7F/255, blue: 0x4C/255)
    static let ink = Color.primary
    static let ink2 = Color(.secondaryLabel)
    static let ink3 = Color(red: 0xB0/255, green: 0xB3/255, blue: 0xBA/255)
    static let hairline = Color(.separator)
    static let surface = Color.white
    static let surfaceOff = Color(red: 0xEC/255, green: 0xED/255, blue: 0xF0/255)
    static let canvas = Color(red: 0xE8/255, green: 0xEA/255, blue: 0xEF/255)
    static let canvasDeep = Color(red: 0xEE/255, green: 0xF0/255, blue: 0xF3/255)
    static let glass = Color.white.opacity(0.62)
    static let glassEdge = Color.white.opacity(0.95)
    static let menu = Color(red: 0xF6/255, green: 0xF7/255, blue: 0xFA/255)
}

/// Backspace that behaves like Apple's: one delete on tap, then after a short hold it repeats,
/// speeding up the longer you hold.
struct RepeatingKey: View {
    let systemImage: String
    let action: () -> Void
    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(pressed ? Palette.surface : Palette.surfaceOff)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
