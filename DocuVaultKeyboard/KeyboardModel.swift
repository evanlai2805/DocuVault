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
    /// Past the lock window: the vault seals and the keyboard stops reopening on the last row.
    static func expireIfStale(now: Date = Date()) {
        if key != nil || lastEntryID != nil, now.timeIntervalSince(lastActivity) > window { wipe() }
    }
}

/// Keyboard state: people, every document, the vault key, and the insert bridge.
/// Checkpoint 20 (Evan, 14 Oct): every document is on the keyboard; only vault documents need Face ID.
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
        var favourite = false                                 // starred in the app (checkpoint 16)
        var sensitive = false                                 // a vault document: values sealed
        var personID: UUID?
        var capturedAt = Date.distantPast
        var lines: [String] = []                              // keyless regular documents: their text lines
        var sealedText: Data?                                 // keyless vault documents: text, sealed
        static func == (a: Doc, b: Doc) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    /// What the content area shows. Home is the four tabs; the vault is its own folders behind the door.
    /// The hold menu is view state, not a panel.
    enum Panel: Equatable { case home, keys, search, scan, vault }
    enum MenuTab: String, CaseIterable { case recents = "Recents", people = "People", documents = "Documents", favourites = "Favourites" }
    enum VaultFilter: Equatable { case group(String), person(UUID) }

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
    private(set) var docs: [Doc] = []
    /// Every row, built once per load: documents (owner, then type order), then each person's contact details.
    private(set) var entries: [FillEntry] = []
    /// The loaded row. Nil on home with nothing loaded.
    private(set) var selectedID: String?
    private(set) var key: SymmetricKey?
    private(set) var status: String?
    var isSecureField = false
    /// Field-hint test build (14 Oct, throwaway): what the host field says about itself, never its text.
    var fieldHintProbe = ""

    var panel: Panel = .home
    var menuTab: MenuTab = .recents
    var searchText = ""
    var personFilter: UUID?          // People tab: one person's rows
    var groupFilter: String?         // Documents tab: one group's rows
    var vaultFilter: VaultFilter?    // inside the vault: one category or person
    private var lastUsed: [String: Date] = [:]
    private var useCounts: [String: Int] = [:]
    /// The wording or format last picked in the hold menu, per row and field
    /// ("<entry id>|<field key>" → option id). Survives the keyboard closing (Evan, 15 follow-up).
    private var fieldPrefs: [String: String] = [:]
    private static let lastUsedDefaultsKey = "keyboard.lastUsed"
    private static let useCountsDefaultsKey = "keyboard.useCounts"
    private static let fieldPrefsDefaultsKey = "keyboard.fieldPrefs"

    /// What the host text field tells us; refreshed on every textDidChange.
    var fieldContext = FillInference.Context(region: Locale.current.region?.identifier ?? "SG")
    /// An explicit pick from the hold menu overrides inference for this keyboard session.
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

    /// The vault is open: its values can be read and filled.
    var isUnlocked: Bool { key != nil }
    var currentEntry: FillEntry? { selectedID.flatMap { id in entries.first { $0.id == id } } }
    var isSharedSelected: Bool { currentEntry?.kind == .shared }
    var selectedDoc: UUID? { if case .document(let id)? = currentEntry?.kind { return id }; return nil }
    var currentPerson: Person? { currentEntry?.personID.flatMap { id in people.first { $0.id == id } } }
    var currentDoc: Doc? { selectedDoc.flatMap { id in docs.first { $0.id == id } } }
    /// A vault row while the vault is shut: shown with a lock, values sealed.
    func isLocked(_ e: FillEntry) -> Bool { e.sensitive && !isUnlocked }

    // MARK: Load

    func load() {
        guard hasFullAccess else { status = "Full Access is off. Turn it on in Settings, then Keyboards"; return }
        do {
            let container = try AppFiles.makeContainer()
            let ctx = ModelContext(container)
            let persons = try ctx.fetch(FetchDescriptor<StoredPerson>())
            people = persons.map { Person(id: $0.id, name: $0.name, kind: $0.kind, fullName: $0.fullName, address: $0.address, phone: $0.phone, email: $0.email) }
                .sorted { a, b in rank(a.kind) == rank(b.kind) ? a.name < b.name : rank(a.kind) < rank(b.kind) }
            let order = Dictionary(uniqueKeysWithValues: people.enumerated().map { ($0.element.id, $0.offset) })
            let stored = try ctx.fetch(FetchDescriptor<StoredDocument>()).filter { $0.deletedAt == nil }
            docs = stored.map { d in
                let keyless = FillFormats.keys(for: d.type).isEmpty
                return Doc(id: d.id, title: d.title, type: d.type,
                           fields: Dictionary(d.fields.map { ($0.key, ($0.sealedValue, $0.value)) }, uniquingKeysWith: { a, _ in a }),
                           firstPageFile: d.pages.sorted { $0.index < $1.index }.first?.imageFileName,
                           favourite: d.favourite, sensitive: d.sensitive, personID: d.person?.id, capturedAt: d.capturedAt,
                           lines: keyless && !d.sensitive ? FillLines.lines(from: d.fullText) : [],
                           sealedText: keyless && d.sensitive ? d.sealedText : nil)
            }
            .sorted { a, b in
                let pa = a.personID.flatMap { order[$0] } ?? Int.max, pb = b.personID.flatMap { order[$0] } ?? Int.max
                return pa == pb ? FillFormats.order(a.type) < FillFormats.order(b.type) : pa < pb
            }
            entries = buildEntries()
            loadUsage()
            status = entries.isEmpty ? "Nothing here yet. Scan a document in DocuVault" : nil
            openingPanel()
        } catch {
            status = "Could not open the DocuVault store"
        }
    }

    private func rank(_ k: PersonKind) -> Int { switch k { case .me: 0; case .family: 1; case .partner: 2; case .client: 3; case .other: 4 } }

    private func buildEntries() -> [FillEntry] {
        var out: [FillEntry] = []
        for d in docs {
            let p = d.personID.flatMap { id in people.first { $0.id == id } }
            let plain = d.fields.compactMapValues { $0.value == nil ? $0.plain : nil }
            out.append(FillEntry(title: FillPicker.entryTitle(stored: d.title, type: d.type), personName: p?.name ?? "",
                                 personID: p?.id, kind: .document(d.id), sensitive: d.sensitive,
                                 detail: p == nil ? FillPicker.detail(type: d.type, fields: plain, addedAt: d.capturedAt) : nil,
                                 addedAt: d.capturedAt, type: d.type, favourite: d.favourite))
        }
        for p in people {
            out.append(FillEntry(title: "Contact details", personName: p.name, personID: p.id, kind: .shared))
        }
        return out
    }

    /// Where the keyboard opens: inside the lock window, on the keys you left (checkpoint 13c Q2); otherwise
    /// on the tab chosen in the app's Settings (checkpoint 20). Never on a Face ID screen.
    private func openingPanel() {
        if let id = KeyboardVault.lastEntryID, let e = entries.first(where: { $0.id == id }), !isLocked(e) {
            selectedID = id
            panel = .keys
            return
        }
        panel = .home
        switch startPageMode {
        case .recents: menuTab = .recents
        case .favourites: menuTab = favouriteEntries.isEmpty ? .recents : .favourites
        case .last:
            menuTab = .recents
            if let e = recentEntries.first(where: { lastUsed[$0.id] != nil }), !isLocked(e) { selectedID = e.id; panel = .keys }
        }
    }

    private var startPageMode: AppFiles.KeyboardStartPage {
        sharedDefaults?.string(forKey: AppFiles.keyboardStartPageKey).flatMap(AppFiles.KeyboardStartPage.init(stored:)) ?? .recents
    }

    // MARK: Rows

    /// Recents: last touched first, the later of capture and last fill (checkpoint 20 Q3).
    var recentEntries: [FillEntry] { FillPicker.recents(entries, lastUsed: lastUsed) }
    var favouriteEntries: [FillEntry] { recentEntries.filter(\.favourite) }
    var groups: [FillPicker.Group] { FillPicker.groups(recentEntries) }

    /// The People and Documents tabs, narrowed by the row tapped.
    var personEntries: [FillEntry] { FillPicker.filter(recentEntries, person: personFilter) }
    var groupEntries: [FillEntry] { groups.first { $0.name == groupFilter }?.entries ?? [] }
    func rowCount(for person: Person) -> Int { entries.filter { $0.personID == person.id }.count }

    /// Inside the vault: categories, then the people who have vault documents.
    var vaultEntries: [FillEntry] { recentEntries.filter(\.sensitive) }
    var vaultGroups: [FillPicker.Group] { FillPicker.groups(vaultEntries) }
    var vaultPeople: [Person] { people.filter { p in vaultEntries.contains { $0.personID == p.id } } }
    var vaultFilteredEntries: [FillEntry] {
        switch vaultFilter {
        case .group(let name): vaultGroups.first { $0.name == name }?.entries ?? []
        case .person(let id): vaultEntries.filter { $0.personID == id }
        case nil: []
        }
    }

    /// Ranked by word starts, with the letters to highlight. Covers the vault too; a locked row asks for
    /// Face ID once when picked (Evan, 14 Oct).
    var searchMatches: [FillPicker.Match] { FillPicker.search(recentEntries, query: searchText) }
    var searchResults: [FillEntry] { searchMatches.map(\.entry) }

    // MARK: Field hints (checkpoint 20 Q4)

    var fieldHint: FillInference.FieldHint? { FillInference.hint(contentType: fieldContext.contentType) }

    /// The one row the suggestion row offers for the field's hint: the person you last filled for, else you.
    var suggestion: FillEntry? {
        guard let h = fieldHint else { return nil }
        let rows = recentEntries
        let pid = currentEntry?.personID ?? people.first { $0.kind == .me }?.id ?? people.first?.id
        switch h.target {
        case .contact: return rows.first { $0.kind == .shared && $0.personID == pid }
        case .businessCard: return rows.first { $0.type == .businessCard }
        case .bankCard: return rows.first { $0.type == .bankCard && $0.personID == pid } ?? rows.first { $0.type == .bankCard }
        case .passport: return rows.first { $0.type == .passport && $0.personID == pid } ?? rows.first { $0.type == .passport }
        }
    }

    /// The key the field asks for gets a ring; nothing moves.
    func isHinted(_ spec: FillFormats.KeySpec) -> Bool { fieldHint?.keys.contains(spec.fieldKey) ?? false }

    // MARK: Selecting

    /// Loads a row. A vault row while the vault is shut asks for Face ID once, then opens; the lock window
    /// from the app's Settings applies after that.
    func select(_ e: FillEntry) {
        if isLocked(e) {
            Task { await unlock(); if isUnlocked { select(e) } }
            return
        }
        selectedID = e.id
        KeyboardVault.lastEntryID = e.id
        searchText = ""
        panel = .keys
        markCurrentUsed(count: true)
    }

    // MARK: Panels

    func openSearch() { searchText = ""; panel = .search }

    /// The menu circle: home, the four tabs. From home with a row loaded, back to its keys.
    func toggleHome() {
        if panel == .home, personFilter == nil, groupFilter == nil, currentEntry != nil { panel = .keys; return }
        personFilter = nil; groupFilter = nil; searchText = ""
        panel = .home
    }

    func showTab(_ tab: MenuTab) { menuTab = tab; personFilter = nil; groupFilter = nil }

    /// The vault door: Face ID once if shut, then the vault's own folders. Tapping it inside the vault goes back.
    func openVault() {
        if panel == .vault { panel = .home; vaultFilter = nil; return }
        if isUnlocked { vaultFilter = nil; panel = .vault; return }
        Task {
            await unlock()
            if isUnlocked { vaultFilter = nil; panel = .vault }
        }
    }

    func toggleScan() {
        guard currentDoc?.firstPageFile != nil else { return }
        panel == .scan ? back() : (panel = .scan)
    }

    /// Back: out of a filter first, then to the keys when a row is loaded, else home.
    func back() {
        searchText = ""
        switch panel {
        case .home: personFilter = nil; groupFilter = nil
        case .vault: if vaultFilter != nil { vaultFilter = nil } else { panel = .home }
        case .keys: panel = .home
        case .search, .scan: panel = currentEntry != nil ? .keys : .home
        }
    }

    var showsBack: Bool {
        switch panel {
        case .search, .scan, .vault: true
        case .home: personFilter != nil || groupFilter != nil
        case .keys: false
        }
    }

    func typeSearch(_ letter: String) { searchText += letter }
    func backspaceSearch() { if !searchText.isEmpty { searchText.removeLast() } }
    /// The best match while typing; the pad's Open key loads it, like Search on Apple's keyboard.
    var topMatch: FillEntry? { searchText.isEmpty ? nil : searchResults.first }
    func openTopMatch() { if let e = topMatch { select(e) } }

    func setDateStyle(_ style: FillFormats.DateStyle?) { dateOverride = style; KeyboardVault.touch() }

    // MARK: Text lines (checkpoint 20 Q6)

    /// A keyless document's text lines. Vault ones open with the key and are never kept.
    var currentLines: [String] {
        guard let d = currentDoc, FillFormats.keys(for: d.type).isEmpty else { return [] }
        if let sealed = d.sealedText {
            guard let key, let text = try? VaultCrypto.openString(sealed, key: key) else { return [] }
            return FillLines.lines(from: text)
        }
        return d.lines
    }

    func insertLine(_ text: String) { commit(text) }

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
        guard let id = selectedID else { return }
        lastUsed[id] = Date()
        if count { useCounts[id, default: 0] += 1 }
        sharedDefaults?.set(lastUsed.mapValues(\.timeIntervalSince1970), forKey: Self.lastUsedDefaultsKey)
        sharedDefaults?.set(useCounts, forKey: Self.useCountsDefaultsKey)
    }

    private func prefKey(_ spec: FillFormats.KeySpec) -> String? {
        selectedID.map { $0 + "|" + spec.fieldKey }
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
            } else { status = "No vault key yet. Open DocuVault and unlock the Vault once" }
        } catch let e as VaultError {
            status = VaultSession.describe(e)
        } catch {
            status = error.localizedDescription
        }
    }

    /// Seals the vault. Regular rows stay open; a loaded vault row goes back home.
    func lock() {
        key = nil
        KeyboardVault.wipe()
        vaultFilter = nil
        if currentEntry?.sensitive == true { selectedID = nil }
        if panel == .vault || ((panel == .keys || panel == .scan) && selectedID == nil) { panel = .home }
    }

    /// The keyboard is about to show: seal the vault if the lock window has passed while it was hidden.
    func willAppear() {
        KeyboardVault.expireIfStale()
        if KeyboardVault.key == nil, key != nil { lock() }
    }

    /// The keyboard hid, usually because you switched apps. The lock window starts now; with
    /// "Immediately" chosen in Settings it locks on the spot, as it always did before.
    func didDisappear() {
        KeyboardVault.touch()
        if KeyboardVault.window == 0 { lock() }
    }

    // MARK: Values

    func value(for spec: FillFormats.KeySpec) -> String? {
        if isSharedSelected {
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
        if isSharedSelected { return value(for: spec) != nil }
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
