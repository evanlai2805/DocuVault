import Foundation

/// Display rules for text the app shows (Evan, checkpoint 14): every label and each `·` segment starts
/// with a capital, and every date reads 12/MAR/1990. Used on strings that were stored before the rule,
/// such as old tombstone lines and cloud log purposes. Stored values themselves are never rewritten.
public enum DisplayText {

    /// Capitalise the first letter of the string and of each `·` segment. Leaves the rest alone, so
    /// "SG region", "60 s" and Chinese text pass through unchanged.
    public static func capitalisedSegments(_ text: String) -> String {
        text.components(separatedBy: " · ").map(capitaliseFirstLetter).joined(separator: " · ")
    }

    static func capitaliseFirstLetter(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }), s[i].isLowercase,
              s[s.startIndex..<i].allSatisfy({ !$0.isNumber }) else { return s }
        return s.replacingCharacters(in: i...i, with: s[i].uppercased())
    }

    /// Replace every ISO yyyy-MM-dd inside a line with the display form.
    public static func displayDates(in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}\b"#) else { return text }
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let iso = ns.substring(with: m.range)
            out = (out as NSString).replacingCharacters(in: m.range, with: FillFormats.display(iso))
        }
        return out
    }
}
