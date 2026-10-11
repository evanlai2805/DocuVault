import Foundation
import CoreGraphics
import Vision
import DocuVaultCore

/// On-device OCR via Apple Vision. English + Simplified + Traditional Chinese, always on.
/// Thread-safe: every call builds its own request. Call from any task.
public final class OCREngine: Sendable {

    public static let shared = OCREngine()

    /// Vision uses order as priority when scripts are ambiguous.
    /// Prose: Chinese first (contracts, letters). Identity: English first (MRZ, card numbers, Latin IDs).
    public static let proseLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    public static let identityLanguages = ["en-US", "zh-Hans", "zh-Hant"]

    /// Domain words Vision should bias toward.
    public static let customWords = [
        "SGD", "GST", "NRIC", "FIN", "UEN", "MRZ", "DBS", "OCBC", "UOB", "POSB",
        "增值税", "发票", "统一社会信用代码", "公民身份号码", "签发机关", "有效期限", "居民身份证",
        "租赁合同", "甲方", "乙方", "人民币"
    ]

    public init() {}

    // MARK: - Public API

    /// Recognise text in an image. `mode: .auto` runs a fast pass, decides, then an accurate pass.
    public func recognize(_ image: CGImage, mode: OCRMode = .auto) async throws -> OCRPage {
        let start = Date()
        var chosen = mode
        if mode == .auto {
            let quick = try await run(image, level: .fast, languageCorrection: false, languages: Self.identityLanguages)
            chosen = Self.looksLikeIdentityDocument(quick.textLines) ? .identity : .prose
        }
        let page = try await run(image, level: .accurate, languageCorrection: chosen == .prose,
                                 languages: chosen == .prose ? Self.proseLanguages : Self.identityLanguages)
        let text = page.text
        let ratio = TextRules.cjkRatio(text)
        return OCRPage(
            lines: page.lines,
            imageSize: CGSize(width: image.width, height: image.height),
            language: TextRules.detectLanguage(text).rawValue,
            cjkRatio: ratio,
            mode: chosen,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    /// Heuristic used by `.auto`: MRZ line, card-number run, NRIC/FIN token, or 18-digit 身份证.
    public static func looksLikeIdentityDocument(_ lines: [String]) -> Bool {
        if MRZ.locateLines(in: lines) != nil { return true }
        if NRIC.find(in: lines) != nil { return true }
        if ChinaID.find(in: lines) != nil { return true }
        if let card = CardCheck.findCardNumber(in: lines), card.luhnOK { return true }
        let joined = lines.joined(separator: " ").uppercased()
        let markers = ["PASSPORT", "IDENTITY CARD", "居民身份证", "VALID THRU", "护照", "身份证"]
        return markers.contains { joined.contains($0) }
    }

    // MARK: - Vision

    private struct RawPage: Sendable {
        let lines: [OCRLine]
        var text: String { lines.map(\.text).joined(separator: "\n") }
        var textLines: [String] { lines.map(\.text) }
    }

    private func run(_ image: CGImage, level: VNRequestTextRecognitionLevel, languageCorrection: Bool, languages: [String]) async throws -> RawPage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RawPage, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = languageCorrection
                request.minimumTextHeight = 0.01
                request.customWords = Self.customWords
                request.automaticallyDetectsLanguage = false
                request.recognitionLanguages = Self.supported(languages, for: request)

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results ?? [])
                let lines: [OCRLine] = observations.enumerated().compactMap { idx, obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return OCRLine(index: idx, text: top.string, box: obs.boundingBox, confidence: Double(top.confidence))
                }
                cont.resume(returning: RawPage(lines: lines))
            }
        }
    }

    /// Filter a language list to what this OS build supports, keeping order.
    static func supported(_ wanted: [String], for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let filtered = wanted.filter { supported.contains($0) }
        return filtered.isEmpty ? ["en-US"] : filtered
    }
}
