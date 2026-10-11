import Foundation
import SwiftData
import DocuVaultCore

/// Orchestrates a summary: language → chunks → map/reduce → grounding → store. One in flight per document.
@MainActor @Observable
final class SummaryService {
    static let shared = SummaryService()

    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case failed(String)
    }
    private(set) var states: [UUID: State] = [:]

    private let defaults = UserDefaults.standard

    func state(for doc: StoredDocument) -> State { states[doc.id] ?? .idle }

    /// Remembered format per document type (checkpoint 9 Q2: remember per type).
    func preferredFormat(for type: DocumentType) -> DocumentSummary.Format? {
        defaults.string(forKey: "summary.format.\(type.rawValue)").flatMap(DocumentSummary.Format.init(rawValue:))
    }
    func setPreferredFormat(_ f: DocumentSummary.Format?, for type: DocumentType) {
        if let f { defaults.set(f.rawValue, forKey: "summary.format.\(type.rawValue)") } else { defaults.removeObject(forKey: "summary.format.\(type.rawValue)") }
    }

    func summary(for doc: StoredDocument) -> DocumentSummary? {
        guard let data = doc.summaryJSON else { return nil }
        return try? JSONDecoder().decode(DocumentSummary.self, from: data)
    }

    /// Run or re-run. `format` nil = type default or remembered preference. `language` nil = detected.
    func summarise(_ doc: StoredDocument, text: String, format: DocumentSummary.Format? = nil,
                   length: DocumentSummary.Length = .short, language: String? = nil, context: ModelContext) async {
        guard SummarySpec.supportsSummary(doc.type) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { states[doc.id] = .failed("No text to summarise."); return }
        let avail = AppleSummarizer.availability
        guard avail == .available else { states[doc.id] = .failed(avail.message); return }

        let lang = language ?? SummarySpec.language(for: text)
        let fmt = format ?? preferredFormat(for: doc.type) ?? SummarySpec.defaultFormat(for: doc.type)
        let start = Date()
        var chunks = SummarySpec.chunks(text, language: lang)
        var partial = false
        if chunks.count > SummarySpec.maxChunks { chunks = Array(chunks.prefix(SummarySpec.maxChunks)); partial = true }
        states[doc.id] = .running(done: 0, total: chunks.count)

        do {
            var result: DocumentSummary
            if chunks.count == 1 {
                result = try await AppleSummarizer.pass(text: chunks[0], language: lang, format: fmt, length: length)
            } else {
                var partials: [DocumentSummary] = []
                for (i, c) in chunks.enumerated() {
                    partials.append(try await AppleSummarizer.pass(text: c, language: lang, format: .bullets, length: .short, chunk: (i, chunks.count)))
                    states[doc.id] = .running(done: i + 1, total: chunks.count)
                }
                result = try await AppleSummarizer.reduce(partials: partials, language: lang, format: fmt, length: length)
                result.keyFacts = SummarySpec.mergeFacts([result.keyFacts] + partials.map(\.keyFacts))
            }
            // Ground every key fact in the source; drop the rest. The model never gets to invent a number.
            result.keyFacts = SummarySpec.grounded(result.keyFacts, in: text)
            result.chunks = chunks.count
            result.partial = partial
            result.model = "apple"
            result.seconds = Date().timeIntervalSince(start)
            result.generatedAt = Date()
            if result.format == .unsure, fmt != .unsure { result.format = fmt }
            doc.summaryJSON = try JSONEncoder().encode(result)
            try context.save()
            states[doc.id] = .idle
            if ExportManager.shared.syncFolder { ExportManager.shared.exportAll(context: context, vaultKey: nil) }
        } catch SummarizerError.unavailable(let a) {
            states[doc.id] = .failed(a.message)
        } catch {
            states[doc.id] = .failed("The model could not summarise this document. \(error.localizedDescription)")
        }
    }

    func clear(_ doc: StoredDocument, context: ModelContext) {
        doc.summaryJSON = nil
        try? context.save()
        states[doc.id] = .idle
    }
}
