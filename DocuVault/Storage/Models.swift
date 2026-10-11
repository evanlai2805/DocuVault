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

    init(id: UUID = UUID(), title: String, type: DocumentType, language: String, sensitive: Bool,
         capturedAt: Date = Date(), source: CaptureSource, fullText: String, pages: [StoredPage] = []) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.language = language
        self.sensitive = sensitive
        self.capturedAt = capturedAt
        self.sourceRaw = source.rawValue
        self.fullText = fullText
        self.pages = pages
    }

    var type: DocumentType {
        get { DocumentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .files }
    var orderedPages: [StoredPage] { pages.sorted { $0.index < $1.index } }
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
