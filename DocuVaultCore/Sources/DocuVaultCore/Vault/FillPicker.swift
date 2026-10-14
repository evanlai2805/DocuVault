import Foundation

/// One row in the keyboard's picker: a document, or a person's contact details.
/// The keyboard builds the rows; ordering and search live here so they can be tested without a UI.
/// Since checkpoint 20 every document is a row, not only vault ones; a row may have no person.
public struct FillEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case document(UUID)
        case shared
    }

    public let id: String
    public let title: String        // "Passport · CHAI", "Contact details", "Starbucks"
    public let personName: String   // "" when the document has no person
    public let personID: UUID?
    public let kind: Kind
    /// A vault document: its values open only after Face ID.
    public let sensitive: Bool
    /// Shown on the right in grey when there is no person: a receipt's date, a card's company.
    public let detail: String?
    /// When the document was captured; with the last fill it decides the Recents order.
    public let addedAt: Date?
    public let type: DocumentType?
    public let favourite: Bool

    public init(title: String, personName: String, personID: UUID?, kind: Kind, sensitive: Bool = false,
                detail: String? = nil, addedAt: Date? = nil, type: DocumentType? = nil, favourite: Bool = false) {
        self.id = FillPicker.key(personID: personID, kind: kind)
        self.title = title
        self.personName = personName
        self.personID = personID
        self.kind = kind
        self.sensitive = sensitive
        self.detail = detail
        self.addedAt = addedAt
        self.type = type
        self.favourite = favourite
    }

    /// The right side of the row: the person when there is one, else the detail, else nothing.
    public var trailing: String? { personName.isEmpty ? detail : personName }
}

public enum FillPicker {

    /// Stable key for remembering when a row was last filled from. Survives relaunches; a document
    /// keeps its key for life, so renaming the document does not lose its place in the order.
    public static func key(personID: UUID?, kind: FillEntry.Kind) -> String {
        switch kind {
        case .document(let id): "doc:\(id.uuidString)"
        case .shared: "shared:\(personID?.uuidString ?? "none")"
        }
    }

    /// Recents (checkpoint 20): last touched first, meaning the later of capture and last fill. A receipt
    /// scanned a minute ago and a passport filled yesterday both sit near the top. Rows never touched
    /// (contact details nobody has filled from) go last, in incoming order.
    public static func recents(_ entries: [FillEntry], lastUsed: [String: Date]) -> [FillEntry] {
        func touched(_ e: FillEntry) -> Date? {
            switch (e.addedAt, lastUsed[e.id]) {
            case let (a?, u?): max(a, u)
            case let (a?, nil): a
            case let (nil, u?): u
            case (nil, nil): nil
            }
        }
        return entries.enumerated()
            .sorted { a, b in
                switch (touched(a.element), touched(b.element)) {
                case let (x?, y?): return x == y ? a.offset < b.offset : x > y
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.offset < b.offset
                }
            }
            .map(\.element)
    }

    /// One group on the Documents tab.
    public struct Group: Equatable, Sendable, Identifiable {
        public let name: String
        public let entries: [FillEntry]
        public var id: String { name }
    }

    /// The Documents tab groups rows by type, in the app's category order; empty groups are left out.
    /// Contact details come first: every person has them.
    public static func groups(_ entries: [FillEntry]) -> [Group] {
        let order: [(String, (FillEntry) -> Bool)] = [
            ("Contact details", { $0.kind == .shared }),
            ("Passports", { $0.type == .passport }),
            ("ID cards", { $0.type == .nric || $0.type == .chinaID }),
            ("Bank cards", { $0.type == .bankCard }),
            ("Receipts", { $0.type == .receipt }),
            ("Business cards", { $0.type == .businessCard }),
            ("Contracts", { $0.type == .contract }),
            ("Letters", { $0.type == .letter }),
            ("Notes and other", { $0.kind != .shared && ($0.type == .other || $0.type == nil) }),
        ]
        return order.compactMap { name, test in
            let rows = entries.filter(test)
            return rows.isEmpty ? nil : Group(name: name, entries: rows)
        }
    }

    /// The grey right-side detail for a row with no person (Evan, 14 Oct): a receipt's capture date, a
    /// business card's company, a contract's or letter's other party. Nil leaves the side blank.
    public static func detail(type: DocumentType, fields: [String: String], addedAt: Date, now: Date = Date()) -> String? {
        func f(_ k: String) -> String? { fields[k].flatMap { $0.isEmpty ? nil : $0 } }
        switch type {
        case .receipt: return shortDate(addedAt, now: now)
        case .businessCard: return f("company")
        case .contract, .letter: return f("partyB") ?? f("partyA")
        default: return nil
        }
    }

