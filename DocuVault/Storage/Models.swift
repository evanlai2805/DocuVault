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

    init(id: UUID = UUID(), title: String, type: DocumentType, language: String, sensitive: Bool,
         capturedAt: Date = Date(), source: CaptureSource, fullText: String, pages: [StoredPage] = [],
         fields: [StoredField] = [], checksPassed: Int = 0, checksTotal: Int = 0) {
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
    var value: String
    var checkRaw: String        // FieldCheck.rawValue
    var sectionRaw: String      // FieldSection.rawValue
    var document: StoredDocument?

    init(id: UUID = UUID(), order: Int, field: ExtractedField) {
        self.id = id
        self.order = order
        self.key = field.key
        self.labelEN = field.labelEN
        self.labelZH = field.labelZH
        self.value = field.value
        self.checkRaw = field.check.rawValue
        self.sectionRaw = field.section.rawValue
    }

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
