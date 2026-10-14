import Foundation

/// Documents with no keys ("Other", imported notes) fill from their text lines (checkpoint 20, Evan:
/// "both scan and text lines"). Tap types a line; hold splits "Booking reference: K7Q2LM" into its
/// label and its value.
public enum FillLines {
    /// Non-empty lines, trimmed, in reading order. Capped so a long document cannot swell the keyboard's memory.
    public static func lines(from text: String, limit: Int = 80) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    /// "Label: value" → ("Label", "value"). Also the full-width colon used in Chinese text. Nil when the
    /// line has no colon, either side is empty, or the part before it is too long to be a label.
    public static func split(_ line: String) -> (label: String, value: String)? {
        guard let i = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let label = line[..<i].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty, label.count <= 30 else { return nil }
        return (label, value)
    }
}
