import Foundation

/// Code-side redaction before any text leaves the phone (Phase 7).
/// Finds identifiers, contacts, names, amounts and dates; swaps them for stable placeholders
/// (`[NAME 1]`, `[AMOUNT 2 SGD]`); restores the placeholders in the reply.
/// Identifiers and contacts are always redacted. The other categories are per-send choices.
public enum Redactor {

    public enum Category: String, Codable, CaseIterable, Sendable, Hashable {
        case identifier, contact, name, amount, date

        public var placeholderWord: String {
            switch self {
            case .identifier: "ID"
            case .contact: "CONTACT"
            case .name: "NAME"
            case .amount: "AMOUNT"
            case .date: "DATE"
            }
        }
        /// Cannot be switched off on the approval sheet.
        public var isLocked: Bool { self == .identifier || self == .contact }
        public var displayName: String {
            switch self {
            case .identifier: "IDs and card numbers"
            case .contact: "Phones and emails"
            case .name: "Names"
            case .amount: "Amounts"
            case .date: "Dates"
            }
        }
    }

    /// One thing found in the text. `range` is UTF-16 (NSRange) into the source.
    public struct Span: Equatable, Sendable {
        public let category: Category
        public let location: Int
        public let length: Int
        public let original: String
        /// Normalised key: the same person or amount gets the same placeholder index.
        public let key: String
        /// Extra tag kept in the placeholder so the model can still reason: the currency for amounts.
        public let tag: String?
        public var range: NSRange { NSRange(location: location, length: length) }
    }

