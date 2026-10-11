import Foundation

/// ICAO 9303 TD3 (passport) machine-readable zone: two lines of 44 characters.
/// All check digits use weights 7-3-1 and the value map 0-9 → 0-9, A-Z → 10-35, '<' → 0.
public enum MRZ {

    public struct TD3: Equatable, Sendable {
        public let documentCode: String        // "P" or "P<" variants
        public let issuingCountry: String      // ISO 3166-1 alpha-3, e.g. SGP
        public let surname: String
        public let givenNames: String
        public let documentNumber: String
        public let nationality: String
        public let dateOfBirth: String         // YYMMDD as printed
        public let sex: String                 // M, F, or "<" (unspecified)
        public let expiryDate: String          // YYMMDD as printed
        public let optionalData: String

        public let documentNumberCheckOK: Bool
        public let dateOfBirthCheckOK: Bool
        public let expiryCheckOK: Bool
        public let optionalDataCheckOK: Bool
        public let compositeCheckOK: Bool

        /// True only when every check digit matches. If false, the review screen flags the whole scan.
        public var allChecksOK: Bool {
            documentNumberCheckOK && dateOfBirthCheckOK && expiryCheckOK && optionalDataCheckOK && compositeCheckOK
        }

        /// Resolve YYMMDD to ISO yyyy-MM-dd. DOB: years > current YY are 19xx. Expiry: always 20xx.
        public func isoDateOfBirth(now: Date = Date()) -> String { MRZ.isoDate(dateOfBirth, isExpiry: false, now: now) }
        public func isoExpiryDate(now: Date = Date()) -> String { MRZ.isoDate(expiryDate, isExpiry: true, now: now) }
    }

    public enum ParseError: Error, Equatable {
        case wrongLineCount(Int)
        case wrongLineLength(line: Int, length: Int)
        case notTD3
    }

    // MARK: - Public API

    /// Character value per ICAO 9303.
    public static func value(of c: Character) -> Int {
        if c == "<" { return 0 }
        if let d = c.wholeNumberValue { return d }
        if let a = c.asciiValue, a >= 65, a <= 90 { return Int(a) - 55 }   // A=10 … Z=35
        return 0
    }

    /// Check digit for a string using weights 7, 3, 1.
    public static func checkDigit(_ s: String) -> Int {
        let weights = [7, 3, 1]
        var total = 0
        for (i, c) in s.enumerated() {
            total += value(of: c) * weights[i % 3]
        }
        return total % 10
    }

    /// Find two 44-character MRZ-looking lines in OCR output. Returns nil if not found.
    /// OCR often misreads '<' as 'K' or 'c' and 'O' as '0'; `normalise` fixes the common ones.
    public static func locateLines(in ocrLines: [String]) -> (String, String)? {
        let cleaned = ocrLines.map(normalise).filter { $0.count == 44 }
        guard cleaned.count >= 2 else { return nil }
        // Line 1 starts with P; line 2 immediately follows.
        for i in 0..<(cleaned.count - 1) where cleaned[i].hasPrefix("P") {
            return (cleaned[i], cleaned[i + 1])
        }
        return (cleaned[cleaned.count - 2], cleaned[cleaned.count - 1])
    }

    /// Parse and verify a TD3 MRZ.
    public static func parseTD3(line1 rawLine1: String, line2 rawLine2: String) throws -> TD3 {
        let l1 = normalise(rawLine1)
        let l2 = normalise(rawLine2)
        guard l1.count == 44 else { throw ParseError.wrongLineLength(line: 1, length: l1.count) }
        guard l2.count == 44 else { throw ParseError.wrongLineLength(line: 2, length: l2.count) }
        guard l1.hasPrefix("P") else { throw ParseError.notTD3 }

        let a1 = Array(l1), a2 = Array(l2)
        func s(_ a: [Character], _ r: Range<Int>) -> String { String(a[r]) }

        let documentCode = s(a1, 0..<2)
        let issuingCountry = s(a1, 2..<5)
        let nameField = s(a1, 5..<44)
        let nameParts = nameField.components(separatedBy: "<<")
        let surname = nameParts.first.map { $0.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces) } ?? ""
        let givenNames = nameParts.dropFirst().joined(separator: " ")
            .replacingOccurrences(of: "<", with: " ")
            .split(separator: " ").joined(separator: " ")

