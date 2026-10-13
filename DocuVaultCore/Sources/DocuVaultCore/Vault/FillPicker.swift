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
            let title = units(e.title), person = units(e.personName)
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
