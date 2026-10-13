import Foundation
import SwiftData
import CryptoKit
import CoreGraphics
import DocuVaultCore

/// The unlocked key, held for the keyboard's whole process rather than by one controller. iOS builds a
/// new controller each time the keyboard appears, so an instance property locked on every app switch.
/// The key now survives that inside the lock window (Evan, checkpoint 14: 1 min by default). Memory only:
/// a restart or iOS closing the keyboard drops it.
@MainActor enum KeyboardVault {
    static var key: SymmetricKey?
    static var lastActivity = Date()
    /// The row you were filling from, kept with the key so that inside the lock window the keyboard
    /// reopens on the same keys (checkpoint 13c Q2). Dropped with the key.
    static var lastEntryID: String?

    /// Seconds the keyboard stays unlocked after the last key. 0 = lock as soon as it hides.
    /// Written by the app's Settings into the App Group.
    static var window: TimeInterval {
        guard let d = UserDefaults(suiteName: AppFiles.appGroupID), d.object(forKey: AppFiles.keyboardLockWindowKey) != nil
        else { return AppFiles.keyboardLockWindowDefault }
        return max(0, d.double(forKey: AppFiles.keyboardLockWindowKey))
    }

    static func touch() { lastActivity = Date() }
    static func wipe() { key = nil; lastEntryID = nil }
    static func expireIfStale(now: Date = Date()) {
        if key != nil, now.timeIntervalSince(lastActivity) > window { wipe() }
    }
}

/// Keyboard state: people, their vault documents, the unlocked key, and the insert bridge.
@MainActor @Observable
final class KeyboardModel {
    struct Person: Identifiable, Hashable {
        let id: UUID
        let name: String
        let kind: PersonKind
        let fullName: String, address: String, phone: String, email: String
    }
    struct Doc: Identifiable, Hashable {
        let id: UUID
        let title: String
        let type: DocumentType
        let fields: [String: (value: Data?, plain: String)]   // key → sealed or plain
        let firstPageFile: String?                            // for the scan circle
        static func == (a: Doc, b: Doc) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    /// What the content area shows (checkpoint 13c/15). The hold menu is view state, not a panel.
    enum Panel: Equatable { case start, keys, search, menu, scan }
    enum MenuTab: String, CaseIterable { case people = "People", documents = "Documents", settings = "Settings" }

    /// One row of the hold menu under the preview card.
    struct HoldOption: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let selected: Bool
        let action: () -> Void
    }

    let hasFullAccess: Bool
    private let insertText: (String) -> Void
    private let deleteBack: () -> Void
    private let nextKeyboard: () -> Void
    private let dismissKeyboard: () -> Void

    private(set) var people: [Person] = []
    private(set) var docsByPerson: [UUID: [Doc]] = [:]
    var selectedPerson: UUID?
    var selectedDoc: UUID?          // nil = Shared fields
    private(set) var key: SymmetricKey?
    private(set) var status: String?
    var isSecureField = false

    var panel: Panel = .start
    var menuTab: MenuTab = .people
    var searchText = ""
    var personFilter: UUID?          // nil = every person
    private var lastUsed: [String: Date] = [:]
    private var useCounts: [String: Int] = [:]
    /// The wording or format last picked in the hold menu, per person, document and field
    /// ("<entry id>|<field key>" → option id). Survives the keyboard closing (Evan, 15 follow-up).
    private var fieldPrefs: [String: String] = [:]
    private static let lastUsedDefaultsKey = "keyboard.lastUsed"
    private static let useCountsDefaultsKey = "keyboard.useCounts"
    private static let fieldPrefsDefaultsKey = "keyboard.fieldPrefs"

    /// What the host text field tells us; refreshed on every textDidChange.
    var fieldContext = FillInference.Context(region: Locale.current.region?.identifier ?? "SG")
    /// Explicit picks from the hold menu or the Settings card override inference for this keyboard session.
    var dateOverride: FillFormats.DateStyle?
    var expiryOverride: FillFormats.ExpiryStyle?

    var datePlan: FillInference.Choice<FillInference.DatePlan> {
        if let o = dateOverride { return .init(value: .full(o), reason: "Your choice") }
        return FillInference.date(fieldContext)
    }
    var expiryChoice: FillInference.Choice<FillFormats.ExpiryStyle> {
        if let o = expiryOverride { return .init(value: o, reason: "Your choice") }
        return FillInference.expiry(fieldContext)
    }

