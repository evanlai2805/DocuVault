import SwiftUI
import CoreGraphics
import DocuVaultCore
import DocuVaultOCR

/// One page being prepared before it becomes a StoredPage.
struct DraftPage: Identifiable, Sendable {
    enum Enhance: String, CaseIterable, Sendable { case colour = "Colour", greyscale = "Greyscale", blackWhite = "B&W" }
    enum OCRState: Sendable, Equatable {
        case queued, running, done(OCRPage), embedded(String), failed(String)
    }

    let id = UUID()
    var original: CGImage
    var enhance: Enhance = .colour
    var quarterTurns: Int = 0
    /// Present when the page came from a text PDF; OCR is skipped.
    var embeddedText: String?
    var ocr: OCRState = .queued

    /// The image after rotation and enhancement. Computed on demand; cached by views.
    func processed() -> CGImage {
        var img = ImageNormalizer.rotated(original, quarterTurnsClockwise: quarterTurns) ?? original
        switch enhance {
        case .colour: break
        case .greyscale: img = ImageNormalizer.greyscale(img) ?? img
        case .blackWhite: img = ImageEnhancer.blackAndWhite(img) ?? ImageNormalizer.greyscale(img) ?? img
        }
        return img
    }

    var text: String {
        switch ocr {
        case .done(let page): return page.text
        case .embedded(let t): return t
        default: return ""
        }
    }

    var meanConfidence: Double {
        switch ocr {
        case .done(let page): return page.meanConfidence
        case .embedded: return 1.0
        default: return 0
        }
    }
}

/// Holds the in-progress capture across the import → pages → OCR → save screens.
@MainActor @Observable
final class CaptureSession {
    var pages: [DraftPage] = []
    var source: CaptureSource = .camera
    var isRunningOCR = false

    // Phase 3: classification + extraction, editable on the review screen.
    var verdict: Classifier.Verdict?
    var chosenType: DocumentType = .other
    var extraction: ExtractionResult?

    var hasPages: Bool { !pages.isEmpty }

    func reset() {
        pages = []
        isRunningOCR = false
        verdict = nil
        chosenType = .other
        extraction = nil
    }

    /// Run after OCR. Rules pick the type; the user can override with `changeType`.
    func classifyAndExtract() {
        let v = Classifier.classify(lines: allTextLines)
        verdict = v
        chosenType = v.type
        extraction = Extractor.extract(type: v.type, lines: allTextLines)
    }

    /// Re-extract with another type. Edits are kept where the field key matches.
    func changeType(_ t: DocumentType) {
        let previous = extraction?.fields ?? []
        var next = Extractor.extract(type: t, lines: allTextLines)
        for (i, f) in next.fields.enumerated() {
            if let old = previous.first(where: { $0.key == f.key }), old.check == .user {
                next.fields[i].value = old.value
                next.fields[i].check = .user
            }
        }
        chosenType = t
        extraction = next
    }

    func editField(key: String, value: String) {
        guard var e = extraction, let i = e.fields.firstIndex(where: { $0.key == key }) else { return }
        e.fields[i].value = value
        e.fields[i].check = value.isEmpty ? .missing : .user
        extraction = e
    }

    func applyPinyin(_ split: Pinyin.NameSplit) {
        editField(key: "namePinyin", value: split.formatted)
        editField(key: "surnamePinyin", value: split.surname)
        editField(key: "givenNamePinyin", value: split.givenName)
    }

    var isSensitive: Bool { chosenType.isSensitiveByDefault || looksSensitive }

    func add(_ images: [CGImage], source: CaptureSource) {
        self.source = source
        pages.append(contentsOf: images.map { DraftPage(original: $0) })
    }

    func addPDF(_ imported: [PDFImporter.ImportedPage]) {
        source = .pdf
        pages.append(contentsOf: imported.map { p in
            var d = DraftPage(original: p.image)
            d.embeddedText = p.embeddedText
            if let t = p.embeddedText { d.ocr = .embedded(t) }
            return d
        })
    }

    func remove(_ id: DraftPage.ID) { pages.removeAll { $0.id == id } }

    func rotate(_ id: DraftPage.ID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].quarterTurns = (pages[i].quarterTurns + 1) % 4
        pages[i].ocr = pages[i].embeddedText.map { .embedded($0) } ?? .queued
    }

    func setEnhance(_ id: DraftPage.ID, _ e: DraftPage.Enhance) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].enhance = e
        pages[i].ocr = pages[i].embeddedText.map { .embedded($0) } ?? .queued
    }

    func move(from: IndexSet, to: Int) { pages.move(fromOffsets: from, toOffset: to) }

    /// Run OCR on every queued page, one at a time, updating state as each finishes.
    func runOCR() async {
        guard !isRunningOCR else { return }
        isRunningOCR = true
        defer { isRunningOCR = false }
        for i in pages.indices {
            guard case .queued = pages[i].ocr else { continue }
            pages[i].ocr = .running
            let img = pages[i].processed()
            do {
                let page = try await OCREngine.shared.recognize(img, mode: .auto)
                pages[i].ocr = .done(page)
            } catch {
                pages[i].ocr = .failed(error.localizedDescription)
            }
        }
    }

    var allTextLines: [String] {
        pages.flatMap { $0.text.components(separatedBy: "\n") }
    }

    var fullText: String { pages.map(\.text).joined(separator: "\n\n") }

    var detectedLanguage: String { TextRules.detectLanguage(fullText).rawValue }

    var guessedTitle: String { TitleGuesser.guess(from: allTextLines) }

    /// Rule from checkpoint 1: identity-looking content is sensitive by default.
    var looksSensitive: Bool { OCREngine.looksLikeIdentityDocument(allTextLines) }

    var ocrComplete: Bool {
        pages.allSatisfy {
            switch $0.ocr {
            case .done, .embedded, .failed: return true
            default: return false
            }
        }
    }
}
