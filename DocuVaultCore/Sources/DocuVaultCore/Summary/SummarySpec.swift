import Foundation

/// The summary contract from checkpoint 9. Language and format defaults are decided in code;
/// the model fills the content; code grounds key facts back to the source text.
public struct DocumentSummary: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable { case bullets, paragraph, both, unsure }
    public enum Length: String, Codable, Sendable { case short, long }
    public struct Fact: Codable, Equatable, Sendable {
        public var label: String
        public var value: String
        public init(label: String, value: String) { self.label = label; self.value = value }
    }

    public var language: String          // "en" | "zh-Hans"
    public var headline: String
    public var format: Format
    public var body: [String]            // bullets, or paragraph sentences joined by the view
    public var keyFacts: [Fact]
    public var actions: [String]
    public var length: Length
    public var chunks: Int               // 1 = single pass; >1 = map-reduce
    public var partial: Bool             // true when the chunk cap was hit
    public var model: String             // "apple" | "mlx" | "claude"
    public var generatedAt: Date
    public var seconds: Double
    /// Cloud sends only (Phase 7): placeholders swapped before sending, and how many came back unresolved.
    public var redacted: Int?
    public var unresolved: Int?
    public var sentCharacters: Int?

    public init(language: String, headline: String, format: Format, body: [String], keyFacts: [Fact], actions: [String],
                length: Length = .short, chunks: Int = 1, partial: Bool = false, model: String = "apple",
                generatedAt: Date = Date(), seconds: Double = 0) {
        self.language = language; self.headline = headline; self.format = format; self.body = body; self.keyFacts = keyFacts
        self.actions = actions; self.length = length; self.chunks = chunks; self.partial = partial; self.model = model
        self.generatedAt = generatedAt; self.seconds = seconds
    }

    /// Plain Markdown for export and sharing.
    public var markdown: String {
        var out = ["## Summary", "", "**\(headline)**", ""]
        switch format {
        case .paragraph: out.append(body.joined(separator: " "))
        default: out.append(contentsOf: body.map { "- \($0)" })
        }
        if !keyFacts.isEmpty {
            out.append(""); out.append(language == "zh-Hans" ? "### 要点" : "### Key facts")
            out.append(contentsOf: keyFacts.map { "- \($0.label): \($0.value)" })
        }
        if !actions.isEmpty {
            out.append(""); out.append(language == "zh-Hans" ? "### 待办" : "### Actions")
            out.append(contentsOf: actions.map { "- [ ] \($0)" })
        }
        return out.joined(separator: "\n")
    }
}

public enum SummarySpec {

    /// Types that get fields, not summaries.
    public static func supportsSummary(_ t: DocumentType) -> Bool {
        switch t { case .receipt, .bankCard, .passport, .nric, .chinaID, .businessCard: false; default: true }
    }

    /// Code decides the language. ≥ 60% CJK → Chinese. ≤ 10% → English. Between: dominant script.
    public static func language(for text: String) -> String {
        TextRules.cjkRatio(text) >= 0.5 ? "zh-Hans" : "en"
    }

    public static func isMixed(_ text: String) -> Bool {
        let r = TextRules.cjkRatio(text); return r > 0.10 && r < 0.60
    }

    /// Format default by type. `.unsure` means "let the model decide; if it is unsure too, ask the user".
    public static func defaultFormat(for t: DocumentType) -> DocumentSummary.Format {
        switch t { case .contract: .bullets; case .letter: .paragraph; default: .unsure }
    }

    // MARK: Prompts

    public static let groundingRule = "Use only the text. If a fact is absent, omit it. Do not guess. Every key fact value must be copied exactly from the text."

    public static let steRule = """
    Write in simplified technical English: one idea per sentence; sentences under 20 words; active voice; \
    one term per concept; keep normal finance and legal vocabulary.
    """

    /// System instructions for the on-device model. English output follows STE; Chinese output keeps a conventional register.
    public static func instructions(language: String, format: DocumentSummary.Format, length: DocumentSummary.Length) -> String {
        var parts: [String] = []
        if language == "zh-Hans" {
            parts.append("你是文件摘要助手。只用简体中文作答。语气正式、简洁。")
            parts.append("仅使用原文内容。原文没有的信息一律省略，不要猜测。关键信息的值必须逐字来自原文。")
        } else {
            parts.append("You summarise documents for a finance and restructuring analyst. Answer only in English.")
            parts.append(steRule)
            parts.append(groundingRule)
        }
        switch format {
        case .bullets: parts.append(language == "zh-Hans" ? "正文用要点列表。" : "Write the body as bullet points.")
        case .paragraph: parts.append(language == "zh-Hans" ? "正文用一段话。" : "Write the body as one paragraph of sentences.")
        case .both: parts.append(language == "zh-Hans" ? "先一段话，再列要点。" : "Write one short paragraph, then bullet points.")
        case .unsure: parts.append(language == "zh-Hans" ? "根据文件性质选择要点或段落；若拿不准，format 填 unsure。" : "Choose bullets or a paragraph to suit the document; if unsure, set format to unsure.")
        }
        switch length {
        case .short: parts.append(language == "zh-Hans" ? "正文不超过5条要点或80字。" : "Body: 3 to 5 bullets, or at most 80 words.")
        case .long: parts.append(language == "zh-Hans" ? "正文6到10条要点或不超过200字。" : "Body: 6 to 10 bullets, or at most 200 words.")
        }
        parts.append(language == "zh-Hans" ? "标题不超过20个字。待办最多4条，有日期的写明日期。" : "Headline at most 12 words. Up to 4 actions, each with a date when the text gives one.")
        return parts.joined(separator: "\n")
    }

