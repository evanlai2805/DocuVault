import SwiftUI
import DocuVaultCore

/// The keyboard surface. One selector bar (lock + the loaded document), then either the field keys,
/// the picker, or a format panel. Bottom: globe · space · ⌫ · Done.
/// Values are never drawn on keys; hints show the last 4 or the format that will be used.
/// Nothing scrolls horizontally: the person and document chip rows rendered blurred inside the
/// keyboard host, so selection moved into a picker that replaces the keys.
struct KeyboardRootView: View {
    static let height: CGFloat = 300
    /// Three columns, and three rows fit at 300pt once the bar and bottom row are taken out.
    static let columns = 3
    static let visibleRows = 3

    @Bindable var model: KeyboardModel
    let showsGlobe: Bool
    @State private var holdSpec: FillFormats.KeySpec?

    private let accent = Color(red: 0x2F/255, green: 0x6B/255, blue: 0xFF/255)
    private let graphite = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    private let green = Color(red: 0x1B/255, green: 0x7F/255, blue: 0x4C/255)
    private let keyBG = Color(red: 0xD1/255, green: 0xD4/255, blue: 0xDA/255)
    private let ink2 = Color(.secondaryLabel)

    var body: some View {
        VStack(spacing: 6) {
            if model.isUnlocked {
                selectorBar
                if model.isPickerOpen {
                    pickerPanel
                } else if let spec = holdSpec {
                    holdPanel(spec)
                } else {
                    keyArea
                }
            } else {
                unlockPanel
            }
            bottomRow
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
        .background(keyBG)
    }

    // MARK: Selector

    /// One row, no horizontal scrolling. Shows what is loaded; tap to pick something else.
    private var selectorBar: some View {
        HStack(spacing: 6) {
            lockButton
            Button {
                model.isPickerOpen ? model.closePicker() : model.openPicker()
            } label: {
                HStack(spacing: 6) {
                    Text(model.currentEntry?.title ?? "Choose a document")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let person = model.currentEntry?.personName {
                        Text(person)
                            .font(.system(size: 13))
                            .foregroundStyle(ink2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: model.isPickerOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ink2)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a document to fill from")
        }
        .frame(height: 34)
    }

    /// Replaces the keys, so rows stay full size. Vertical scrolling only: the chip rows that
    /// scrolled sideways are what rendered blurred, so the person filter wraps instead.
    private var pickerPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 5) {
                if model.people.count > 1 { personFilterGrid }
                ForEach(model.visibleEntries) { entry in
                    Button { model.select(entry) } label: { entryRow(entry) }
                        .buttonStyle(.plain)
                }
                if model.visibleEntries.isEmpty {
                    Text(model.people.isEmpty ? (model.status ?? "Nothing in the vault yet")
                                              : "Nothing for this person")
                        .font(.system(size: 13)).foregroundStyle(ink2)
                        .padding(.top, 16)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Narrows the list without typing. Wraps over as many rows as it needs, so any number of
    /// people fits and nothing has to scroll sideways.
    private var personFilterGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
            filterButton("All", on: model.personFilter == nil) { model.personFilter = nil }
            ForEach(model.people) { p in
                filterButton(p.name, on: model.personFilter == p.id) { model.personFilter = p.id }
            }
        }
        .padding(.bottom, 3)
    }

    private func filterButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 28)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? accent : Color.white.opacity(0.75))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func entryRow(_ e: FillEntry) -> some View {
        let selected = e.id == model.currentEntry?.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(e.personName).font(.system(size: 12)).foregroundStyle(ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(green)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
        .foregroundStyle(Color.primary)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent, lineWidth: 2)
            }
        }
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
                    .font(.system(size: 12)).foregroundStyle(ink2)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color.primary)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFullAccess)
    }

    // MARK: Keys

    private var specs: [FillFormats.KeySpec] {
        guard model.isUnlocked else { return [] }
        if model.selectedDoc == nil { return FillFormats.sharedKeys }
        return model.currentDoc.map { FillFormats.keys(for: $0.type) } ?? []
    }

    /// How many keys sit below the fold. Three columns, three rows visible at this height.
    private var hiddenKeyCount: Int {
        max(0, specs.count - Self.columns * Self.visibleRows)
    }

    private var keyArea: some View {
        VStack(spacing: 2) {
            keyGrid
                .overlay(alignment: .bottom) {
                    if hiddenKeyCount > 0 {
                        LinearGradient(colors: [keyBG.opacity(0), keyBG],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 24).allowsHitTesting(false)
                    }
                }
            if hiddenKeyCount > 0 {
                HStack(spacing: 3) {
                    Text("\(hiddenKeyCount) more").font(.system(size: 11, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(ink2)
            }
        }
    }

    private var keyGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.columns), spacing: 6) {
                ForEach(specs, id: \.fieldKey) { spec in
                    key(spec)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func key(_ spec: FillFormats.KeySpec) -> some View {
        let enabled = model.isUnlocked && model.hasValue(spec)
        let hint = enabled ? model.hint(for: spec) : nil
        return Button {
            guard enabled else { return }
            model.insert(spec)
        } label: {
            VStack(spacing: 2) {
                Text(spec.label).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(ink2).lineLimit(1) }
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .foregroundStyle(enabled ? Color.primary : ink2)
            .background(enabled ? Color.white : Color(red: 0xEC/255, green: 0xED/255, blue: 0xF0/255))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .overlay(alignment: .topTrailing) {
                if enabled, let doc = model.currentDoc, doc.checksOK, ["pan", "passportNumber", "nric", "idNumber"].contains(spec.fieldKey) {
                    Text("✓").font(.system(size: 9, weight: .bold)).foregroundStyle(green).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            guard enabled else { return }
            switch spec.kind {
            case .date, .expiry: holdSpec = spec
            case .cardNumber, .holdOnly: model.insert(spec, alternate: true)
            case .text: break
            }
        })
        .accessibilityLabel(spec.label)
    }

    /// Hold on a date or expiry key: pick a format. The pick overrides inference for this keyboard session.
    private func holdPanel(_ spec: FillFormats.KeySpec) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(spec.label) · format").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink2)
                Spacer()
                Text("auto: \(model.datePlan.reason)").font(.system(size: 11)).foregroundStyle(ink2)
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                if spec.kind == .date, let raw = model.value(for: spec) {
                    ForEach(FillFormats.DateStyle.allCases, id: \.self) { st in
                        formatKey(FillFormats.date(raw, style: st), sub: st.rawValue) { model.insertDate(spec, style: st); holdSpec = nil }
                    }
                } else if spec.kind == .expiry, let raw = model.value(for: spec) {
                    ForEach(FillFormats.ExpiryStyle.allCases, id: \.self) { st in
                        formatKey(FillFormats.expiry(raw, style: st), sub: st.rawValue) { model.insertExpiry(spec, style: st); holdSpec = nil }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func formatKey(_ title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(sub).font(.system(size: 11)).foregroundStyle(ink2)
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Color.white).foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if showsGlobe {
                bottomKey("globe", systemImage: true) { model.globe() }.frame(width: 52)
            }
            Button { model.space() } label: {
                Text("space").font(.system(size: 15)).foregroundStyle(ink2)
                    .frame(maxWidth: .infinity).frame(height: 42).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            }.buttonStyle(.plain)
            RepeatingKey(systemImage: "delete.left", action: { model.backspace() }).frame(width: 52)
            Button { dismissOrBack() } label: {
                Text(isShowingPanel ? "Back" : "Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 70, height: 42).background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private var isShowingPanel: Bool { holdSpec != nil || model.isPickerOpen }

    private func dismissOrBack() {
        if holdSpec != nil { holdSpec = nil }
        else if model.isPickerOpen { model.closePicker() }
        else { model.done() }
    }

    private func bottomKey(_ name: String, systemImage: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 18)).foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Color(red: 0xAD/255, green: 0xB3/255, blue: 0xBC/255))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }.buttonStyle(.plain)
    }

    private var lockButton: some View {
        Button {
            if model.isUnlocked { model.lock() } else { Task { await model.unlock() } }
        } label: {
            Image(systemName: model.isUnlocked ? "lock.open.fill" : "faceid")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(model.isUnlocked ? green : graphite)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFullAccess)
    }
}


/// Backspace that behaves like Apple's: one delete on tap, then after a short hold it repeats,
/// speeding up the longer you hold.
struct RepeatingKey: View {
    let systemImage: String
    let action: () -> Void
    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(pressed ? Color.white : Color(red: 0xAD/255, green: 0xB3/255, blue: 0xBC/255))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
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
