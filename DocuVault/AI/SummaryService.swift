import Foundation
import SwiftData
import DocuVaultCore

/// Orchestrates a summary: language → chunks → map/reduce → grounding → store. One in flight per document.
@MainActor @Observable
final class SummaryService {
    static let shared = SummaryService()

    enum State: Equatable {
        case idle
        case askLanguage                 // mixed-language document: user picks 中文 or English (Evan, checkpoint 9 Q3)
        case running(done: Int, total: Int)
        case failed(String)
    }

    /// Auto-summarise contracts and letters on save (checkpoint 9 Q1).
    var autoSummarise: Bool {
        get { UserDefaults.standard.object(forKey: "summary.auto") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "summary.auto") }
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

        // Mixed-language document and no explicit choice: ask once.
        if language == nil, SummarySpec.isMixed(text) { states[doc.id] = .askLanguage; return }
        let lang = language ?? SummarySpec.language(for: text)

        // Backend: Qwen for Chinese when installed and enabled; Apple otherwise. Apple is the fallback if Qwen fails.
        let useMLX = lang == "zh-Hans" && LocalModelManager.shared.canServeChinese
        if !useMLX {
            let avail = AppleSummarizer.availability
            guard avail == .available else { states[doc.id] = .failed(avail.message); return }
        }
        let fmt = format ?? preferredFormat(for: doc.type) ?? SummarySpec.defaultFormat(for: doc.type)
        let start = Date()
        var chunks = SummarySpec.chunks(text, language: lang)
        var partial = false
        if chunks.count > SummarySpec.maxChunks { chunks = Array(chunks.prefix(SummarySpec.maxChunks)); partial = true }
        states[doc.id] = .running(done: 0, total: chunks.count)

        do {
            var result: DocumentSummary
            do {
                result = try await generate(chunks: chunks, lang: lang, fmt: fmt, length: length, mlx: useMLX, docID: doc.id)
            } catch where useMLX {
                // Qwen failed (memory, bad JSON, load error): fall back to Apple silently, note it on the card.
                guard AppleSummarizer.availability == .available else { throw error }
                result = try await generate(chunks: chunks, lang: lang, fmt: fmt, length: length, mlx: false, docID: doc.id)
                result.model = "apple (qwen failed)"
            }
            // Ground every key fact in the source; drop the rest. The model never gets to invent a number.
            result.keyFacts = SummarySpec.grounded(result.keyFacts, in: text)
            result.chunks = chunks.count
            result.partial = partial
            if result.model.isEmpty { result.model = useMLX ? "mlx" : "apple" }
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

    private func generate(chunks: [String], lang: String, fmt: DocumentSummary.Format, length: DocumentSummary.Length,
                          mlx: Bool, docID: UUID) async throws -> DocumentSummary {
        func pass(_ t: String, _ f: DocumentSummary.Format, _ l: DocumentSummary.Length, _ c: (Int, Int)?) async throws -> DocumentSummary {
            mlx ? try await MLXSummarizer.pass(text: t, language: lang, format: f, length: l, chunk: c)
                : try await AppleSummarizer.pass(text: t, language: lang, format: f, length: l, chunk: c)
        }
        if chunks.count == 1 {
            var r = try await pass(chunks[0], fmt, length, nil)
            r.model = mlx ? "mlx" : "apple"
            return r
        }
        var partials: [DocumentSummary] = []
        for (i, c) in chunks.enumerated() {
            partials.append(try await pass(c, .bullets, .short, (i, chunks.count)))
            states[docID] = .running(done: i + 1, total: chunks.count)
        }
        var result = mlx ? try await MLXSummarizer.reduce(partials: partials, language: lang, format: fmt, length: length)
                         : try await AppleSummarizer.reduce(partials: partials, language: lang, format: fmt, length: length)
        result.keyFacts = SummarySpec.mergeFacts([result.keyFacts] + partials.map(\.keyFacts))
        result.model = mlx ? "mlx" : "apple"
        return result
    }

    func clear(_ doc: StoredDocument, context: ModelContext) {
        doc.summaryJSON = nil
        try? context.save()
        states[doc.id] = .idle
    }
}