    init(hasFullAccess: Bool, insert: @escaping (String) -> Void, deleteBackward: @escaping () -> Void,
         nextKeyboard: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.hasFullAccess = hasFullAccess
        self.insertText = insert
        self.deleteBack = deleteBackward
        self.nextKeyboard = nextKeyboard
        self.dismissKeyboard = dismiss
        KeyboardVault.expireIfStale()
        self.key = KeyboardVault.key
    }

    var isUnlocked: Bool { key != nil }
    var currentPerson: Person? { people.first { $0.id == selectedPerson } }
    var currentDocs: [Doc] { selectedPerson.flatMap { docsByPerson[$0] } ?? [] }
    var currentDoc: Doc? { currentDocs.first { $0.id == selectedDoc } }
    var hasSelection: Bool { selectedPerson != nil && (selectedDoc != nil || currentPerson != nil) && currentEntry != nil }

    // MARK: Load

    func load() {
        guard hasFullAccess else { status = "Full Access is off. Enable it in Settings, then Keyboards"; return }
        do {
            let container = try AppFiles.makeContainer()
            let ctx = ModelContext(container)
            let persons = try ctx.fetch(FetchDescriptor<StoredPerson>())
            people = persons.map { Person(id: $0.id, name: $0.name, kind: $0.kind, fullName: $0.fullName, address: $0.address, phone: $0.phone, email: $0.email) }
                .sorted { a, b in rank(a.kind) == rank(b.kind) ? a.name < b.name : rank(a.kind) < rank(b.kind) }
            var map: [UUID: [Doc]] = [:]
            for p in persons {
                map[p.id] = p.documents.filter { $0.sensitive }
                    .sorted { FillFormats.order($0.type) < FillFormats.order($1.type) }
                    .map { d in Doc(id: d.id, title: d.title, type: d.type,
                                    fields: Dictionary(uniqueKeysWithValues: d.fields.map { ($0.key, ($0.sealedValue, $0.value)) }),
                                    firstPageFile: d.pages.sorted { $0.index < $1.index }.first?.imageFileName) }
            }
            docsByPerson = map
            loadUsage()
            status = people.isEmpty ? "No people in the vault yet. Add one in DocuVault" : nil
            openingPanel()
        } catch {
            status = "Could not open the vault store"
        }
    }

    private func rank(_ k: PersonKind) -> Int { switch k { case .me: 0; case .family: 1; case .partner: 2; case .client: 3; case .other: 4 } }

    /// Where the keyboard opens (checkpoint 13c Q2 and the Settings option): inside the lock window,
    /// on the keys you left; otherwise on the start page chosen in Settings.
    private func openingPanel() {
        if isUnlocked, let id = KeyboardVault.lastEntryID, let e = entries.first(where: { $0.id == id }) {
            select(e)
            return
        }
        switch startPageMode {
        case .suggestions:
            panel = .start
        case .last:
            if let e = FillPicker.sorted(entries, lastUsed: lastUsed).first, lastUsed[e.id] != nil { select(e) } else { panel = .start }
        case .list:
            personFilter = nil
            menuTab = .documents
            panel = .menu
        }
    }

    private var startPageMode: AppFiles.KeyboardStartPage {
        sharedDefaults?.string(forKey: AppFiles.keyboardStartPageKey).flatMap(AppFiles.KeyboardStartPage.init) ?? .suggestions
    }

    // MARK: Rows

    /// Every row the keyboard can offer: each document and each person's shared fields.
    var entries: [FillEntry] {
        var out: [FillEntry] = []
        for p in people {
            for d in docsByPerson[p.id] ?? [] {
                out.append(FillEntry(title: d.title, personName: p.name, personID: p.id, kind: .document(d.id)))
            }
            out.append(FillEntry(title: "Contact details", personName: p.name, personID: p.id, kind: .shared))
        }
        return FillPicker.sorted(out, lastUsed: lastUsed)
    }

    var startPage: FillPicker.StartPage { FillPicker.startPage(entries, useCounts: useCounts, lastUsed: lastUsed) }
    var hasUsage: Bool { !lastUsed.isEmpty }

    var searchResults: [FillEntry] { FillPicker.filter(entries, query: searchText) }

