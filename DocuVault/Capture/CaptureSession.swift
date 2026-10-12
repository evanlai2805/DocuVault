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

    /// Batch import (Evan, 12 Oct): one document per image. Documents waiting their turn live here;
    /// `pages` is always the document being worked on.
    var queue: [[DraftPage]] = []
    private(set) var batchDone = 0

    var hasPages: Bool { !pages.isEmpty }
    var batchTotal: Int { batchDone + (pages.isEmpty ? 0 : 1) + queue.count }
    var batchPosition: Int { batchDone + 1 }
    var isBatch: Bool { batchTotal > 1 }
    var remainingAfterThis: Int { queue.count }

    func reset() {
        pages = []
        queue = []
        batchDone = 0
        isRunningOCR = false
        verdict = nil
        chosenType = .other
        extraction = nil
    }

    /// Current document is saved or skipped. Moves the next one in. Returns false when the batch is finished.
    @discardableResult
    func advance() -> Bool {
        batchDone += 1
        verdict = nil
        chosenType = .other
        extraction = nil
        guard !queue.isEmpty else { reset(); return false }
        pages = queue.removeFirst()
        return true
    }

    /// Add one document to the batch: becomes current when nothing is open, otherwise waits in the queue.
    func addDocument(_ newPages: [DraftPage], source: CaptureSource) {
        guard !newPages.isEmpty else { return }
        self.source = source
        if pages.isEmpty { pages = newPages } else { queue.append(newPages) }
    }

    /// Photos and Files: each image is its own document.
    func addSeparate(_ images: [CGImage], source: CaptureSource) {
        for img in images { addDocument([DraftPage(original: img)], source: source) }
    }

    /// Pull the next queued document's pages into this one (a two-page letter photographed twice).
    func mergeNextIntoCurrent() {
        guard !queue.isEmpty else { return }
        pages.append(contentsOf: queue.removeFirst())
    }

    /// Push one page out into its own document, next in the queue.
    func splitOff(_ id: DraftPage.ID) {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let p = pages.remove(at: i)
        queue.insert([p], at: 0)
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

    /// One PDF = one document.
    func addPDF(_ imported: [PDFImporter.ImportedPage]) {
        addDocument(imported.map { p in
            var d = DraftPage(original: p.image)
            d.embeddedText = p.embeddedText
            if let t = p.embeddedText { d.ocr = .embedded(t) }
            return d
        }, source: .pdf)
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

    /// Run OCR on every queued page: the current document first, then the rest of the batch.
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
        for d in queue.indices {
            for i in queue[d].indices {
                guard case .queued = queue[d][i].ocr else { continue }
                queue[d][i].ocr = .running
                let img = queue[d][i].processed()
                do {
                    let page = try await OCREngine.shared.recognize(img, mode: .auto)
                    queue[d][i].ocr = .done(page)
                } catch {
                    queue[d][i].ocr = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Make the current document ready for review: wait for any OCR in flight, read it if needed, then classify.
    func prepareCurrent() async {
        while isRunningOCR { try? await Task.sleep(for: .milliseconds(150)) }
        if !ocrComplete { await runOCR() }
        classifyAndExtract()
    }

    /// Pages read so far across the whole batch, for the progress label.
    var ocrProgress: (done: Int, total: Int) {
        let all = pages + queue.flatMap { $0 }
        let done = all.filter { if case .queued = $0.ocr { return false }; if case .running = $0.ocr { return false }; return true }.count
        return (done, all.count)
    }

    var allTextLines: [String] {
        pages.flatMap { $0.text.components(separatedBy: "\n") }
    }

    var fullText: String { pages.map(\.text).joined(separator: "\n\n") }

    var detectedLanguage: String { TextRules.detectLanguage(fullText).rawValue }

    /// Title from the text header; identity, card and receipt types use their key fields instead
    /// ("Passport · CHAI", "Visa •4417", "NTUC FairPrice · 2026-10-10").
    var guessedTitle: String {
        func v(_ k: String) -> String? { extraction?.fields.first { $0.key == k && !$0.value.isEmpty }?.value }
        switch chosenType {
        case .passport, .nric, .chinaID:
            if let n = v("surname") ?? v("name") { return "\(chosenType.displayName) · \(n)" }
        case .bankCard:
            let brand = v("brand") ?? v("issuer") ?? "Card"
            if let l4 = v("last4") ?? v("cardLast4") { return "\(brand) •\(l4)" }
            return brand
        case .receipt:
            if let m = v("merchant") { return v("date").map { "\(m) · \($0)" } ?? m }
        case .businessCard:
            if let n = v("name") { return v("company").map { "\(n) · \($0)" } ?? n }
        default: break
        }
        return TitleGuesser.guess(from: allTextLines)
    }

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