    public struct Options: Equatable, Sendable {
        public var names = true
        public var amounts = true
        public var dates = false
        public init(names: Bool = true, amounts: Bool = true, dates: Bool = false) {
            self.names = names; self.amounts = amounts; self.dates = dates
        }
        public func includes(_ c: Category) -> Bool {
            switch c {
            case .identifier, .contact: true
            case .name: names
            case .amount: amounts
            case .date: dates
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let applied: [Span]
        /// placeholder → original, for restoring the reply.
        public let map: [String: String]
        public var counts: [Category: Int] { Dictionary(grouping: applied, by: \.category).mapValues(\.count) }
        public var count: Int { applied.count }
    }

    // MARK: Find

    /// Every candidate span, non-overlapping, sorted by position. `extraNames` are known names
    /// (extracted fields, people in the vault) that must be redacted wherever they appear.
    public static func findSpans(in text: String, extraNames: [String] = []) -> [Span] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [Span] = []
        func take(_ c: Category, _ r: NSRange, key: String? = nil, tag: String? = nil) {
            guard r.location != NSNotFound, r.length > 0 else { return }
            if spans.contains(where: { NSIntersectionRange($0.range, r).length > 0 }) { return }
            let s = ns.substring(with: r)
            spans.append(Span(category: c, location: r.location, length: r.length, original: s, key: key ?? normalise(s), tag: tag))
        }
        func each(_ pattern: String, options: NSRegularExpression.Options = [], _ body: (NSTextCheckingResult) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for m in re.matches(in: text, range: full) { body(m) }
        }

        // 1. Identifiers: MRZ lines, PRC 身份证, NRIC/FIN, passport numbers after a label, card numbers (Luhn).
        each(#"(?m)^[A-Z0-9<]{30,44}$"#) { take(.identifier, $0.range) }
        each(#"(?<![\dA-Za-z])\d{17}[\dXx](?![\dA-Za-z])"#) { take(.identifier, $0.range) }
        each(#"(?<![A-Za-z0-9])[STFGMstfgm]\d{7}[A-Za-z](?![A-Za-z0-9])"#) { take(.identifier, $0.range) }
        each(#"(?:Passport\s*(?:No\.?|Number|#)?|护照号码?|护照编号|Document\s*No\.?|证件号码?)\s*[:：]?\s*([A-Z]{0,2}\d{6,9}[A-Z]?)"#, options: [.caseInsensitive]) { take(.identifier, $0.range(at: 1)) }
        each(#"(?<!\d)\d(?:[ \-]?\d){12,18}(?!\d)"#) { m in
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            guard (13...19).contains(digits.count), CardCheck.luhn(digits) else { return }
            take(.identifier, m.range, key: digits)
        }

        // 2. Contacts: emails, then phones (SG 8-digit, CN 11-digit, international with +).
        each(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#) { take(.contact, $0.range) }
        let phonePatterns = [
            #"\+\s?\d{1,3}[\s\-]?(?:\d[\s\-]?){7,12}\d"#,                 // +65 9123 4567 · +86 138 0000 0000
            #"(?<![\d\-.])1[3-9]\d{9}(?![\d\-.])"#,                        // China mobile
            #"(?<![\d\-.])\(?0\d{2,3}\)?[\s\-]?\d{7,8}(?![\d\-.])"#,     // China landline with area code
            #"(?<![\d\-.])[3689]\d{3}[\s\-]?\d{4}(?![\d\-.])"#,           // Singapore 8-digit
        ]
        for pat in phonePatterns { each(pat) { m in
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            guard digits.count >= 8 else { return }
            take(.contact, m.range, key: digits)
        } }

        // 3. Names. Known names first (longest first so "Evan Lai" wins over "Lai").
        for n in extraNames.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ $0.count >= 2 }).sorted(by: { $0.count > $1.count }) {
            var search = full
            while search.length > 0 {
                let r = ns.range(of: n, options: [.caseInsensitive], range: search)
                guard r.location != NSNotFound else { break }
                take(.name, r, key: normalise(n))
                let next = r.location + r.length
                search = NSRange(location: next, length: ns.length - next)
            }
        }
        // English: companies, salutations, "Dear X", labels.
        let cap = #"[A-Z](?:[A-Za-z'\-]+|\.)"#
        each(#"((?:(?:\#(cap)|&)\s+){1,4}(?:Pte\.?\s+Ltd\.?|Sdn\.?\s+Bhd\.?|Co\.?,?\s+Ltd\.?|Ltd\.?|LLP|LLC|Inc\.?|Limited|Corporation|Corp\.?|Holdings|Bhd|Partners|Associates))"#) { take(.name, $0.range(at: 1)) }
        each(#"\b(?:Mr|Mrs|Ms|Miss|Mdm|Madam|Dr|Prof|Messrs)\.?\s+(\#(cap)(?:\s+\#(cap)){0,3})"#) { take(.name, $0.range(at: 1)) }
        each(#"\bDear\s+(?!Sirs?\b|Madam\b|Team\b|All\b|Colleagues\b)(\#(cap)(?:\s+\#(cap)){0,3})"#) { take(.name, $0.range(at: 1)) }
        each(#"(?:Name|Attn|Attention|Signed by|Signatory|Director|Client|Borrower|Lender|Tenant|Landlord|Party [AB])\s*[:：]\s*(\#(cap)(?:\s+\#(cap)){0,4})"#) { take(.name, $0.range(at: 1)) }
        // Chinese: companies, role + name, name + honorific.
        let han = #"[\u4e00-\u9fff]"#
        each(#"((?:\#(han)|[A-Za-z0-9（）()·]){2,24}?(?:有限责任公司|股份有限公司|有限公司|律师事务所|会计师事务所|合伙企业|集团))"#) { m in
            var r = m.range(at: 1)
            let s = ns.substring(with: r)
            if let stripped = stripRolePrefix(s), stripped.count < s.count {
                let drop = (s as NSString).length - (stripped as NSString).length
                r = NSRange(location: r.location + drop, length: r.length - drop)
            }
            take(.name, r)
        }
        each(#"(?:\#(roleWordsPattern))\s*[:：（(]?\s*(\#(han){2,4})(?=先生|女士|小姐|经理|总|律师|会计师|[，,。、；;:：（）()\s]|$)"#, options: [.anchorsMatchLines]) { take(.name, $0.range(at: 1)) }
        each(#"(?<!\#(han))(\#(han){2,4})(?=先生|女士|小姐|经理|律师|会计师|总经理|董事长)"#) { take(.name, $0.range(at: 1)) }

        // 4. Amounts (currency kept in the placeholder) and 5. dates.
        for (r, money) in TextRules.moneySpans(in: text) {
            take(.amount, r, key: "\(money.currency)\(money.amount)", tag: money.currency)
        }
        for (r, iso) in TextRules.dateSpans(in: text) { take(.date, r, key: iso) }

        return spans.sorted { $0.location < $1.location }
    }

    static let roleWords = ["甲方", "乙方", "丙方", "丁方", "委托人", "受托人", "出租方", "承租方", "出租人", "承租人", "买方", "卖方",
                            "借款人", "贷款人", "担保人", "法定代表人", "代表人", "签字", "签名", "姓名", "联系人", "经办人", "负责人", "收件人", "致"]
    static var roleWordsPattern: String { roleWords.joined(separator: "|") }

    /// Connectors that glue a company name to the sentence before it: "本合同由西安某某有限公司".
    static let connectorWords = ["本合同由", "本协议由", "以下简称", "简称", "由", "与", "及", "和", "向", "为", "系"]

    /// "甲方西安某某有限公司" → "西安某某有限公司".
    static func stripRolePrefix(_ s: String) -> String? {
        var t = s
        var changed = true
        while changed {
            changed = false
            for w in roleWords + connectorWords where t.hasPrefix(w) && t.count - w.count >= 4 { t = String(t.dropFirst(w.count)); changed = true }
            while let f = t.first, "：:（()）、，, ".contains(f) { t = String(t.dropFirst()); changed = true }
        }
        return t.count >= 2 ? t : nil
    }

    // MARK: Apply / restore

    /// Replace the chosen spans with placeholders. Same key → same index within a category.
    public static func apply(_ text: String, spans: [Span], options: Options = Options()) -> Result {
        let chosen = spans.filter { options.includes($0.category) }.sorted { $0.location < $1.location }
        var index: [Category: [String: Int]] = [:]
        var map: [String: String] = [:]
        var applied: [Span] = []
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for s in chosen {
            guard s.location >= cursor else { continue }
            out += ns.substring(with: NSRange(location: cursor, length: s.location - cursor))
            var byKey = index[s.category, default: [:]]
            let n: Int
            if let existing = byKey[s.key] { n = existing } else { n = byKey.count + 1; byKey[s.key] = n }
            index[s.category] = byKey
            let placeholder = "[\(s.category.placeholderWord) \(n)\(s.tag.map { " " + $0 } ?? "")]"
            if map[placeholder] == nil { map[placeholder] = s.original }
            out += placeholder
            applied.append(s)
            cursor = s.location + s.length
        }
        out += ns.substring(from: cursor)
        return Result(text: out, applied: applied, map: map)
    }

    /// Put the originals back into a model reply. Unknown placeholders are left as-is and counted.
    public static func restore(_ reply: String, map: [String: String]) -> (text: String, unresolved: Int) {
        guard let re = try? NSRegularExpression(pattern: #"\[(ID|CONTACT|NAME|AMOUNT|DATE) (\d+)(?: [A-Z]{3})?\]"#) else { return (reply, 0) }
        let ns = reply as NSString
        var out = ""
        var cursor = 0
        var unresolved = 0
        // Lookup ignores the currency tag so "[AMOUNT 1]" and "[AMOUNT 1 SGD]" both resolve.
        var byBare: [String: String] = [:]
        for (k, v) in map {
            let parts = k.dropFirst().dropLast().split(separator: " ")
            if parts.count >= 2 { byBare["\(parts[0]) \(parts[1])"] = v }
        }
        for m in re.matches(in: reply, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let token = ns.substring(with: m.range)
            let bare = ns.substring(with: m.range(at: 1)) + " " + ns.substring(with: m.range(at: 2))
            if let v = map[token] ?? byBare[bare] { out += v } else { out += token; unresolved += 1 }
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return (out, unresolved)
    }

    /// Restore every string field of a summary.
    public static func restore(_ summary: DocumentSummary, map: [String: String]) -> (summary: DocumentSummary, unresolved: Int) {
        var s = summary
        var u = 0
        func fix(_ t: String) -> String { let r = restore(t, map: map); u += r.unresolved; return r.text }
        s.headline = fix(s.headline)
        s.body = s.body.map(fix)
        s.actions = s.actions.map(fix)
        s.keyFacts = s.keyFacts.map { DocumentSummary.Fact(label: fix($0.label), value: fix($0.value)) }
        return (s, u)
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "." && $0 != "," }
    }

    /// Instruction line for the model so it keeps placeholders intact.
    public static func placeholderRule(language: String) -> String {
        language == "zh-Hans"
            ? "文中的 [NAME 1]、[AMOUNT 2 SGD]、[ID 1] 等是已脱敏的占位符。需要引用时原样照抄，不要猜测其内容。"
            : "Tokens like [NAME 1], [AMOUNT 2 SGD] or [ID 1] are redacted placeholders. Copy them exactly when you refer to them. Never guess what they stand for."
    }
}
