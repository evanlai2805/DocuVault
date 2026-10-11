import Foundation
import SwiftData
import DocuVaultCore

/// Cloud sends to Claude (Phase 7). Opt-in per document, approved per send on `CloudApprovalView`.
/// The only path to the network is `send(_:options:excluded:context:)`, and it is only reachable from that sheet.
/// `CloudGate` decides, in code, which documents can ever be offered.
@MainActor @Observable
final class CloudService {
    static let shared = CloudService()

    private let defaults = UserDefaults.standard

    var modelID: String {
        get { defaults.string(forKey: "cloud.model") ?? CloudCost.defaultModelID }
        set { defaults.set(newValue, forKey: "cloud.model") }
    }
    /// Keep the exact redacted text in the log so you can audit what left (checkpoint 10 Q5).
    var keepSentText: Bool {
        get { defaults.object(forKey: "cloud.keepText") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cloud.keepText") }
    }
    var logRetentionDays: Int {
        get { defaults.object(forKey: "cloud.logDays") as? Int ?? 90 }
        set { defaults.set(newValue, forKey: "cloud.logDays") }
    }
    private(set) var hasKey: Bool = false
    private(set) var maskedKey: String = ""
    /// Answers from "Ask Claude", kept for the session only.
    private(set) var answers: [UUID: [(question: String, answer: String)]] = [:]

    /// Cap on what one send may carry. Claude's window is far larger; this bounds cost and the preview.
    static let maxCharacters = 120_000

    init() { refreshKey() }

    func refreshKey() {
        let k = ClaudeKeychain.load()
        hasKey = !(k ?? "").isEmpty
        maskedKey = k.map(ClaudeKeychain.masked) ?? ""
    }
    func setKey(_ key: String) { ClaudeKeychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); refreshKey() }
    func deleteKey() { ClaudeKeychain.delete(); refreshKey() }

    // MARK: Offer

    /// May this document be offered a cloud action right now? Key present and the gate allows it.
    func canOffer(_ doc: StoredDocument) -> Bool {
        hasKey && CloudGate.allows(type: doc.type, sensitive: doc.sensitive, hasSealedContent: doc.sealedText != nil || doc.fields.contains { $0.isSealed })
    }

    /// Everything the approval sheet needs. Nil when the gate refuses.
    struct Draft: Identifiable {
        let id = UUID()
        let doc: StoredDocument
        let text: String
        let purpose: CloudPurpose
        let spans: [Redactor.Span]
    }

    func draft(_ doc: StoredDocument, text: String, purpose: CloudPurpose) -> Draft? {
        guard canOffer(doc) else { return nil }
        let clipped = text.count > Self.maxCharacters ? String(text.prefix(Self.maxCharacters)) : text
        // Known names: extracted name-like fields and the vault's people. Both must be redacted wherever they appear.
        var known = doc.fields.filter { !$0.isSealed && ["name", "fullName", "surname", "givenNames", "partyA", "partyB", "company", "counterparty", "from", "to", "sender", "recipient"].contains($0.key) }.map(\.value)
        // People in the vault (family, clients, partners) never travel in clear, whichever document mentions them.
        if let ctx = doc.modelContext, let people = try? ctx.fetch(FetchDescriptor<StoredPerson>()) {
            known += people.flatMap { [$0.name, $0.fullName] }
        }
        return Draft(doc: doc, text: clipped, purpose: purpose, spans: Redactor.findSpans(in: clipped, extraNames: known))
    }

    // MARK: Send

    enum Outcome { case summary(DocumentSummary), answer(String) }

