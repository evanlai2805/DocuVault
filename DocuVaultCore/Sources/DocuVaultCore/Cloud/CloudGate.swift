import Foundation

/// Which documents may ever be offered a cloud send. Code, not prompt (checkpoint 10).
public enum CloudGate {
    /// False for vault documents, identity and payment types, receipts, business cards, and anything sealed.
    public static func allows(type: DocumentType, sensitive: Bool, hasSealedContent: Bool) -> Bool {
        if sensitive || hasSealedContent { return false }
        if type.isSensitiveByDefault { return false }
        switch type {
        case .receipt, .businessCard, .bankCard, .passport, .nric, .chinaID: return false
        case .contract, .letter, .other: return true
        }
    }

    /// Why a document is not offered. For the banner on the detail screen.
    public static func reason(type: DocumentType, sensitive: Bool) -> String {
        if sensitive { return "Vault documents never leave this phone." }
        if !allows(type: type, sensitive: false, hasSealedContent: false) { return "\(type.displayName) documents never leave this phone." }
        return ""
    }
}

/// What one send is for. The purpose shapes the prompt and the log line.
public enum CloudPurpose: Equatable, Sendable, Codable {
    case summarise(format: DocumentSummary.Format, length: DocumentSummary.Length, language: String)
    case ask(question: String, language: String)

    public var logLabel: String {
        switch self {
        case .summarise: "summarise"
        case .ask(let q, _): "ask: \u{201C}\(q.count > 40 ? String(q.prefix(40)) + "…" : q)\u{201D}"
        }
    }
    public var language: String {
        switch self {
        case .summarise(_, _, let l), .ask(_, let l): l
        }
    }
}

/// Rough token and price estimate shown on the approval sheet. Figures are estimates, not a bill.
public enum CloudCost {
    public struct Model: Equatable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        /// USD per million tokens.
        public let inputPerM: Double
        public let outputPerM: Double
    }

    /// Prices are the published list prices at the time of writing; adjust in one place if they move.
    public static let models: [Model] = [
        Model(id: "claude-sonnet-5-5", displayName: "Sonnet 5.5", inputPerM: 3, outputPerM: 15),
        Model(id: "claude-haiku-5-5", displayName: "Haiku 5.5", inputPerM: 1, outputPerM: 5),
        Model(id: "claude-opus-5-5", displayName: "Opus 5.5", inputPerM: 15, outputPerM: 75),
    ]
    public static let defaultModelID = "claude-sonnet-5-5"
    public static func model(_ id: String) -> Model { models.first { $0.id == id } ?? models[0] }

    /// Characters → tokens. English ≈ 4 chars per token; Chinese ≈ 1.3 tokens per character.
    public static func estimatedTokens(for text: String) -> Int {
        let cjk = TextRules.cjkRatio(text)
        let chars = Double(text.count)
        let tokens = chars * cjk * 1.3 + chars * (1 - cjk) / 4
        return Int(tokens.rounded())
    }

    /// Estimated USD for a send: input tokens plus a typical output.
    public static func estimateUSD(inputTokens: Int, outputTokens: Int, model id: String) -> Double {
        let m = model(id)
        return Double(inputTokens) / 1_000_000 * m.inputPerM + Double(outputTokens) / 1_000_000 * m.outputPerM
    }

    public static func formatUSD(_ usd: Double) -> String {
        usd < 0.005 ? "< US$0.01" : String(format: "US$%.2f", usd)
    }
}
