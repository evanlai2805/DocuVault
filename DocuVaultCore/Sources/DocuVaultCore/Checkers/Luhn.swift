import Foundation

/// Payment card number validation (ISO/IEC 7812 Luhn) and brand detection.
public enum CardCheck {

    public enum Brand: String, Codable, Sendable {
        case visa = "Visa"
        case mastercard = "Mastercard"
        case amex = "American Express"
        case unionPay = "UnionPay"
        case jcb = "JCB"
        case discover = "Discover"
        case unknown = "Unknown"
    }

    public struct Result: Equatable, Sendable {
        public let digits: String       // digits only
        public let luhnOK: Bool
        public let brand: Brand
        public let last4: String
        public var masked: String {     // •••• •••• •••• 4417
            let groups = digits.count == 15 ? [4, 6, 5] : [4, 4, 4, 4]
            var out: [String] = []
            for (gi, g) in groups.enumerated() {
                let isLast = gi == groups.count - 1
                out.append(isLast ? last4 : String(repeating: "•", count: g))
            }
            return out.joined(separator: " ")
        }
    }

    /// Luhn mod-10 over a digit string.
    public static func luhn(_ digits: String) -> Bool {
        let ds = digits.compactMap { $0.wholeNumberValue }
        guard ds.count == digits.count, ds.count >= 12 else { return false }
        var sum = 0
        var double = false
        for d in ds.reversed() {
            var n = d
            if double { n *= 2; if n > 9 { n -= 9 } }
            sum += n
            double.toggle()
        }
        return sum % 10 == 0
    }

    /// Brand from leading digits. Order matters: UnionPay 62 before generic checks; Mastercard 2221–2720.
    public static func brand(_ digits: String) -> Brand {
        guard digits.count >= 4, let p4 = Int(digits.prefix(4)) else { return .unknown }
        let p2 = p4 / 100
        if digits.hasPrefix("62") { return .unionPay }
        if digits.hasPrefix("4") { return .visa }
        if (51...55).contains(p2) || (2221...2720).contains(p4) { return .mastercard }
        if p2 == 34 || p2 == 37 { return .amex }
        if (3528...3589).contains(p4) { return .jcb }
        if digits.hasPrefix("6011") || p2 == 65 || (644...649).contains(p4 / 10) { return .discover }
        return .unknown
    }

    /// Validate a raw OCR string. Strips spaces and dashes. Returns nil if no 13–19 digit run is present.
    public static func validate(_ raw: String) -> Result? {
        let digits = raw.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return nil }
        return Result(digits: digits, luhnOK: luhn(digits), brand: brand(digits), last4: String(digits.suffix(4)))
    }

    /// Scan OCR lines for the first card-number-looking run (groups of digits, 13–19 total).
    public static func findCardNumber(in ocrLines: [String]) -> Result? {
        let pattern = #"(?:\d[ \-]?){12,18}\d"#
        for line in ocrLines {
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            if let r = validate(String(line[range])), r.luhnOK { return r }
        }
        // Second pass: accept a Luhn-failing run so the user can correct it.
        for line in ocrLines {
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            if let r = validate(String(line[range])) { return r }
        }
        return nil
    }

    /// Card expiry "MM/YY" or "MM/YYYY" or "MM-YY". Returns (month, fullYear) or nil.
    public static func parseExpiry(_ raw: String) -> (month: Int, year: Int)? {
        let pattern = #"(0[1-9]|1[0-2])\s*[/\-]\s*(\d{2}|\d{4})"#
        guard let r = raw.range(of: pattern, options: .regularExpression) else { return nil }
        let m = String(raw[r])
        let parts = m.components(separatedBy: CharacterSet(charactersIn: "/-")).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let mm = Int(parts[0]), var yy = Int(parts[1]) else { return nil }
        if yy < 100 { yy += 2000 }
        return (mm, yy)
    }

    /// True if the expiry month/year is the current month or later.
    public static func expiryIsCurrentOrFuture(month: Int, year: Int, now: Date = Date()) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
        return year > y || (year == y && month >= m)
    }
}
