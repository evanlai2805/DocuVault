import Foundation

/// Hanyu Pinyin for Chinese names, with a surname/given-name split the user confirms.
/// Uses Foundation's Mandarin→Latin transform (on-device, no network). Tones are stripped; output is upper case.
public enum Pinyin {

    public struct NameSplit: Equatable, Sendable {
        public var syllables: [String]      // one per Chinese character, upper case, e.g. ["WANG", "WEI"]
        public var characters: [Character]  // the Chinese characters in the same order
        public var surnameCount: Int        // how many leading characters are the surname (1 or 2)
        public var surnameFirst: Bool       // WANG WEI (true) vs WEI WANG (false)

        public var surname: String { syllables.prefix(surnameCount).joined() }
        public var givenName: String { syllables.dropFirst(surnameCount).joined(separator: " ") }
        public var formatted: String {
            surnameFirst ? [surname, givenName].filter { !$0.isEmpty }.joined(separator: " ")
                         : [givenName, surname].filter { !$0.isEmpty }.joined(separator: " ")
        }
        public var surnameCharacters: String { String(characters.prefix(surnameCount)) }
        public var givenCharacters: String { String(characters.dropFirst(surnameCount)) }
    }

    /// Common two-character surnames. If the name starts with one, surnameCount defaults to 2.
    public static let compoundSurnames: Set<String> = [
        "欧阳", "司马", "上官", "诸葛", "夏侯", "皇甫", "尉迟", "公孙", "慕容", "长孙", "宇文", "司徒", "司空", "令狐", "东方", "轩辕", "端木", "呼延", "南宫", "百里"
    ]

    /// Pinyin syllable for one Chinese character (upper case, no tone marks). Non-CJK characters return themselves.
    public static func syllable(for ch: Character) -> String {
        guard ch.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return String(ch).uppercased() }
        let s = NSMutableString(string: String(ch))
        CFStringTransform(s, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(s, nil, kCFStringTransformStripDiacritics, false)
        return (s as String).uppercased().trimmingCharacters(in: .whitespaces)
    }

    /// Split a Chinese name. Defaults: surname = first character (or first two if a compound surname), surname first.
    public static func split(_ name: String) -> NameSplit? {
        let chars = Array(name.filter { !$0.isWhitespace })
        guard !chars.isEmpty, chars.allSatisfy({ $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }) else { return nil }
        let count = chars.count >= 3 && compoundSurnames.contains(String(chars.prefix(2))) ? 2 : 1
        return NameSplit(syllables: chars.map(syllable(for:)), characters: chars, surnameCount: min(count, chars.count), surnameFirst: true)
    }
}