    var menuEntries: [FillEntry] { FillPicker.filter(entries, person: personFilter) }

    func documentCount(for person: Person) -> Int { (docsByPerson[person.id]?.count ?? 0) + 1 }

    var currentEntryKind: FillEntry.Kind { selectedDoc.map { .document($0) } ?? .shared }

    var currentEntry: FillEntry? {
        guard let person = selectedPerson else { return nil }
        let id = FillPicker.key(personID: person, kind: currentEntryKind)
        return entries.first { $0.id == id }
    }

    func select(_ e: FillEntry) {
        selectedPerson = e.personID
        switch e.kind {
        case .document(let id): selectedDoc = id
        case .shared: selectedDoc = nil
        }
        KeyboardVault.lastEntryID = e.id
        searchText = ""
        personFilter = nil
        panel = .keys
        markCurrentUsed(count: true)
    }

    // MARK: Panels

    func openSearch() { searchText = ""; panel = .search }
    func openMenu() { personFilter = nil; menuTab = .people; panel = .menu }
    func toggleMenu() { panel == .menu ? back() : openMenu() }
    func toggleScan() {
        guard currentDoc?.firstPageFile != nil else { return }
        panel == .scan ? back() : (panel = .scan)
    }
    func showDocuments(of person: Person) { personFilter = person.id; menuTab = .documents }

    /// Back from search, the menu or the scan: to the keys when something is loaded, else the start page.
    func back() {
        searchText = ""
        panel = currentEntry != nil ? .keys : .start
    }

    var showsBack: Bool { panel == .search || panel == .menu || panel == .scan }

    func typeSearch(_ letter: String) { searchText += letter }
    func backspaceSearch() { if !searchText.isEmpty { searchText.removeLast() } }

    func setDateStyle(_ style: FillFormats.DateStyle?) { dateOverride = style; KeyboardVault.touch() }

    /// The loaded document's first page, decrypted into memory only while the scan panel shows it.
    func scanImage() -> CGImage? {
        guard let file = currentDoc?.firstPageFile else { return nil }
        return PageStore.load(file, vaultKey: key)
    }

