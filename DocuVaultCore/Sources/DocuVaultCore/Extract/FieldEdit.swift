import Foundation

/// Editing one field of a saved document (Evan, checkpoint 14 Q1).
/// A checksum is re-run in code wherever the field carries its own; everything else becomes `.user`,
/// meaning Evan checked it against the scan. Passport MRZ digits cannot be re-run from one stored field,
/// because the MRZ lines themselves are not stored.
public enum FieldEdit {

    /// Keys that hold a date. Stored as ISO yyyy-MM-dd; a card's expiry is the exception (MM/YY).
    public static let dateKeys: Set<String> = ["dateOfBirth", "expiry", "issueDate", "date", "effectiveDate",
                                               "expiryDate", "validFrom", "validTo"]

    /// Keys whose check counts toward the document's checks, per type.
    static func checkedKeys(_ type: DocumentType) -> Set<String> {
        switch type {
        case .passport: ["passportNumber", "dateOfBirth", "expiry"]
        case .nric: ["nric"]
        case .chinaID: ["idNumber"]
        case .bankCard: ["pan"]
        default: []
        }
    }

    public static func isDate(key: String, type: DocumentType) -> Bool {
        dateKeys.contains(key) && !(type == .bankCard && key == "expiry")
    }

    /// Trim, and turn any recognisable date into ISO so the keyboard can format it later.
    /// A value that is not a date (长期, "Indefinite") is kept as typed.
    public static func normalize(key: String, value: String, type: DocumentType) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDate(key: key, type: type), let iso = TextRules.firstISODate(in: v) { return iso }
        if key == "pan" { return v.filter(\.isNumber) }
        return v
    }

    /// The check a field carries after an edit. A failed checksum becomes `.ocr`, the same tag the
    /// extractors give a number whose check digit failed.
    public static func recheck(key: String, value: String, type: DocumentType) -> FieldCheck {
        if value.isEmpty { return .missing }
        switch key {
        case "pan": return CardCheck.validate(value)?.luhnOK == true ? .luhn : .ocr
        case "nric": return NRIC.validate(value)?.checksumOK == true ? .nric : .ocr
        case "idNumber": return ChinaID.validate(value)?.checksumOK == true ? .cnid : .ocr
        default: return .user
        }
    }

    /// The document's new pass count after one field moved from `old` to `new`.
    /// Only checked keys move the count; a name or address edit leaves it alone.
    public static func adjustedPassed(passed: Int, total: Int, key: String, type: DocumentType,
                                      old: FieldCheck, new: FieldCheck) -> Int {
        guard total > 0, checkedKeys(type).contains(key) else { return passed }
        let was = old.confidenceTier == .verified ? 1 : 0
        let now = new.confidenceTier == .verified ? 1 : 0
        return min(max(passed + now - was, 0), total)
    }

    /// Fields derived from the edited one: a new card number also rewrites Last 4 and Brand.
    public static func derived(key: String, value: String) -> [String: String] {
        guard key == "pan", let c = CardCheck.validate(value) else { return [:] }
        return ["last4": c.last4, "brand": c.brand.rawValue]
    }
}
