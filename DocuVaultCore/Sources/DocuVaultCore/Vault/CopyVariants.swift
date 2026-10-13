import Foundation

/// What the app copies from a field (checkpoint 16). A tap copies what the row shows; holding offers
/// the same wordings the keyboard's hold menu inserts, built from the same formatters, so the two
/// never disagree.
public enum CopyVariants {

    public struct Option: Equatable, Identifiable, Sendable {
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }

    /// The value as the row displays it: dates read 12/MAR/1990, everything else as stored.
    public static func shown(fieldKey: String, value: String, type: DocumentType) -> String {
        isDate(fieldKey, type) ? FillFormats.display(value) : value
    }

    /// Other ways to copy the value, excluding the one a tap already gives.
    public static func options(fieldKey: String, value: String, type: DocumentType, fields: [String: String] = [:]) -> [Option] {
        guard !value.isEmpty else { return [] }
        var out: [Option]
        if isDate(fieldKey, type), TextRules.firstISODate(in: value) == value {
            out = FillFormats.DateStyle.menu.map { Option(id: $0.rawValue, text: FillFormats.date(value, style: $0)) }
        } else if type == .bankCard && fieldKey == "expiry" {
            out = FillFormats.ExpiryStyle.allCases.map { Option(id: $0.rawValue, text: FillFormats.expiry(value, style: $0)) }
        } else if fieldKey == "pan" {
            out = [Option(id: "plain", text: FillFormats.cardNumber(value, spaced: false)),
                   Option(id: "spaced", text: FillFormats.cardNumber(value, spaced: true))]
        } else if fieldKey == "name", type == .chinaID, let pinyin = fields["namePinyin"], !pinyin.isEmpty {
            out = [Option(id: "chars", text: value), Option(id: "pinyin", text: pinyin)]
        } else {
            out = FillVariants.variants(fieldKey: fieldKey, value: value).map { Option(id: $0.id, text: $0.text) }
        }
        let tap = shown(fieldKey: fieldKey, value: value, type: type)
        var seen: Set<String> = [tap]
        return out.filter { seen.insert($0.text).inserted }
    }

    private static func isDate(_ key: String, _ type: DocumentType) -> Bool {
        FieldEdit.dateKeys.contains(key) && !(type == .bankCard && key == "expiry")
    }
}