    // MARK: Usage (App Group, ids and dates only)

    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: AppFiles.appGroupID) }

    private func loadUsage() {
        if let raw = sharedDefaults?.dictionary(forKey: Self.lastUsedDefaultsKey) as? [String: Double] {
            lastUsed = raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        if let raw = sharedDefaults?.dictionary(forKey: Self.useCountsDefaultsKey) as? [String: Int] {
            useCounts = raw
        }
        if let raw = sharedDefaults?.dictionary(forKey: Self.fieldPrefsDefaultsKey) as? [String: String] {
            fieldPrefs = raw
        }
    }

    /// Loading a row counts as a use; an insert refreshes its recency.
    private func markCurrentUsed(count: Bool = false) {
        guard let person = selectedPerson else { return }
        let id = FillPicker.key(personID: person, kind: currentEntryKind)
        lastUsed[id] = Date()
        if count { useCounts[id, default: 0] += 1 }
        sharedDefaults?.set(lastUsed.mapValues(\.timeIntervalSince1970), forKey: Self.lastUsedDefaultsKey)
        sharedDefaults?.set(useCounts, forKey: Self.useCountsDefaultsKey)
    }

    private func prefKey(_ spec: FillFormats.KeySpec) -> String? {
        guard let person = selectedPerson else { return nil }
        return FillPicker.key(personID: person, kind: currentEntryKind) + "|" + spec.fieldKey
    }

    /// The option id picked last for this field on this row, if any.
    func preference(for spec: FillFormats.KeySpec) -> String? {
        prefKey(spec).flatMap { fieldPrefs[$0] }
    }

    private func remember(_ spec: FillFormats.KeySpec, option: String) {
        guard let k = prefKey(spec) else { return }
        fieldPrefs[k] = option
        sharedDefaults?.set(fieldPrefs, forKey: Self.fieldPrefsDefaultsKey)
    }

    // MARK: Unlock

    func unlock() async {
        status = nil
        do {
            let k = try await Task.detached(priority: .userInitiated) { try VaultKeychain.load(reason: "Fill from your DocuVault") }.value
            if let k {
                key = k; KeyboardVault.key = k; KeyboardVault.touch()
                openingPanel()
            } else { status = "No vault key yet. Open DocuVault and unlock the Vault once" }
        } catch let e as VaultError {
            status = VaultSession.describe(e)
        } catch {
            status = error.localizedDescription
        }
    }

    func lock() { key = nil; KeyboardVault.wipe(); panel = .start }

    /// The keyboard is about to show: drop the key if the lock window has passed while it was hidden.
    func willAppear() {
        KeyboardVault.expireIfStale()
        if KeyboardVault.key == nil { key = nil; panel = .start }
    }

    /// The keyboard hid, usually because you switched apps. The lock window starts now; with
    /// "Immediately" chosen in Settings it locks on the spot, as it always did before.
    func didDisappear() {
        KeyboardVault.touch()
        if KeyboardVault.window == 0 { lock() }
    }

    // MARK: Values

    func value(for spec: FillFormats.KeySpec) -> String? {
        if selectedDoc == nil {
            guard let p = currentPerson else { return nil }
            switch spec.fieldKey {
            case "fullName": return p.fullName.isEmpty ? nil : p.fullName
            case "address": return p.address.isEmpty ? nil : p.address
            case "postcode": return FillFormats.postcode(from: p.address)
            case "phone": return p.phone.isEmpty ? nil : p.phone
            case "email": return p.email.isEmpty ? nil : p.email
            default: return nil
            }
        }
        guard let doc = currentDoc, let f = doc.fields[spec.fieldKey] else { return nil }
        if let sealed = f.value {
            guard let key else { return nil }
            return try? VaultCrypto.openString(sealed, key: key)
        }
        return f.plain.isEmpty ? nil : f.plain
    }

    func hasValue(_ spec: FillFormats.KeySpec) -> Bool {
        if selectedDoc == nil { return value(for: spec) != nil }
        guard let doc = currentDoc, let f = doc.fields[spec.fieldKey] else { return false }
        return f.value != nil || !f.plain.isEmpty
    }

    /// Hint shown under the key. Never the full value of a sensitive field.
    func hint(for spec: FillFormats.KeySpec) -> String? {
        switch spec.kind {
        case .cardNumber: return value(for: .init(fieldKey: "last4", label: "", kind: .text)).map { "•" + $0 }
        case .date:
            if let st = preferredDateStyle(spec) { return st.rawValue }
            switch datePlan.value {
            case .full(let st): return st.rawValue
            case .component(let c): return "\(String(describing: c).capitalized) only"
            }
        case .expiry: return preferredExpiryStyle(spec).rawValue
        case .holdOnly: return "Hold"
        case .text:
            if ["nationality", "issuingCountry", "sex"].contains(spec.fieldKey) { return rendered(spec) }
            return nil
        }
    }

    private func preferredDateStyle(_ spec: FillFormats.KeySpec) -> FillFormats.DateStyle? {
        preference(for: spec).flatMap(FillFormats.DateStyle.init(rawValue:))
    }
    private func preferredExpiryStyle(_ spec: FillFormats.KeySpec) -> FillFormats.ExpiryStyle {
        preference(for: spec).flatMap(FillFormats.ExpiryStyle.init(rawValue:)) ?? expiryChoice.value
    }
    private func preferredSpaced(_ spec: FillFormats.KeySpec) -> Bool {
        switch preference(for: spec) {
        case "spaced": true
        case "plain": false
        default: FillInference.cardSpaced(fieldContext)
        }
    }
    /// The wording a tap inserts for a field with variants: the remembered one, else the value as stored.
    private func preferredVariant(_ spec: FillFormats.KeySpec, raw: String) -> String {
        let vs = FillVariants.variants(fieldKey: spec.fieldKey, value: raw)
        guard !vs.isEmpty else { return raw }
        if let id = preference(for: spec), let v = vs.first(where: { $0.id == id }) { return v.text }
        return raw
    }

    // MARK: Insert

    /// What a tap on the key inserts right now: the remembered pick for this row and field first, then
    /// the session choice, then inference. The hold menu's preview card shows exactly this.
    func rendered(_ spec: FillFormats.KeySpec) -> String? {
        guard let raw = value(for: spec) else { return nil }
        switch spec.kind {
        case .cardNumber: return FillFormats.cardNumber(raw, spaced: preferredSpaced(spec))
        case .date:
            if let st = preferredDateStyle(spec) { return FillFormats.date(raw, style: st) }
            switch datePlan.value {
            case .full(let st): return FillFormats.date(raw, style: st)
            case .component(let c): return FillInference.component(c, of: raw)
            }
        case .expiry: return FillFormats.expiry(raw, style: preferredExpiryStyle(spec))
        case .holdOnly: return raw
        case .text:
            if spec.fieldKey == "name", preference(for: spec) == "pinyin",
               let pinyin = value(for: .init(fieldKey: "namePinyin", label: "", kind: .text)) { return pinyin }
            return preferredVariant(spec, raw: raw)
        }
    }

    func insert(_ spec: FillFormats.KeySpec) {
        guard spec.kind != .holdOnly, let text = rendered(spec) else { return }
        commit(text)
    }

    /// From the hold menu's preview card: inserts even a hold-only key, because the hold was deliberate.
    func insertPreview(_ spec: FillFormats.KeySpec) {
        guard let text = rendered(spec) else { return }
        commit(text)
    }

    private func commit(_ text: String) {
        insertText(text)
        markCurrentUsed()
        KeyboardVault.touch()
    }

    /// The rows under the preview card (checkpoint 15): only what makes sense for the field. Picking
    /// one inserts it and remembers it for this row and field.
    func holdOptions(for spec: FillFormats.KeySpec) -> [HoldOption] {
        guard let raw = value(for: spec) else { return [] }
        let pref = preference(for: spec)
        switch spec.kind {
        case .date:
            let current: FillFormats.DateStyle? = preferredDateStyle(spec) ?? { if case .full(let s) = datePlan.value { return s }; return nil }()
            return FillFormats.DateStyle.menu.map { st in
                HoldOption(id: st.rawValue, title: st.rawValue, detail: FillFormats.date(raw, style: st), selected: st == current) { [weak self] in
                    self?.remember(spec, option: st.rawValue)
                    self?.commit(FillFormats.date(raw, style: st))
                }
            }
        case .expiry:
            let current = preferredExpiryStyle(spec)
            return FillFormats.ExpiryStyle.allCases.map { st in
                HoldOption(id: st.rawValue, title: st.rawValue, detail: FillFormats.expiry(raw, style: st), selected: st == current) { [weak self] in
                    self?.remember(spec, option: st.rawValue)
                    self?.commit(FillFormats.expiry(raw, style: st))
                }
            }
        case .cardNumber:
            let spaced = preferredSpaced(spec)
            return [
                HoldOption(id: "plain", title: "Without spaces", detail: FillFormats.cardNumber(raw, spaced: false), selected: !spaced) { [weak self] in
                    self?.remember(spec, option: "plain"); self?.commit(FillFormats.cardNumber(raw, spaced: false)) },
                HoldOption(id: "spaced", title: "With spaces", detail: FillFormats.cardNumber(raw, spaced: true), selected: spaced) { [weak self] in
                    self?.remember(spec, option: "spaced"); self?.commit(FillFormats.cardNumber(raw, spaced: true)) },
            ]
        case .text:
            // Nationality, issuing country and sex offer the wordings a form may want.
            let vs = FillVariants.variants(fieldKey: spec.fieldKey, value: raw)
            if vs.count > 1 {
                let current = rendered(spec)
                return vs.map { v in
                    HoldOption(id: v.id, title: v.text, detail: nil, selected: v.text == current) { [weak self] in
                        self?.remember(spec, option: v.id); self?.commit(v.text)
                    }
                }
            }
            // A Chinese name offers its pinyin as well, when the document has one.
            if spec.fieldKey == "name", currentDoc?.type == .chinaID, let pinyin = value(for: .init(fieldKey: "namePinyin", label: "", kind: .text)) {
                return [
                    HoldOption(id: "chars", title: "Characters", detail: raw, selected: pref != "pinyin") { [weak self] in
                        self?.remember(spec, option: "chars"); self?.commit(raw) },
                    HoldOption(id: "pinyin", title: "Pinyin", detail: pinyin, selected: pref == "pinyin") { [weak self] in
                        self?.remember(spec, option: "pinyin"); self?.commit(pinyin) },
                ]
            }
            return []
        case .holdOnly:
            return []
        }
    }

    func backspace() { deleteBack(); KeyboardVault.touch() }
    func space() { insertText(" "); KeyboardVault.touch() }
    func globe() { nextKeyboard() }
    func done() { dismissKeyboard() }
}
