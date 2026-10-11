import Foundation
import Security

/// Your Anthropic API key. Keychain, this device only, no biometry: you paste it once in Settings.
/// Deleting it removes every cloud entry point in the app.
enum ClaudeKeychain {
    static let service = "com.evanlai.docuvault.claude"
    static let account = "api-key"

    static func load() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// "sk-ant-…R7Qa" for display.
    static func masked(_ key: String) -> String {
        guard key.count > 10 else { return "••••" }
        return String(key.prefix(6)) + "…" + String(key.suffix(4))
    }
}

/// Thin Messages API client. One request per approval; no retries that could double-bill.
enum ClaudeClient {
    struct Request: Sendable {
        var model: String
        var system: String
        var user: String
        var maxTokens: Int = 1500
        var temperature: Double = 0.2
    }
    struct Response: Sendable {
        var text: String
        var inputTokens: Int
        var outputTokens: Int
        var stopReason: String
    }
    enum Failure: LocalizedError {
        case noKey
        case invalidKey
        case rateLimited
        case overloaded
        case http(Int, String)
        case network(String)
        case badReply

        var errorDescription: String? {
            switch self {
            case .noKey: "No API key. Add one in Settings → Claude."
            case .invalidKey: "The API key was rejected (401). Check it in Settings → Claude."
            case .rateLimited: "Rate limited (429). Wait a minute and try again."
            case .overloaded: "Claude is overloaded right now (529). Try again shortly."
            case .http(let c, let m): "Claude returned \(c): \(m)"
            case .network(let m): "No connection: \(m)"
            case .badReply: "Claude's reply could not be read."
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func send(_ r: Request, apiKey: String) async throws -> Response {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": r.model,
            "max_tokens": r.maxTokens,
            "temperature": r.temperature,
            "system": r.system,
            "messages": [["role": "user", "content": r.user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw Failure.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(code) else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            switch code {
            case 401: throw Failure.invalidKey
            case 429: throw Failure.rateLimited
            case 529: throw Failure.overloaded
            default: throw Failure.http(code, msg)
            }
        }
        guard let json,
              let content = json["content"] as? [[String: Any]] else { throw Failure.badReply }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        let usage = json["usage"] as? [String: Any]
        return Response(text: text,
                        inputTokens: usage?["input_tokens"] as? Int ?? 0,
                        outputTokens: usage?["output_tokens"] as? Int ?? 0,
                        stopReason: json["stop_reason"] as? String ?? "")
    }
}