        let docNo = s(a2, 0..<9)
        let docNoCD = s(a2, 9..<10)
        let nationality = s(a2, 10..<13)
        let dob = s(a2, 13..<19)
        let dobCD = s(a2, 19..<20)
        let sex = s(a2, 20..<21)
        let exp = s(a2, 21..<27)
        let expCD = s(a2, 27..<28)
        let optional = s(a2, 28..<42)
        let optionalCD = s(a2, 42..<43)
        let compositeCD = s(a2, 43..<44)

        func matches(_ cd: String, _ field: String) -> Bool {
            Int(cd) == checkDigit(field)
        }
        // Optional-data check digit may be '<' when the field is empty (ICAO allows this).
        let optionalOK = (optionalCD == "<" && optional.allSatisfy { $0 == "<" }) || matches(optionalCD, optional)
        let composite = docNo + docNoCD + dob + dobCD + exp + expCD + optional + optionalCD

        return TD3(
            documentCode: documentCode,
            issuingCountry: issuingCountry,
            surname: surname,
            givenNames: givenNames,
            documentNumber: docNo.replacingOccurrences(of: "<", with: ""),
            nationality: nationality,
            dateOfBirth: dob,
            sex: sex,
            expiryDate: exp,
            optionalData: optional.replacingOccurrences(of: "<", with: ""),
            documentNumberCheckOK: matches(docNoCD, docNo),
            dateOfBirthCheckOK: matches(dobCD, dob),
            expiryCheckOK: matches(expCD, exp),
            optionalDataCheckOK: optionalOK,
            compositeCheckOK: matches(compositeCD, composite)
        )
    }

    /// Build a valid TD3 line 2 from parts. Used by tests and by the review screen's "what should it be" hint.
    public static func buildLine2(documentNumber: String, nationality: String, dateOfBirth: String,
                                  sex: String, expiry: String, optionalData: String = "") -> String {
        let docNo = pad(documentNumber, 9)
        let dob = pad(dateOfBirth, 6)
        let exp = pad(expiry, 6)
        let opt = pad(optionalData, 14)
        let c1 = checkDigit(docNo), c2 = checkDigit(dob), c3 = checkDigit(exp), c4 = checkDigit(opt)
        let composite = checkDigit(docNo + "\(c1)" + dob + "\(c2)" + exp + "\(c3)" + opt + "\(c4)")
        return docNo + "\(c1)" + pad(nationality, 3) + dob + "\(c2)" + pad(sex, 1) + exp + "\(c3)" + opt + "\(c4)" + "\(composite)"
    }

    public static func buildLine1(issuingCountry: String, surname: String, givenNames: String) -> String {
        let name = surname.uppercased().replacingOccurrences(of: " ", with: "<") + "<<" +
                   givenNames.uppercased().replacingOccurrences(of: " ", with: "<")
        return "P<" + pad(issuingCountry, 3) + pad(name, 39)
    }

    // MARK: - Helpers

    /// Uppercase, strip spaces, fix the OCR confusions that matter inside an MRZ.
    static func normalise(_ line: String) -> String {
        var s = line.uppercased().filter { !$0.isWhitespace }
        // OCR reads filler '<' as these; inside an MRZ none of them are otherwise valid in filler runs.
        s = s.replacingOccurrences(of: "«", with: "<")
        s = s.replacingOccurrences(of: "‹", with: "<")
        return s
    }

    static func pad(_ s: String, _ n: Int) -> String {
        let up = s.uppercased()
        if up.count >= n { return String(up.prefix(n)) }
        return up + String(repeating: "<", count: n - up.count)
    }

    static func isoDate(_ yymmdd: String, isExpiry: Bool, now: Date) -> String {
        guard yymmdd.count == 6, let yy = Int(yymmdd.prefix(2)) else { return yymmdd }
        let mm = yymmdd.dropFirst(2).prefix(2)
        let dd = yymmdd.suffix(2)
        let currentYY = Calendar(identifier: .gregorian).component(.year, from: now) % 100
        let century: Int
        if isExpiry {
            century = 2000
        } else {
            century = yy > currentYY ? 1900 : 2000
        }
        return "\(century + yy)-\(mm)-\(dd)"
    }
}
