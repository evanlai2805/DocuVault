import Foundation

/// PRC Resident Identity Card number (公民身份号码), GB 11643-1999.
/// 18 characters: 6 region + 8 birth date (YYYYMMDD) + 3 sequence + 1 check (0-9 or X).
/// Check: ISO 7064 MOD 11-2 with weights 7 9 10 5 8 4 2 1 6 3 7 9 10 5 8 4 2 and map "10X98765432".
public enum ChinaID {

    public struct Result: Equatable, Sendable {
        public let value: String
        public let checksumOK: Bool
        public let expectedCheck: Character
        public let regionCode: String          // first 6 digits
        public let dateOfBirthISO: String      // yyyy-MM-dd
        public let dateOfBirthValid: Bool
        public let sex: Sex
    }

    public enum Sex: String, Sendable {
        case male = "M", female = "F"
        public var zh: String { self == .male ? "男" : "女" }
    }

    static let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    static let checkMap: [Character] = Array("10X98765432")

    public static func expectedCheck(first17: String) -> Character? {
        guard first17.count == 17 else { return nil }
        var sum = 0
        for (i, c) in first17.enumerated() {
            guard let d = c.wholeNumberValue else { return nil }
            sum += d * weights[i]
        }
        return checkMap[sum % 11]
    }

    /// Validate an 18-character ID. Accepts lowercase x. Ignores spaces.
    public static func validate(_ raw: String) -> Result? {
        let s = raw.uppercased().filter { !$0.isWhitespace }
        guard s.count == 18 else { return nil }
        let first17 = String(s.prefix(17))
        guard let expected = expectedCheck(first17: first17), let last = s.last else { return nil }

        let a = Array(s)
        let region = String(a[0..<6])
        let y = String(a[6..<10]), m = String(a[10..<12]), d = String(a[12..<14])
        let iso = "\(y)-\(m)-\(d)"
        var comps = DateComponents()
        comps.year = Int(y); comps.month = Int(m); comps.day = Int(d)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dobValid = cal.date(from: comps).map { cal.component(.day, from: $0) == Int(d) } ?? false

        let seqLast = a[16].wholeNumberValue ?? 0
        return Result(value: s, checksumOK: expected == last, expectedCheck: expected,
                      regionCode: region, dateOfBirthISO: iso, dateOfBirthValid: dobValid,
                      sex: seqLast % 2 == 1 ? .male : .female)
    }

    /// Find the first 18-character ID in OCR lines. Handles the label 公民身份号码 and spacing.
    public static func find(in ocrLines: [String]) -> Result? {
        let pattern = #"\d{17}[\dXx]"#
        for line in ocrLines {
            let compact = line.filter { !$0.isWhitespace }
            guard let r = compact.range(of: pattern, options: .regularExpression) else { continue }
            if let res = validate(String(compact[r])) { return res }
        }
        return nil
    }

    /// Parse 有效期限 like "2015.06.15-2035.06.15" or "2015.06.15-长期". Returns ISO dates; nil `to` = 长期.
    public static func parseValidity(_ text: String) -> (from: String, to: String?)? {
        let compact = text.filter { !$0.isWhitespace }
        let datePat = #"(\d{4})[.\-/年](\d{1,2})[.\-/月](\d{1,2})日?"#
        guard let regex = try? NSRegularExpression(pattern: datePat) else { return nil }
        let ns = compact as NSString
        let matches = regex.matches(in: compact, range: NSRange(location: 0, length: ns.length))
        func iso(_ m: NSTextCheckingResult) -> String {
            let y = ns.substring(with: m.range(at: 1))
            let mo = ns.substring(with: m.range(at: 2))
            let d = ns.substring(with: m.range(at: 3))
            return String(format: "%@-%02d-%02d", y, Int(mo) ?? 0, Int(d) ?? 0)
        }
        guard let first = matches.first else { return nil }
        if matches.count >= 2 { return (iso(first), iso(matches[1])) }
        if compact.contains("长期") { return (iso(first), nil) }
        return (iso(first), nil)
    }
}
