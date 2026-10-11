import Foundation

/// Parses a free-text model reply (Qwen via MLX) into the summary contract. Tolerates code fences,
/// leading chatter, trailing text, missing keys and a few common key spellings.
public enum SummaryJSON {

    /// JSON schema shown to the model, kept in sync with `DocumentSummary`.
    public static let schemaHint = """
    Reply with JSON only, no prose, exactly this shape:
    {"headline": string, "format": "bullets" | "paragraph" | "unsure", "body": [string], "keyFacts": [{"label": string, "value": string}], "actions": [string]}
    """

    public static func parse(_ reply: String, language: String) -> DocumentSummary? {
        guard let obj = extractObject(reply) else { return nil }
        let headline = (obj["headline"] ?? obj["title"]) as? String ?? ""
        let fmtRaw = ((obj["format"] as? String) ?? "unsure").lowercased()
        let format: DocumentSummary.Format = fmtRaw.contains("para") ? .paragraph : fmtRaw.contains("bullet") || fmtRaw.contains("list") ? .bullets : .unsure
        let body = stringArray(obj["body"] ?? obj["summary"] ?? obj["points"])
        let facts: [DocumentSummary.Fact] = ((obj["keyFacts"] ?? obj["key_facts"] ?? obj["facts"]) as? [[String: Any]] ?? []).compactMap { f in
            guard let l = (f["label"] ?? f["key"] ?? f["name"]) as? String, let v = f["value"] as? String, !v.isEmpty else { return nil }
            return .init(label: l, value: v)
        }
        let actions = stringArray(obj["actions"] ?? obj["todo"] ?? obj["next_steps"])
        guard !headline.isEmpty || !body.isEmpty else { return nil }
        return DocumentSummary(language: language, headline: headline, format: format, body: body, keyFacts: facts, actions: actions, model: "mlx")
    }

    static func stringArray(_ any: Any?) -> [String] {
        if let a = any as? [String] { return a.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        if let s = any as? String { return s.split(separator: "\n").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " -•*")) }.filter { !$0.isEmpty } }
        return []
    }

    /// Find the first balanced {...} object in the text and decode it. Strips ``` fences and a Qwen <think> block.
    static func extractObject(_ text: String) -> [String: Any]? {
        var s = text
        if let r = s.range(of: "</think>") { s = String(s[r.upperBound...]) }
        s = s.replacingOccurrences(of: "```json", with: "```").replacingOccurrences(of: "```", with: "")
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        for i in s[start...].indices {
            let c = s[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
        }
        guard let end else { return nil }
        let json = String(s[start...end])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}
