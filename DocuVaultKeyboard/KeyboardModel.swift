import Foundation
import SwiftData
import CryptoKit
import DocuVaultCore

/// The unlocked key, held for the keyboard's whole process rather than by one controller. iOS builds a
/// new controller each time the keyboard appears, so an instance property locked on every app switch.
/// The key now survives that inside the lock window (Evan, checkpoint 14: 1 min by default). Memory only:
/// a restart or iOS closing the keyboard drops it.
@MainActor enum KeyboardVault {
    static var key: SymmetricKey?
    static var lastActivity = Date()

    /// Seconds the keyboard stays unlocked after the last key. 0 = lock as soon as it hides.
    /// Written by the app's Settings into the App Group.
    static var window: TimeInterval {
        guard let d = UserDefaults(suiteName: AppFiles.appGroupID), d.object(forKey: AppFiles.keyboardLockWindowKey) != nil
        else { return AppFiles.keyboardLockWindowDefault }
        return max(0, d.double(forKey: AppFiles.keyboardLockWindowKey))
    }

    static func touch() { lastActivity = Date() }
    static func wipe() { key = nil }
    static func expireIfStale(now: Date = Date()) {
        if key != nil, now.timeIntervalSince(lastActivity) > window { key = nil }
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
        let checksOK: Bool
        static func == (a: Doc, b: Doc) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
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

    /// Picker: one flat list of every document and every person's shared fields.
    var isPickerOpen = false
    var searchText = ""
    var personFilter: UUID?          // nil = every person
    private var lastUsed: [String: Date] = [:]
    private static let lastUsedDefaultsKey = "keyboard.lastUsed"

    /// What the host text field tells us; refreshed on every textDidChange.
    var fieldContext = FillInference.Context(region: Locale.current.region?.identifier ?? "SG")
    /// Explicit picks from a hold override inference for the rest of this keyboard session.
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

    // MARK: Load

    func load() {
        guard hasFullAccess else { status = "Full Access is off — enable it in Settings → Keyboards"; return }
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
                                    checksOK: d.allChecksPassed) }
            }
            docsByPerson = map
            loadLastUsed()
            if let first = entries.first {
                select(first)
            } else {
                selectedPerson = people.first?.id
                selectedDoc = currentDocs.first?.id
            }
            status = people.isEmpty ? "No people in the vault yet — add one in DocuVault" : nil
        } catch {
            status = "Could not open the vault store"
        }
    }

    private func rank(_ k: PersonKind) -> Int { switch k { case .me: 0; case .family: 1; case .partner: 2; case .client: 3; case .other: 4 } }

    // MARK: Picker

    /// Every row the picker can show, most recently used first. Shared fields sit alongside the
    /// documents rather than forming a separate idea.
    var entries: [FillEntry] {
        var out: [FillEntry] = []
        for p in people {
            for d in docsByPerson[p.id] ?? [] {
                out.append(FillEntry(title: d.title, personName: p.name, personID: p.id, kind: .document(d.id)))
            }
            out.append(FillEntry(title: "Shared fields", personName: p.name, personID: p.id, kind: .shared))
        }
        return FillPicker.sorted(out, lastUsed: lastUsed)
    }

    var visibleEntries: [FillEntry] {
        FillPicker.filter(FillPicker.filter(entries, person: personFilter), query: searchText)
    }

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
        closePicker()
    }

    func openPicker() { searchText = ""; personFilter = nil; isPickerOpen = true }
    func closePicker() { searchText = ""; personFilter = nil; isPickerOpen = false }

    /// Remembered across launches in the App Group, so the row you filled from last is on top.
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: AppFiles.appGroupID) }

    private func loadLastUsed() {
        guard let raw = sharedDefaults?.dictionary(forKey: Self.lastUsedDefaultsKey) as? [String: Double] else { return }
        lastUsed = raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func markCurrentUsed() {
        guard let person = selectedPerson else { return }
        lastUsed[FillPicker.key(personID: person, kind: currentEntryKind)] = Date()
        sharedDefaults?.set(lastUsed.mapValues(\.timeIntervalSince1970), forKey: Self.lastUsedDefaultsKey)
    }

    // MARK: Unlock

    func unlock() async {
        status = nil
        do {
            let k = try await Task.detached(priority: .userInitiated) { try VaultKeychain.load(reason: "Fill from your DocuVault") }.value
            if let k { key = k; KeyboardVault.key = k; KeyboardVault.touch() } else { status = "No vault key yet — open DocuVault and unlock the Vault once" }
        } catch let e as VaultError {
            status = VaultSession.describe(e)
        } catch {
            status = error.localizedDescription
        }
    }

    func lock() { key = nil; KeyboardVault.wipe() }

    /// The keyboard is about to show: drop the key if the lock window has passed while it was hidden.
    func willAppear() {
        KeyboardVault.expireIfStale()
        if KeyboardVault.key == nil { key = nil }
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
            switch datePlan.value {
            case .full(let st): return st.rawValue
            case .component(let c): return "\(String(describing: c).capitalized) only"
            }
        case .expiry: return expiryChoice.value.rawValue
        case .holdOnly: return "Hold"
        case .text:
            if ["nationality", "issuingCountry", "sex"].contains(spec.fieldKey) { return value(for: spec) }
            return nil
        }
    }

    // MARK: Insert

    func insert(_ spec: FillFormats.KeySpec, alternate: Bool = false) {
        guard let raw = value(for: spec) else { return }
        let text: String
        switch spec.kind {
        case .cardNumber: text = FillFormats.cardNumber(raw, spaced: alternate || FillInference.cardSpaced(fieldContext))
        case .date:
            switch datePlan.value {
            case .full(let st): text = FillFormats.date(raw, style: st)
            case .component(let c): text = FillInference.component(c, of: raw)
            }
        case .expiry: text = FillFormats.expiry(raw, style: expiryChoice.value)
        case .holdOnly: guard alternate else { return }; text = raw
        case .text: text = raw
        }
        insertText(text)
        markCurrentUsed()
        KeyboardVault.touch()
    }

    func insertDate(_ spec: FillFormats.KeySpec, style: FillFormats.DateStyle) {
        guard let raw = value(for: spec) else { return }
        dateOverride = style
        insertText(FillFormats.date(raw, style: style))
        markCurrentUsed()
        KeyboardVault.touch()
    }

    func insertExpiry(_ spec: FillFormats.KeySpec, style: FillFormats.ExpiryStyle) {
        guard let raw = value(for: spec) else { return }
        expiryOverride = style
        insertText(FillFormats.expiry(raw, style: style))
        markCurrentUsed()
        KeyboardVault.touch()
    }

    func backspace() { deleteBack(); KeyboardVault.touch() }
    func space() { insertText(" "); KeyboardVault.touch() }
    func globe() { nextKeyboard() }
    func done() { dismissKeyboard() }
}