    /// "14/OCT" this year, "14/OCT/2025" otherwise: the app's 12/MAR/1990 form, shortened when the year is plain.
    public static func shortDate(_ date: Date, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let d = cal.dateComponents([.day, .month, .year], from: date)
        let year = cal.component(.year, from: now)
        let base = String(format: "%02d/%@", d.day ?? 1, months[(d.month ?? 1) - 1])
        return d.year == year ? base : base + "/\(d.year ?? year)"
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

    /// The rows that match, best first. A thin wrapper over `search`, kept for the menu and the tests.
    public static func filter(_ entries: [FillEntry], query: String) -> [FillEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return search(entries, query: q).map(\.entry)
    }

    /// One search result, with the letters to highlight as character offsets into the title and the
    /// person's name.
    public struct Match: Equatable, Sendable {
        public let entry: FillEntry
        public let titleHighlight: [Range<Int>]
        public let personHighlight: [Range<Int>]
    }

    /// Search as the keyboard types (Evan, 13 Oct: "g" found Ben Ong). Each word of the query must match
    /// the start of a word in the title or the person's name; "pass ce" finds Passport · Celine Chai.
    /// Chinese matches by pinyin from any character, so "shen" and "fenz" both find 身份证. From three
    /// letters on, a match inside a word also counts, ranked after the word starts.
    /// Order: rows whose title starts with the query, then whose name starts with it, then the rest;
    /// ties keep the incoming order, which is most recently used first.
    public static func search(_ entries: [FillEntry], query: String) -> [Match] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map { romanised(String($0)) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var scored: [(rank: Int, offset: Int, match: Match)] = []
        for (offset, e) in entries.enumerated() {
            let title = units(e.title), person = units(secondary(e))
            var th: [Range<Int>] = [], ph: [Range<Int>] = []
            var inner = false
            var lead = 2
            var ok = true
            for (n, t) in tokens.enumerated() {
                if let r = find(t, in: title, wordStartOnly: true) {
                    th.append(r); if n == 0, r.lowerBound == 0 { lead = 0 }
                } else if let r = find(t, in: person, wordStartOnly: true) {
                    ph.append(r); if n == 0, r.lowerBound == 0 { lead = 1 }
                } else if t.count >= 3, let r = find(t, in: title, wordStartOnly: false) {
                    th.append(r); inner = true
                } else if t.count >= 3, let r = find(t, in: person, wordStartOnly: false) {
                    ph.append(r); inner = true
                } else { ok = false; break }
            }
            guard ok else { continue }
            scored.append(((inner ? 3 : 0) + lead, offset, Match(entry: e, titleHighlight: th, personHighlight: ph)))
        }
        return scored.sorted { $0.rank == $1.rank ? $0.offset < $1.offset : $0.rank < $1.rank }.map(\.match)
    }

    /// One character of a title or name, romanised, and whether a word starts there. Every Chinese
    /// character starts a word, so pinyin can match from any of them.
    private struct Unit { let roman: String; let wordStart: Bool }

    private static func units(_ s: String) -> [Unit] {
        var out: [Unit] = []
        var afterSeparator = true
        for ch in s {
            let roman = String(Pinyin.syllable(for: ch).filter { $0.isLetter || $0.isNumber }).uppercased()
            let chinese = ch.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            out.append(Unit(roman: roman, wordStart: !roman.isEmpty && (afterSeparator || chinese)))
            afterSeparator = roman.isEmpty
        }
        return out
    }

    /// The first place the token matches, as a character range. A token may end part way through a
    /// pinyin syllable ("she" covers 身).
    private static func find(_ token: String, in u: [Unit], wordStartOnly: Bool) -> Range<Int>? {
        for i in u.indices where wordStartOnly ? u[i].wordStart : !u[i].roman.isEmpty {
            var rest = Substring(token)
            var j = i
            while !rest.isEmpty, j < u.count, !u[j].roman.isEmpty {
                let r = u[j].roman
                if rest.hasPrefix(r) { rest = rest.dropFirst(r.count) }
                else if r.hasPrefix(rest) { rest = "" }
                else { break }
                j += 1
            }
            if rest.isEmpty { return i..<j }
        }
        return nil
    }

    /// The keyboard names identity documents by their type (Evan, 13 Oct: a passport showed as
    /// "REPUBLIC OF SINGAPORE"). A stored title that already names the type, such as "Passport · CHAI",
    /// is kept; any other title on a passport, NRIC or China ID gives way to the type's name.
    public static func entryTitle(stored: String, type: DocumentType) -> String {
        let words: [String] = switch type {
        case .passport: ["passport", "护照"]
        case .nric: ["nric", "fin", "identity card"]
        case .chinaID: ["id card", "身份证", "china id"]
        default: []
        }
        guard !words.isEmpty else { return stored }
        let lower = stored.lowercased()
        return words.contains { lower.contains($0) } ? stored : type.displayName
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

    /// Searchable text beyond title and person: a row with no person is found by its detail too,
    /// so "harbour" finds Daniel Koh's card. Used by `search`.
    static func secondary(_ e: FillEntry) -> String { e.personName.isEmpty ? (e.detail ?? "") : e.personName }

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
