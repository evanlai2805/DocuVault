import Foundation
import SwiftData
import DocuVaultCore

/// A saved document. Pages carry their own image file and OCR result.
@Model
final class StoredDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRaw: String                 // DocumentType.rawValue
    var language: String                // "en" | "zh-Hans" | "mixed"
    var sensitive: Bool
    var capturedAt: Date
    var sourceRaw: String               // CaptureSource.rawValue
    var fullText: String                // all pages joined; drives search
    @Relationship(deleteRule: .cascade, inverse: \StoredPage.document)
    var pages: [StoredPage]
    @Relationship(deleteRule: .cascade, inverse: \StoredField.document)
    var fields: [StoredField]
    var checksPassed: Int
    var checksTotal: Int
    var person: StoredPerson?
    /// Client retention. nil = never auto-deletes.
    var expiresAt: Date?
    /// For sensitive documents `fullText` is empty and the text lives here, sealed with the vault key.
    var sealedText: Data?
    var notes: String
    /// DocumentSummary encoded. Sealed with the vault key for sensitive documents (rare: summaries are hidden for ID types).
    var summaryJSON: Data?

    init(id: UUID = UUID(), title: String, type: DocumentType, language: String, sensitive: Bool,
         capturedAt: Date = Date(), source: CaptureSource, fullText: String, pages: [StoredPage] = [],
         fields: [StoredField] = [], checksPassed: Int = 0, checksTotal: Int = 0,
         person: StoredPerson? = nil, expiresAt: Date? = nil, sealedText: Data? = nil, notes: String = "") {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.language = language
        self.sensitive = sensitive
        self.capturedAt = capturedAt
        self.sourceRaw = source.rawValue
        self.fullText = fullText
        self.pages = pages
        self.fields = fields
        self.checksPassed = checksPassed
        self.checksTotal = checksTotal
        self.person = person
        self.expiresAt = expiresAt
        self.sealedText = sealedText
        self.notes = notes
    }

    var type: DocumentType {
        get { DocumentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .files }
    var orderedPages: [StoredPage] { pages.sorted { $0.index < $1.index } }
    var orderedFields: [StoredField] { fields.sorted { $0.order < $1.order } }
    var allChecksPassed: Bool { checksTotal == 0 || checksPassed == checksTotal }
}

/// One extracted field. Secondary-section fields (race, blood group, CVV…) are stored apart from the main block.
@Model
final class StoredField {
    @Attribute(.unique) var id: UUID
    var order: Int
    var key: String
    var labelEN: String
    var labelZH: String?
    /// Plain value for non-sensitive documents. Empty when `sealedValue` is set.
    var value: String
    /// Vault-sealed value for sensitive documents.
    var sealedValue: Data?
    var checkRaw: String        // FieldCheck.rawValue
    var sectionRaw: String      // FieldSection.rawValue
    var document: StoredDocument?

    init(id: UUID = UUID(), order: Int, field: ExtractedField, sealedValue: Data? = nil) {
        self.id = id
        self.order = order
        self.key = field.key
        self.labelEN = field.labelEN
        self.labelZH = field.labelZH
        self.value = sealedValue == nil ? field.value : ""
        self.sealedValue = sealedValue
        self.checkRaw = field.check.rawValue
        self.sectionRaw = field.section.rawValue
    }

    var isSealed: Bool { sealedValue != nil }

    var check: FieldCheck { FieldCheck(rawValue: checkRaw) ?? .ocr }
    var section: FieldSection { FieldSection(rawValue: sectionRaw) ?? .main }
    var asExtracted: ExtractedField {
        ExtractedField(key: key, labelEN: labelEN, labelZH: labelZH, value: value, check: check, section: section)
    }
}

@Model
final class StoredPage {
    @Attribute(.unique) var id: UUID
    var index: Int
    var imageFileName: String           // relative to PageStore.directory
    var ocrJSON: Data?                  // OCRPage encoded; nil when text came from a PDF text layer
    var text: String
    var meanConfidence: Double
    var document: StoredDocument?

    init(id: UUID = UUID(), index: Int, imageFileName: String, ocrJSON: Data?, text: String, meanConfidence: Double) {
        self.id = id
        self.index = index
        self.imageFileName = imageFileName
        self.ocrJSON = ocrJSON
        self.text = text
        self.meanConfidence = meanConfidence
    }
}

enum CaptureSource: String, Codable, Sendable {
    case camera, photos, files, clipboard, pdf
    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .photos: return "Photos"
        case .files: return "Files"
        case .clipboard: return "Clipboard"
        case .pdf: return "PDF"
        }
    }
}


/// A person or entity who owns vault documents. Shared fields feed the keyboard (Phase 5).
@Model
final class StoredPerson {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String                 // PersonKind.rawValue
    var retentionDays: Int?             // client default 30; nil = never
    var createdAt: Date
    var fullName: String
    var address: String
    var phone: String
    var email: String
    @Relationship(deleteRule: .nullify, inverse: \StoredDocument.person)
    var documents: [StoredDocument]

    init(id: UUID = UUID(), name: String, kind: PersonKind, retentionDays: Int? = nil, createdAt: Date = Date(),
         fullName: String = "", address: String = "", phone: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.retentionDays = retentionDays
        self.createdAt = createdAt
        self.fullName = fullName
        self.address = address
        self.phone = phone
        self.email = email
        self.documents = []
    }

    var kind: PersonKind {
        get { PersonKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

/// One-line trace of a document removed by retention. Shown in the Vault and written to index.md.
@Model
final class StoredTombstone {
    @Attribute(.unique) var id: UUID
    var line: String
    var deletedAt: Date
    init(id: UUID = UUID(), line: String, deletedAt: Date = Date()) {
        self.id = id
        self.line = line
        self.deletedAt = deletedAt
    }
}
