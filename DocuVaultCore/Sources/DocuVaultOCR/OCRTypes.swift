import Foundation
import CoreGraphics
import DocuVaultCore

/// One recognised line of text with its position and confidence.
public struct OCRLine: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let text: String
    /// Normalised bounding box, origin bottom-left, 0…1 (Vision convention).
    public let box: CGRect
    /// 0…1. Vision reports per-candidate confidence; we keep the top candidate's.
    public let confidence: Double

    public init(index: Int, text: String, box: CGRect, confidence: Double) {
        self.index = index
        self.text = text
        self.box = box
        self.confidence = confidence
    }

    /// Below this the review UI underlines the line in amber.
    /// Vision's confidence is coarse: clean print often reports exactly 0.5, strong matches 1.0,
    /// poor reads 0.3 or less (observed on macOS 15 / Xcode 16.4 CI). Re-check on device.
    public static let lowConfidenceThreshold = 0.45
    public var isLowConfidence: Bool { confidence < Self.lowConfidenceThreshold }
}

/// OCR result for one page.
public struct OCRPage: Codable, Equatable, Sendable {
    public let lines: [OCRLine]
    public let imageSize: CGSize
    public let language: String          // "en" | "zh-Hans" | "mixed"
    public let cjkRatio: Double
    public let mode: OCRMode
    public let durationSeconds: Double

    public init(lines: [OCRLine], imageSize: CGSize, language: String, cjkRatio: Double, mode: OCRMode, durationSeconds: Double) {
        self.lines = lines
        self.imageSize = imageSize
        self.language = language
        self.cjkRatio = cjkRatio
        self.mode = mode
        self.durationSeconds = durationSeconds
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
    public var textLines: [String] { lines.map(\.text) }

    /// Mean confidence weighted by line length. 0 when there is no text.
    public var meanConfidence: Double {
        let total = lines.reduce(0) { $0 + $1.text.count }
        guard total > 0 else { return 0 }
        return lines.reduce(0.0) { $0 + $1.confidence * Double($1.text.count) } / Double(total)
    }

    /// Lines sorted top-to-bottom, then left-to-right (Vision's y axis points up).
    public var readingOrder: [OCRLine] {
        lines.sorted {
            if abs($0.box.midY - $1.box.midY) > 0.01 { return $0.box.midY > $1.box.midY }
            return $0.box.minX < $1.box.minX
        }
    }
}

/// Which Vision configuration to use.
public enum OCRMode: String, Codable, Sendable {
    /// Language correction ON. Prose, contracts, receipts, letters.
    case prose
    /// Language correction OFF. IDs, cards, MRZ. Correction turns "K1234567A" into words.
    case identity
    /// Run a fast pass first, pick prose or identity from what it sees, then run accurate.
    case auto
}

public enum OCRError: Error, Equatable {
    case noImage
    case visionFailed(String)
    case unsupportedFile(String)
    case pdfUnreadable
}
