import Foundation

/// Wordings a form may want for a stored value (Evan, checkpoint 15 follow-up): a Singapore passport
/// stores SGP, but a form may ask for "Singaporean", "Singapore" or "Singapore citizen". The keyboard's
/// hold menu offers these; the one picked is remembered per person, document and field.
/// Pure tables and string rules, no UI.
public enum FillVariants {

    /// One wording the hold menu can offer. `id` is stable across launches so a pick can be remembered.
    public struct Variant: Equatable, Sendable, Identifiable {
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }

    /// ISO 3166-1 alpha-3 code → (demonym, country, "<country> citizen" wording). The table covers the
    /// passports Evan is likely to hold or handle; an unknown code or wording passes through as itself.
    static let countries: [String: (demonym: String, country: String)] = [
        "SGP": ("Singaporean", "Singapore"),
        "MYS": ("Malaysian", "Malaysia"),
        "CHN": ("Chinese", "China"),
        "HKG": ("Hong Kong", "Hong Kong"),
        "TWN": ("Taiwanese", "Taiwan"),
        "IDN": ("Indonesian", "Indonesia"),
        "THA": ("Thai", "Thailand"),
        "VNM": ("Vietnamese", "Vietnam"),
        "PHL": ("Filipino", "Philippines"),
        "IND": ("Indian", "India"),
        "JPN": ("Japanese", "Japan"),
        "KOR": ("Korean", "South Korea"),
        "AUS": ("Australian", "Australia"),
        "NZL": ("New Zealander", "New Zealand"),
        "GBR": ("British", "United Kingdom"),
        "USA": ("American", "United States"),
        "CAN": ("Canadian", "Canada"),
        "FRA": ("French", "France"),
        "DEU": ("German", "Germany"),
    ]

    /// Wordings for a nationality value. Accepts the ISO code (SGP), the country name (Singapore), the
    /// demonym (Singaporean) or an NRIC-style "SINGAPORE CITIZEN", in any case.
    /// Order: demonym, country, "<country> citizen", code. The first is the default insert.
    public static func nationality(_ raw: String) -> [Variant] {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let upper = key.uppercased()
        let code: String? = {
            if let c = countries[upper] { _ = c; return upper }
            let stripped = upper.replacingOccurrences(of: " CITIZEN", with: "").trimmingCharacters(in: .whitespaces)
            return countries.first { $0.value.country.uppercased() == stripped || $0.value.demonym.uppercased() == stripped }?.key
        }()
        guard let code, let c = countries[code] else { return [Variant(id: "raw", text: key)] }
        return [
            Variant(id: "demonym", text: c.demonym),
            Variant(id: "country", text: c.country),
            Variant(id: "citizen", text: c.country + " citizen"),
            Variant(id: "code", text: code),
        ]
    }

    /// Wordings for a sex value: F → F, Female; M → M, Male. Anything else passes through.
    public static func sex(_ raw: String) -> [Variant] {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "F", "FEMALE", "女": return [Variant(id: "letter", text: "F"), Variant(id: "word", text: "Female")]
        case "M", "MALE", "男": return [Variant(id: "letter", text: "M"), Variant(id: "word", text: "Male")]
        case "": return []
        default: return [Variant(id: "raw", text: raw)]
        }
    }

    /// The variants for a field key, or an empty list when the field has only one wording.
    public static func variants(fieldKey: String, value: String) -> [Variant] {
        switch fieldKey {
        case "nationality", "issuingCountry": return nationality(value)
        case "sex": return sex(value)
        default: return []
        }
    }
}
