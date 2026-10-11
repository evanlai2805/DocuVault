import Foundation

/// Singapore NRIC (S, T) and FIN (F, G, M) checksum.
///
/// Algorithm (public, widely documented):
///   weights 2,7,6,5,4,3,2 over the 7 digits; add 4 for T and G prefixes; add 3 for M;
///   remainder = sum % 11; letter = table[remainder].
///   S/T table: J Z I H G F E D C B A
///   F/G table: X W U T R Q P N M L K
///   M   table: X W U T R Q P N J L K   (M-series FIN, issued from 2022)
///
/// The M table is taken from public implementations and has not been verified here against a
/// real M-series FIN. Treat an M failure as "unverified", not "invalid", until you confirm one.
public enum NRIC {

    public enum Series: String, Sendable {
        case nricPre2000 = "S"
        case nric2000 = "T"
        case finPre2000 = "F"
        case fin2000 = "G"
        case fin2022 = "M"

        public var isNRIC: Bool { self == .nricPre2000 || self == .nric2000 }
    }

    public struct Result: Equatable, Sendable {
        public let value: String
        public let series: Series
        public let checksumOK: Bool
        public let expectedLetter: Character
        /// Birth-century hint for cross-checking the printed DOB. nil for FIN.
        public var birthCenturyHint: Int? {
            switch series {
            case .nricPre2000: return 1900
            case .nric2000: return 2000
            default: return nil
            }
        }
    }

    public static func expectedCheckLetter(prefix: Character, digits: String) -> Character? {
        guard digits.count == 7, let series = Series(rawValue: String(prefix)) else { return nil }
        let weights = [2, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (i, c) in digits.enumerated() {
            guard let d = c.wholeNumberValue else { return nil }
            sum += d * weights[i]
        }
        switch series {
        case .nric2000, .fin2000: sum += 4
        case .fin2022: sum += 3
        default: break
        }
        let table: [Character]
        switch series {
        case .nricPre2000, .nric2000: table = Array("JZIHGFEDCBA")
        case .finPre2000, .fin2000: table = Array("XWUTRQPNMLK")
        case .fin2022: table = Array("XWUTRQPNJLK")
        }
        return table[sum % 11]
    }

    /// Validate a 9-character NRIC/FIN like "S1234567D". Case-insensitive, ignores spaces.
    public static func validate(_ raw: String) -> Result? {
        let s = raw.uppercased().filter { !$0.isWhitespace }
        guard s.count == 9, let prefix = s.first, let last = s.last,
              let series = Series(rawValue: String(prefix)) else { return nil }
        let digits = String(s.dropFirst().dropLast())
        guard let expected = expectedCheckLetter(prefix: prefix, digits: digits) else { return nil }
        return Result(value: s, series: series, checksumOK: expected == last, expectedLetter: expected)
    }

    /// Find the first NRIC/FIN-shaped token in OCR lines.
    public static func find(in ocrLines: [String]) -> Result? {
        let pattern = #"\b[STFGM]\s?\d{7}\s?[A-Z]\b"#
        for line in ocrLines.map({ $0.uppercased() }) {
            guard let r = line.range(of: pattern, options: .regularExpression) else { continue }
            if let res = validate(String(line[r])) { return res }
        }
        return nil
    }

    /// Singapore postal code: exactly 6 digits, usually after "SINGAPORE".
    public static func findPostalCode(in text: String) -> String? {
        let pattern = #"SINGAPORE\s*(\d{6})\b"#
        if let r = text.uppercased().range(of: pattern, options: .regularExpression) {
            return String(text.uppercased()[r].suffix(6))
        }
        return nil
    }
}
