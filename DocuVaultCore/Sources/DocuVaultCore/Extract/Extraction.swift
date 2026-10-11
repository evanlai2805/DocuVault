import Foundation

/// Output of an extractor: fields plus warnings the review screen shows on the type card.
public struct ExtractionResult: Equatable, Sendable {
    public let type: DocumentType
    public var fields: [ExtractedField]
    public var warnings: [String]
    /// Number of code-verified checks that passed / were attempted (MRZ digits, Luhn, checksums, sums).
    public var checksPassed: Int
    public var checksTotal: Int

    public init(type: DocumentType, fields: [ExtractedField], warnings: [String] = [], checksPassed: Int = 0, checksTotal: Int = 0) {
        self.type = type
        self.fields = fields
        self.warnings = warnings
        self.checksPassed = checksPassed
        self.checksTotal = checksTotal
    }

    public var allChecksPassed: Bool { checksTotal == 0 || checksPassed == checksTotal }
    public var missingCount: Int { fields.filter { $0.check == .missing }.count }
    public var mainFields: [ExtractedField] { fields.filter { $0.section == .main } }
    public var secondaryFields: [ExtractedField] { fields.filter { $0.section == .secondary } }
}

/// Entry point: classify, then run the matching extractor.
public enum Extractor {
    public static func extract(type: DocumentType, lines: [String]) -> ExtractionResult {
        switch type {
        case .passport: return PassportExtractor.extract(lines: lines)
        case .nric: return NRICExtractor.extract(lines: lines)
        case .chinaID: return ChinaIDExtractor.extract(lines: lines)
        case .bankCard: return BankCardExtractor.extract(lines: lines)
        case .receipt: return ReceiptExtractor.extract(lines: lines)
        case .contract, .letter: return ContractExtractor.extract(lines: lines, type: type)
        case .businessCard: return BusinessCardExtractor.extract(lines: lines)
        case .other: return ExtractionResult(type: .other, fields: [])
        }
    }
}

/// Shared helpers for label-based reading of OCR lines.
enum LabelReader {
    /// Find a value next to any of the labels. Looks on the same line after the label, then the next non-empty line.
    /// Labels are matched case-insensitively. Returns nil if none found.
    static func value(after labels: [String], in lines: [String], maxNextLines: Int = 1) -> String? {
        for (i, line) in lines.enumerated() {
            for label in labels {
                guard let r = line.range(of: label, options: [.caseInsensitive]) else { continue }
                let rest = line[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :：\t.-/"))
                if rest.count >= 1 { return cleaned(rest) }
                // value on following line(s)
                for j in (i + 1)...(i + maxNextLines) where j < lines.count {
                    let next = lines[j].trimmingCharacters(in: .whitespaces)
                    if !next.isEmpty { return cleaned(next) }
                }
            }
        }
        return nil
    }

    static func cleaned(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func field(_ key: String, _ en: String, _ zh: String? = nil, _ value: String?, _ check: FieldCheck,
                      section: FieldSection = .main) -> ExtractedField {
        ExtractedField(key: key, labelEN: en, labelZH: zh, value: value ?? "", check: value == nil ? .missing : check, section: section)
    }
}
