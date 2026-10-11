import Foundation
import DocuVaultCore

/// Guesses a document title from OCR lines. Rule from checkpoint 4:
/// first line with ≥ 4 CJK characters, or ≥ 3 Latin words. Skips noise lines.
public enum TitleGuesser {

    public static let maxLength = 60

    public static func guess(from lines: [String], fallback: String = "Untitled") -> String {
        for raw in lines.prefix(12) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isNoise(line) else { continue }
            let cjk = line.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            let words = line.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: \.isLetter) }.count
            if cjk >= 4 || words >= 3 {
                return clip(line)
            }
        }
        // Fallback: first non-empty line, clipped.
        if let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return clip(first.trimmingCharacters(in: .whitespaces))
        }
        return fallback
    }

    /// Lines that are dates, numbers, MRZ, or mostly punctuation make poor titles.
    static func isNoise(_ line: String) -> Bool {
        if line.count >= 30, line.filter({ $0 == "<" }).count > 5 { return true }        // MRZ
        let letters = line.filter(\.isLetter).count
        if letters == 0 { return true }                                                 // pure numbers / dates
        if Double(letters) / Double(line.count) < 0.4 { return true }                   // mostly digits/punct
        return false
    }

    static func clip(_ s: String) -> String {
        s.count <= maxLength ? s : String(s.prefix(maxLength - 1)) + "…"
    }
}
