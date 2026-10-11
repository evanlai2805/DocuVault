import SwiftUI
import DocuVaultCore

/// The keyboard surface. Top: lock + person chips. Second row: document chips. Grid: field keys. Bottom: globe · space · ⌫ · Done.
/// Values are never drawn on keys; hints show the last 4 or the format that will be used.
struct KeyboardRootView: View {
    static let height: CGFloat = 300
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
            topRow
            if model.isUnlocked && model.currentPerson != nil { docRow }
            if let spec = holdSpec { holdPanel(spec) } else { keyGrid }
            bottomRow
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
        .background(keyBG)
    }

    // MARK: Rows

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                lockButton
                if !model.isUnlocked {
                    Text(model.status ?? (model.hasFullAccess ? "Unlock with Face ID" : "Full Access is off — enable it in Settings"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink2).lineLimit(1)
                } else {
                    ForEach(model.people) { p in
                        chip(p.name, on: p.id == model.selectedPerson) {
                            model.selectedPerson = p.id
                            model.selectedDoc = model.currentDocs.first?.id
                        }
                    }
                    if model.people.isEmpty { Text(model.status ?? "").font(.system(size: 13)).foregroundStyle(ink2) }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 34)
    }

    private var docRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.currentDocs) { d in
                    chip(d.title, on: d.id == model.selectedDoc, small: true, badge: d.checksOK ? nil : "!") { model.selectedDoc = d.id }
                }
                chip("Shared", on: model.selectedDoc == nil, small: true) { model.selectedDoc = nil }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 30)
    }

    private var specs: [FillFormats.KeySpec] {
        guard model.isUnlocked else { return FillFormats.keys(for: .bankCard) }
        if model.selectedDoc == nil { return FillFormats.sharedKeys }
        return model.currentDoc.map { FillFormats.keys(for: $0.type) } ?? []
    }

    private var keyGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
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

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if showsGlobe {
                bottomKey("globe", systemImage: true) { model.globe() }.frame(width: 52)
            }
            Button { model.space() } label: {
                Text(model.lastInserted.map { "inserted \($0)" } ?? "space").font(.system(size: 15)).foregroundStyle(ink2)
                    .frame(maxWidth: .infinity).frame(height: 42).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            }.buttonStyle(.plain)
            bottomKey("delete.left", systemImage: true) { model.backspace() }.frame(width: 52)
            Button { holdSpec == nil ? model.done() : (holdSpec = nil) } label: {
                Text(holdSpec == nil ? "Done" : "Back").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 70, height: 42).background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }.buttonStyle(.plain)
        }
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

    /// Person chips: blue when selected. Document chips (small): white with primary text when selected, translucent otherwise.
    private func chip(_ title: String, on: Bool, small: Bool = false, badge: String? = nil, action: @escaping () -> Void) -> some View {
        let fg: Color = small ? (on ? Color.primary : ink2) : (on ? .white : Color.primary)
        let bg: Color = small ? (on ? Color.white : Color.white.opacity(0.6)) : (on ? accent : Color.white)
        return Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: small ? 13 : 14, weight: .semibold)).lineLimit(1)
                if let badge { Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0x8E/255, green: 0x1F/255, blue: 0x1F/255)) }
            }
            .padding(.horizontal, small ? 10 : 12).frame(height: small ? 28 : 32)
            .foregroundStyle(fg)
            .background(bg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
