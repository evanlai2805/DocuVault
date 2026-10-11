import Foundation
import DocuVaultCore
#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
#endif

/// Qwen3 via MLX. Same contract as the Apple backend; output is JSON parsed by `SummaryJSON`.
enum MLXSummarizer {

    static func pass(text: String, language: String, format: DocumentSummary.Format, length: DocumentSummary.Length,
                     chunk: (index: Int, total: Int)? = nil) async throws -> DocumentSummary {
        try await run(instructions: SummarySpec.instructions(language: language, format: format, length: length),
                      prompt: SummarySpec.prompt(text: text, language: language, chunk: chunk), language: language)
    }

    static func reduce(partials: [DocumentSummary], language: String, format: DocumentSummary.Format, length: DocumentSummary.Length) async throws -> DocumentSummary {
        try await run(instructions: SummarySpec.instructions(language: language, format: format, length: length),
                      prompt: SummarySpec.reducePrompt(partials: partials, language: language), language: language)
    }

    private static func run(instructions: String, prompt: String, language: String) async throws -> DocumentSummary {
        #if canImport(MLXLLM)
        let container = try await LocalModelManager.shared.load()
        // "/no_think" switches Qwen3 out of its reasoning mode; the JSON hint pins the shape.
        let system = instructions + "\n\n" + SummaryJSON.schemaHint + "\n/no_think"
        let session = ChatSession(container, instructions: system,
                                  generateParameters: GenerateParameters(maxTokens: 900, temperature: 0.2))
        let reply = try await session.respond(to: prompt)
        guard let parsed = SummaryJSON.parse(reply, language: language) else { throw SummarizerError.empty }
        return parsed
        #else
        throw SummarizerError.unavailable(.unknown("MLX not in this build"))
        #endif
    }
}
