import Foundation

/// Plain-text views of the vault: one .md per document, an index.md, and expenses.csv.
/// Pure functions over value types so the app and tests share them.
public struct ExportDocument: Equatable, Sendable {
    public var title: String
    public var owner: String
    public var ownerKind: PersonKind
    public var type: DocumentType
    public var sensitive: Bool
    public var capturedAt: Date
    public var source: String
    public var language: String
    public var checksPassed: Int
    public var checksTotal: Int
    public var fields: [ExtractedField]
    public var expiresAt: Date?
    public var notes: String?
    public var imageFileNames: [String]

    public init(title: String, owner: String, ownerKind: PersonKind, type: DocumentType, sensitive: Bool, capturedAt: Date,
                source: String, language: String, checksPassed: Int, checksTotal: Int, fields: [ExtractedField],
                expiresAt: Date? = nil, notes: String? = nil, imageFileNames: [String] = []) {
        self.title = title; self.owner = owner; self.ownerKind = ownerKind; self.type = type; self.sensitive = sensitive
        self.capturedAt = capturedAt; self.source = source; self.language = language; self.checksPassed = checksPassed
        self.checksTotal = checksTotal; self.fields = fields; self.expiresAt = expiresAt; self.notes = notes; self.imageFileNames = imageFileNames
    }
}

public enum MarkdownExporter {

    // MARK: Document

    public static func markdown(for d: ExportDocument) -> String {
        var out: [String] = []
        out.append("# \(d.type.displayName) — \(d.title)")
        out.append("owner: \(d.owner)            kind: \(d.ownerKind.rawValue)            type: \(d.type.rawValue)        sensitive: \(d.sensitive ? "high" : "normal")")
        let checks = d.checksTotal == 0 ? "none" : "\(d.checksPassed)/\(d.checksTotal) \(d.checksPassed == d.checksTotal ? "✓" : "✗")"
        out.append("captured: \(day(d.capturedAt))   source: \(d.source)      language: \(d.language)          checks: \(checks)")
        if let e = d.expiresAt { out.append("retention: deletes \(day(e))") }
        out.append("")

        let main = d.fields.filter { $0.section == .main }
        let secondary = d.fields.filter { $0.section == .secondary }
        out.append(contentsOf: table(main))
        if !secondary.isEmpty {
            out.append("")
            out.append("## Secondary")
            out.append(contentsOf: table(secondary))
        }

        let copyBlock = main.filter { !$0.value.isEmpty }.map(\.value).joined(separator: " | ")
        if !copyBlock.isEmpty {
            out.append("")
            out.append("## Copy block")
            out.append(copyBlock)
        }
        if !d.imageFileNames.isEmpty {
            out.append("")
            out.append("## Images")
            out.append(contentsOf: d.imageFileNames.map { "\($0) (encrypted in app)" })
        }
        if let n = d.notes, !n.isEmpty {
            out.append("")
            out.append("## Notes")
            out.append(n)
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func table(_ fields: [ExtractedField]) -> [String] {
        guard !fields.isEmpty else { return ["(no fields)"] }
        let labelW = max(5, fields.map { $0.labelEN.count }.max() ?? 5)
        let valueW = max(5, fields.map { ($0.value.isEmpty ? "—" : $0.value).count }.max() ?? 5)
        func pad(_ s: String, _ w: Int) -> String { s + String(repeating: " ", count: max(0, w - s.count)) }
        var rows = ["| \(pad("Field", labelW)) | \(pad("Value", valueW)) | Check   |",
                    "|\(String(repeating: "-", count: labelW + 2))|\(String(repeating: "-", count: valueW + 2))|---------|"]
        for f in fields {
            rows.append("| \(pad(f.labelEN, labelW)) | \(pad(f.value.isEmpty ? "—" : f.value.replacingOccurrences(of: "|", with: "¦"), valueW)) | \(pad(checkLabel(f.check), 7)) |")
        }
        return rows
    }

    static func checkLabel(_ c: FieldCheck) -> String {
        switch c {
        case .mrz: "MRZ ✓"; case .luhn: "Luhn ✓"; case .nric: "NRIC ✓"; case .cnid: "ID ✓"
        case .regex: "regex"; case .ocr: "OCR"; case .user: "edited"; case .missing: "missing"
        }
    }

    // MARK: Index

    public struct IndexRow: Equatable, Sendable {
        public let owner: String
        public let kind: PersonKind
        public let title: String
        public let type: DocumentType
        public let expiry: String?        // document's own expiry field (passport/card), ISO or MM/YY
        public let checks: String
        public let path: String           // relative .md path
        public init(owner: String, kind: PersonKind, title: String, type: DocumentType, expiry: String?, checks: String, path: String) {
            self.owner = owner; self.kind = kind; self.title = title; self.type = type; self.expiry = expiry; self.checks = checks; self.path = path
        }
    }

    public static func index(rows: [IndexRow], tombstones: [String], generatedAt: Date) -> String {
        var out = ["# DocuVault index", "generated: \(stamp(generatedAt)) · \(rows.count) documents", ""]
        let grouped = Dictionary(grouping: rows, by: { $0.owner })
        for owner in grouped.keys.sorted() {
            let rs = grouped[owner]!
            out.append("## \(owner) (\(rs.first!.kind.displayName))")
            out.append("| Document | Type | Expiry | Checks | File |")
            out.append("|---|---|---|---|---|")
            for r in rs.sorted(by: { $0.title < $1.title }) {
                out.append("| \(r.title) | \(r.type.displayName) | \(r.expiry ?? "—") | \(r.checks) | [\(r.path)](\(r.path)) |")
            }
            out.append("")
        }
        if !tombstones.isEmpty {
            out.append("## Deleted (retention)")
            out.append(contentsOf: tombstones)
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Safe relative path: vault/<owner>/<type>-<title>.md
    public static func relativePath(owner: String, type: DocumentType, title: String) -> String {
        "vault/\(slug(owner))/\(type.rawValue)-\(slug(title)).md"
    }

    public static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        for scalar in s.unicodeScalars {
            if allowed.contains(scalar) || (0x4E00...0x9FFF).contains(scalar.value) { out.unicodeScalars.append(scalar) }
            else if scalar == " " { out.append("-") }
        }
        // Collapse runs of dashes and trim them at the ends.
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "untitled" : String(out.prefix(60))
    }

    // MARK: Expenses CSV

    public static let csvHeader = ReceiptExtractor.csvHeader

    /// Append a receipt row. Creates the header when `existing` is empty. Skips exact duplicates.
    public static func appendCSV(existing: String, row: String) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if lines.isEmpty { lines = [csvHeader] }
        if !lines.contains(row) { lines.append(row) }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Helpers

    static func day(_ d: Date) -> String { Retention.isoDay(d) }
    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
    }
}
