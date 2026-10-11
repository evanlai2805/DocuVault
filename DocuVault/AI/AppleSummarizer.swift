import Foundation
import DocuVaultCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why the on-device model cannot run right now. Shown on the summary card with a fix.
enum SummarizerAvailability: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceOff
    case modelDownloading
    case unknown(String)

    var message: String {
        switch self {
        case .available: "Ready"
        case .deviceNotEligible: "This device cannot run Apple's on-device model."
        case .appleIntelligenceOff: "Apple Intelligence is off. Turn it on in Settings → Apple Intelligence & Siri."
        case .modelDownloading: "The on-device model is still downloading. Try again in a few minutes."
        case .unknown(let s): s
        }
    }
}

/// Apple Foundation Models backend. One session per call; structured output via @Generable.
enum AppleSummarizer {

    static var availability: SummarizerAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
            case .modelNotReady: return .modelDownloading
            @unknown default: return .unknown("Model unavailable")
            }
        }
        #else
        return .unknown("Foundation Models framework not in this SDK")
        #endif
    }

    #if canImport(FoundationModels)
    @Generable
    enum FormatOut: String { case bullets, paragraph, unsure }

    @Generable
    struct FactOut {
        @Guide(description: "Short label, e.g. Party A, Deadline, Amount, Governing law")
        var label: String
        @Guide(description: "The value copied exactly from the text")
        var value: String
    }

    @Generable
    struct SummaryOut {
        @Guide(description: "Headline: at most 12 words, or 20 Chinese characters. Not a sentence starting with 'Summary'.")
        var headline: String
        @Guide(description: "bullets or paragraph; unsure only if the document really fits neither")
        var format: FormatOut
        @Guide(description: "Body as bullet points or paragraph sentences, one per element")
        var body: [String]
        @Guide(description: "Key facts found in the text. Omit anything not in the text.")
        var keyFacts: [FactOut]
        @Guide(description: "Up to 4 actions the reader must take, each with a date when the text gives one")
        var actions: [String]
    }
    #endif

    /// One model pass over one text (whole document or one chunk).
    static func pass(text: String, language: String, format: DocumentSummary.Format, length: DocumentSummary.Length,
                     chunk: (index: Int, total: Int)? = nil) async throws -> DocumentSummary {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: SummarySpec.instructions(language: language, format: format, length: length))
        let response = try await session.respond(to: SummarySpec.prompt(text: text, language: language, chunk: chunk), generating: SummaryOut.self)
        let out = response.content
        let fmt: DocumentSummary.Format = switch out.format { case .bullets: .bullets; case .paragraph: .paragraph; case .unsure: .unsure }
        return DocumentSummary(language: language, headline: out.headline, format: fmt,
                               body: Array(out.body.prefix(length == .short ? 6 : 12)),
                               keyFacts: out.keyFacts.map { .init(label: $0.label, value: $0.value) },
                               actions: Array(out.actions.prefix(4)), length: length)
        #else
        throw SummarizerError.unavailable(.unknown("Foundation Models framework not in this SDK"))
        #endif
    }

    /// Reduce chunk summaries into one.
    static func reduce(partials: [DocumentSummary], language: String, format: DocumentSummary.Format, length: DocumentSummary.Length) async throws -> DocumentSummary {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: SummarySpec.instructions(language: language, format: format, length: length))
        let response = try await session.respond(to: SummarySpec.reducePrompt(partials: partials, language: language), generating: SummaryOut.self)
        let out = response.content
        let fmt: DocumentSummary.Format = switch out.format { case .bullets: .bullets; case .paragraph: .paragraph; case .unsure: .unsure }
        return DocumentSummary(language: language, headline: out.headline, format: fmt,
                               body: Array(out.body.prefix(length == .short ? 6 : 12)),
                               keyFacts: out.keyFacts.map { .init(label: $0.label, value: $0.value) },
                               actions: Array(out.actions.prefix(4)), length: length)
        #else
        throw SummarizerError.unavailable(.unknown("Foundation Models framework not in this SDK"))
        #endif
    }
}

enum SummarizerError: Error {
    case unavailable(SummarizerAvailability)
    case empty
}