    /// Perform one approved send. Logs the row whatever happens. Throws `ClaudeClient.Failure` on error.
    func send(_ d: Draft, options: Redactor.Options, excluded: Set<Int>, context: ModelContext) async throws -> Outcome {
        guard canOffer(d.doc) else { throw ClaudeClient.Failure.http(0, "This document cannot be sent.") }
        guard let key = ClaudeKeychain.load(), !key.isEmpty else { throw ClaudeClient.Failure.noKey }
        let spans = d.spans.enumerated().filter { !excluded.contains($0.offset) || $0.element.category.isLocked }.map(\.element)
        let red = Redactor.apply(d.text, spans: spans, options: options)
        let lang = d.purpose.language
        let request = Self.request(purpose: d.purpose, redactedText: red.text, model: modelID)
        let inTokens = CloudCost.estimatedTokens(for: request.system + request.user)
        let row = StoredCloudSend(documentID: d.doc.id, documentTitle: d.doc.title, purpose: d.purpose.logLabel, model: modelID,
                                  status: .failed, characters: red.text.count, redactedCount: red.count,
                                  redactionSummary: Self.describe(red.counts), inputTokens: inTokens,
                                  estimatedUSD: CloudCost.estimateUSD(inputTokens: inTokens, outputTokens: 400, model: modelID),
                                  sentText: keepSentText ? red.text : nil)
        context.insert(row)
        try? context.save()
        let start = Date()
        do {
            let resp = try await ClaudeClient.send(request, apiKey: key)
            row.inputTokens = resp.inputTokens
            row.outputTokens = resp.outputTokens
            row.estimatedUSD = CloudCost.estimateUSD(inputTokens: resp.inputTokens, outputTokens: resp.outputTokens, model: modelID)
            switch d.purpose {
            case .summarise(let fmt, let length, _):
                guard var s = SummaryJSON.parse(resp.text, language: lang) else { throw ClaudeClient.Failure.badReply }
                let restored = Redactor.restore(s, map: red.map)
                s = restored.summary
                s.keyFacts = SummarySpec.grounded(s.keyFacts, in: d.text)
                s.language = lang
                s.length = length
                if s.format == .unsure, fmt != .unsure { s.format = fmt }
                s.model = "claude"
                s.chunks = 1
                s.seconds = Date().timeIntervalSince(start)
                s.generatedAt = Date()
                s.redacted = red.count
                s.unresolved = restored.unresolved
                s.sentCharacters = red.text.count
                d.doc.summaryJSON = try JSONEncoder().encode(s)
                row.status = .ok
                try? context.save()
                if ExportManager.shared.syncFolder { ExportManager.shared.exportAll(context: context, vaultKey: nil) }
                return .summary(s)
            case .ask(let q, _):
                let (text, _) = Redactor.restore(resp.text, map: red.map)
                row.status = .ok
                try? context.save()
                answers[d.doc.id, default: []].append((q, text))
                return .answer(text)
            }
        } catch {
            row.status = .failed
            row.error = error.localizedDescription
            try? context.save()
            throw error
        }
    }

    /// You cancelled on the sheet: nothing left the phone, but the log says so.
    func logCancelled(_ d: Draft, context: ModelContext) {
        let row = StoredCloudSend(documentID: d.doc.id, documentTitle: d.doc.title, purpose: d.purpose.logLabel, model: modelID,
                                  status: .cancelled, characters: 0, redactedCount: 0, redactionSummary: "nothing sent")
        context.insert(row)
        try? context.save()
    }

    /// Drop log rows past retention. Called on foreground.
    func prune(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -logRetentionDays, to: Date()) ?? Date()
        let old = (try? context.fetch(FetchDescriptor<StoredCloudSend>(predicate: #Predicate { $0.sentAt < cutoff }))) ?? []
        guard !old.isEmpty else { return }
        for r in old { context.delete(r) }
        try? context.save()
    }

    // MARK: Prompts

    static func request(purpose: CloudPurpose, redactedText: String, model: String) -> ClaudeClient.Request {
        let lang = purpose.language
        switch purpose {
        case .summarise(let fmt, let length, _):
            let system = [SummarySpec.instructions(language: lang, format: fmt, length: length),
                          Redactor.placeholderRule(language: lang),
                          SummaryJSON.schemaHint,
                          lang == "zh-Hans" ? "只输出 JSON，不要其他文字。" : "Reply with the JSON object only. No prose before or after."].joined(separator: "\n\n")
            return ClaudeClient.Request(model: model, system: system, user: SummarySpec.prompt(text: redactedText, language: lang), maxTokens: 1500)
        case .ask(let q, _):
            let system = lang == "zh-Hans"
                ? "你为一位金融重组分析师解答关于一份文件的问题。只用简体中文作答。只依据文件内容；文件没有写明的，就说明没有写明。回答简洁。\n\n" + Redactor.placeholderRule(language: lang)
                : "You answer questions about one document for a finance and restructuring analyst. Answer only in English. Use only the document; if it does not say, say that it does not say. Be brief.\n" + SummarySpec.steRule + "\n\n" + Redactor.placeholderRule(language: lang)
            let user = "<document>\n" + redactedText + "\n</document>\n\n" + (lang == "zh-Hans" ? "问题：" : "Question: ") + q
            return ClaudeClient.Request(model: model, system: system, user: user, maxTokens: 1000)
        }
    }

    static func describe(_ counts: [Redactor.Category: Int]) -> String {
        let order: [Redactor.Category] = [.name, .amount, .identifier, .contact, .date]
        let parts = order.compactMap { c -> String? in
            guard let n = counts[c], n > 0 else { return nil }
            switch c {
            case .name: return "\(n) name\(n == 1 ? "" : "s")"
            case .amount: return "\(n) amount\(n == 1 ? "" : "s")"
            case .identifier: return "\(n) ID\(n == 1 ? "" : "s")"
            case .contact: return "\(n) contact\(n == 1 ? "" : "s")"
            case .date: return "\(n) date\(n == 1 ? "" : "s")"
            }
        }
        return parts.isEmpty ? "nothing redacted" : parts.joined(separator: " · ")
    }
}
