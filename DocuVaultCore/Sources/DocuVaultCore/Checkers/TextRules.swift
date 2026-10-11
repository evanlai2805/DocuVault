import Foundation

/// Small rule-layer helpers shared by extractors: language detection, date parsing, money parsing.
public enum TextRules {

    // MARK: Language

    public enum Language: String, Sendable { case english = "en", chineseSimplified = "zh-Hans", mixed }

    /// Share of CJK characters among letters. ≥ 0.60 → Chinese, ≤ 0.10 → English, else mixed (ask user).
    public static func cjkRatio(_ text: String) -> Double {
        var cjk = 0, letters = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x3000...0x303F).contains(v)
            let isLatin = CharacterSet.letters.contains(scalar) && !isCJK
            if isCJK { cjk += 1; letters += 1 } else if isLatin { letters += 1 }
        }
        return letters == 0 ? 0 : Double(cjk) / Double(letters)
    }

    public static func detectLanguage(_ text: String) -> Language {
        let r = cjkRatio(text)
        if r >= 0.60 { return .chineseSimplified }
        if r <= 0.10 { return .english }
        return .mixed
    }

    // MARK: Dates

    static let monthNames: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "SEPT": 9, "OCT": 10, "NOV": 11, "DEC": 12,
        "JANUARY": 1, "FEBRUARY": 2, "MARCH": 3, "APRIL": 4, "JUNE": 6, "JULY": 7,
        "AUGUST": 8, "SEPTEMBER": 9, "OCTOBER": 10, "NOVEMBER": 11, "DECEMBER": 12
    ]

    /// Parse the first date in `text` to ISO yyyy-MM-dd. Handles:
    ///   12 APR 1999 · 12-04-1999 · 12/04/1999 · 1999-04-12 · 2026年10月10日 · 2026.10.10 · October 10, 2026
    /// Day-first is assumed for numeric dd-mm-yyyy (Singapore / China convention).
    public static func firstISODate(in text: String) -> String? {
        allISODates(in: text).first
    }

    /// Every date in `text`, in order of appearance, de-duplicated by position.
    public static func allISODates(in text: String) -> [String] {
        typealias Build = (NSTextCheckingResult, NSString) -> (Int, Int, Int)?
        let patterns: [(String, Build)] = [
            (#"(\d{4})年(\d{1,2})月(\d{1,2})日"#, { m, s in (Int(s.substring(with: m.range(at: 1)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 3)))!) }),
            (#"\b(\d{4})[\-./](\d{1,2})[\-./](\d{1,2})\b"#, { m, s in (Int(s.substring(with: m.range(at: 1)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 3)))!) }),
            (#"\b(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})\b"#, { m, s in
                guard let mo = monthNames[s.substring(with: m.range(at: 2)).uppercased()] else { return nil }
                return (Int(s.substring(with: m.range(at: 3)))!, mo, Int(s.substring(with: m.range(at: 1)))!) }),
            (#"\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, { m, s in
                guard let mo = monthNames[s.substring(with: m.range(at: 1)).uppercased()] else { return nil }
                return (Int(s.substring(with: m.range(at: 3)))!, mo, Int(s.substring(with: m.range(at: 2)))!) }),
            (#"\b(\d{1,2})[\-./](\d{1,2})[\-./](\d{4})\b"#, { m, s in (Int(s.substring(with: m.range(at: 3)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 1)))!) }),
        ]
        let ns = text as NSString
        var found: [(Int, String)] = []
        var taken: [NSRange] = []
        for (pat, build) in patterns {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                guard let (y, mo, d) = build(m, ns), (1...12).contains(mo), (1...31).contains(d), y >= 1900, y <= 2100 else { continue }
                taken.append(m.range)
                found.append((m.range.location, String(format: "%04d-%02d-%02d", y, mo, d)))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Money

    public struct Money: Equatable, Sendable {
        public let currency: String   // ISO-ish: SGD, CNY, USD, MYR, HKD
        public let amount: Decimal
    }

    /// Find money amounts. Recognises S$, SGD, $, RMB, ¥, ￥, 人民币, 元, CNY, USD, US$, MYR, RM, HKD, HK$.
    public static func findMoney(in text: String) -> [Money] {
        let pattern = #"(S\$|SGD|US\$|USD|HK\$|HKD|RM|MYR|CNY|RMB|人民币|¥|￥|\$)\s*([\d,]+(?:\.\d{1,2})?)|([\d,]+(?:\.\d{1,2})?)\s*(元|SGD|CNY|USD|MYR|HKD)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [Money] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let sym: String, num: String
            if m.range(at: 1).location != NSNotFound {
                sym = ns.substring(with: m.range(at: 1)); num = ns.substring(with: m.range(at: 2))
            } else {
                num = ns.substring(with: m.range(at: 3)); sym = ns.substring(with: m.range(at: 4))
            }
            guard let amt = Decimal(string: num.replacingOccurrences(of: ",", with: "")) else { continue }
            out.append(Money(currency: currencyCode(sym), amount: amt))
        }
        return out
    }

    static func currencyCode(_ sym: String) -> String {
        switch sym.uppercased() {
        case "S$", "SGD": return "SGD"
        case "US$", "USD": return "USD"
        case "HK$", "HKD": return "HKD"
        case "RM", "MYR": return "MYR"
        case "CNY", "RMB", "人民币", "¥", "￥", "元": return "CNY"
        case "$": return "SGD"   // default for a bare $ in Singapore context; user can override
        default: return sym
        }
    }
}