    /// Prompt for one pass or one chunk.
    public static func prompt(text: String, language: String, chunk: (index: Int, total: Int)? = nil) -> String {
        var head = language == "zh-Hans" ? "请总结以下文件。" : "Summarise the following document."
        if let c = chunk, c.total > 1 {
            head = language == "zh-Hans" ? "这是文件第\(c.index + 1)/\(c.total)部分，请总结这一部分。" : "This is part \(c.index + 1) of \(c.total). Summarise this part only."
        }
        return head + "\n\n<document>\n" + text + "\n</document>"
    }

    /// Reduce prompt: combine chunk summaries into one.
    public static func reducePrompt(partials: [DocumentSummary], language: String) -> String {
        let joined = partials.enumerated().map { i, p in
            "Part \(i + 1): \(p.headline)\n" + p.body.map { "- \($0)" }.joined(separator: "\n") +
            (p.keyFacts.isEmpty ? "" : "\nFacts: " + p.keyFacts.map { "\($0.label)=\($0.value)" }.joined(separator: "; "))
        }.joined(separator: "\n\n")
        let head = language == "zh-Hans" ? "以下是同一文件各部分的摘要。请合并为一份完整摘要，去重，保留所有关键信息。" :
            "Below are summaries of parts of one document. Merge them into one summary. Remove duplicates. Keep every key fact."
        return head + "\n\n" + joined
    }

    // MARK: Chunking

    /// Max characters per chunk. Apple's on-device window is about 4k tokens; Chinese characters cost more tokens each.
    public static func chunkLimit(language: String) -> Int { language == "zh-Hans" ? 2000 : 3500 }
    public static let maxChunks = 40

    /// Split on paragraph boundaries. A numbered clause (第X条, 1., (a), Article N) always starts a new paragraph.
    /// Never splits inside a table row (lines containing "|").
    public static func chunks(_ text: String, language: String) -> [String] {
        let limit = chunkLimit(language: language)
        let paragraphs = paragraphize(text)
        var out: [String] = []
        var current = ""
        for p in paragraphs {
            if current.isEmpty { current = p; continue }
            if current.count + 1 + p.count <= limit { current += "\n" + p }
            else { out.append(current); current = p }
        }
        if !current.isEmpty { out.append(current) }
        // A single paragraph longer than the limit is split on sentence ends as a last resort.
        return out.flatMap { $0.count <= limit ? [$0] : hardSplit($0, limit: limit) }
    }

    static func paragraphize(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var paras: [String] = []
        var cur: [String] = []
        let clauseStart = try! NSRegularExpression(pattern: #"^\s*(第[一二三四五六七八九十百\d]+条|Article\s+\d+|Clause\s+\d+|\d+\.\s|\(\w\)\s|[一二三四五六七八九十]+、)"#)
        func flush() { if !cur.isEmpty { paras.append(cur.joined(separator: "\n")); cur = [] } }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flush(); continue }
            let isClause = clauseStart.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil
            if isClause && !cur.isEmpty && !cur.last!.contains("|") { flush() }
            cur.append(t)
        }
        flush()
        return paras
    }

    static func hardSplit(_ s: String, limit: Int) -> [String] {
        var out: [String] = []
        var cur = ""
        for sentence in s.split(whereSeparator: { "。.!?！？\n".contains($0) }).map({ String($0).trimmingCharacters(in: .whitespaces) }) where !sentence.isEmpty {
            if cur.count + sentence.count + 1 > limit && !cur.isEmpty { out.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : " ") + sentence
            while cur.count > limit { out.append(String(cur.prefix(limit))); cur = String(cur.dropFirst(limit)) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // MARK: Grounding

    /// Keep only key facts whose value appears in the source (ignoring spaces, commas and case). Drops invented facts.
    public static func grounded(_ facts: [DocumentSummary.Fact], in source: String) -> [DocumentSummary.Fact] {
        let norm = normalise(source)
        return facts.filter { f in
            let v = normalise(f.value)
            guard v.count >= 2 else { return false }
            if norm.contains(v) { return true }
            // Dates: accept if the digits match in any order of appearance (12 Apr 1999 vs 1999-04-12).
            if let iso = TextRules.firstISODate(in: f.value) {
                return TextRules.allISODates(in: source).contains(iso)
            }
            return false
        }
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "," && $0 != "，" }
    }

    /// Merge chunk facts: first occurrence of each label wins; identical pairs collapse.
    public static func mergeFacts(_ lists: [[DocumentSummary.Fact]]) -> [DocumentSummary.Fact] {
        var seen: Set<String> = []
        var out: [DocumentSummary.Fact] = []
        for f in lists.flatMap({ $0 }) {
            let k = f.label.lowercased() + "=" + normalise(f.value)
            if seen.insert(k).inserted { out.append(f) }
        }
        return out
    }
}
