import Foundation

/// One row in the keyboard's picker: a vault document, or a person's shared fields.
/// The keyboard builds the rows; ordering and search live here so they can be tested without a UI.
public struct FillEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case document(UUID)
        case shared
    }

    public let id: String
    public let title: String        // "Passport · CHAI", "Contact details"
    public let personName: String
    public let personID: UUID
    public let kind: Kind

    public init(title: String, personName: String, personID: UUID, kind: Kind) {
        self.id = FillPicker.key(personID: personID, kind: kind)
        self.title = title
        self.personName = personName
        self.personID = personID
        self.kind = kind
    }
}

public enum FillPicker {

    /// Stable key for remembering when a row was last filled from. Survives relaunches; a document
    /// keeps its key for life, so renaming the document does not lose its place in the order.
    public static func key(personID: UUID, kind: FillEntry.Kind) -> String {
        switch kind {
        case .document(let id): "doc:\(id.uuidString)"
        case .shared: "shared:\(personID.uuidString)"
        }
    }

    /// Most recently used first. Rows never used keep the order they arrived in, so the caller's
    /// own ranking (owner first, then card, passport, NRIC, ID) still decides the tail.
    public static func sorted(_ entries: [FillEntry], lastUsed: [String: Date]) -> [FillEntry] {
        entries.enumerated()
            .sorted { a, b in
                let da = lastUsed[a.element.id], db = lastUsed[b.element.id]
                switch (da, db) {
                case let (x?, y?): return x == y ? a.offset < b.offset : x > y
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.offset < b.offset
                }
            }
            .map(\.element)
    }

    /// Matches the query against the title and the person. Chinese is also matched by its pinyin,
    /// so "shen" finds 身份证 and "zu" finds 租赁合同 on a keyboard with no Chinese input.
    public static func filter(_ entries: [FillEntry], query: String) -> [FillEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        let roman = romanised(q)
        return entries.filter { e in
            if e.title.localizedStandardContains(q) || e.personName.localizedStandardContains(q) { return true }
            guard !roman.isEmpty else { return false }
            return romanised(e.title).contains(roman) || romanised(e.personName).contains(roman)
        }
    }

    /// The keyboard's start page (checkpoint 13c): the two most-used rows, then the two most recent,
    /// with no repeats. A row that is in both lists appears once, under Most used, and the next most
    /// recent row takes its place. With nothing used yet, Recent falls back to the incoming order so
    /// the page is never blank. Counts and dates are keyed by `key(personID:kind:)`.
    public struct StartPage: Equatable, Sendable {
        public let mostUsed: [FillEntry]
        public let recent: [FillEntry]
        public init(mostUsed: [FillEntry], recent: [FillEntry]) { self.mostUsed = mostUsed; self.recent = recent }
    }

    public static func startPage(_ entries: [FillEntry], useCounts: [String: Int], lastUsed: [String: Date], each: Int = 2) -> StartPage {
        let used = entries.enumerated()
            .filter { (useCounts[$0.element.id] ?? 0) > 0 }
            .sorted { a, b in
                let ca = useCounts[a.element.id] ?? 0, cb = useCounts[b.element.id] ?? 0
                return ca == cb ? a.offset < b.offset : ca > cb
            }
            .map(\.element)
        let mostUsed = Array(used.prefix(each))
        let taken = Set(mostUsed.map(\.id))
        let recent = sorted(entries, lastUsed: lastUsed).filter { !taken.contains($0.id) }
        return StartPage(mostUsed: mostUsed, recent: Array(recent.prefix(each)))
    }

    /// Narrows the list to one person. `nil` means everyone.
    public static func filter(_ entries: [FillEntry], person: UUID?) -> [FillEntry] {
        guard let person else { return entries }
        return entries.filter { $0.personID == person }
    }

    /// Romanised, upper-cased form used for matching only: "身份证" becomes "SHENFENZHENG".
    /// Latin text passes through upper-cased with spaces and punctuation dropped.
    public static func romanised(_ s: String) -> String {
        var out = ""
        for ch in s {
            let syl = Pinyin.syllable(for: ch)
            out += syl.filter { $0.isLetter || $0.isNumber }
        }
        return out.uppercased()
    }
}
