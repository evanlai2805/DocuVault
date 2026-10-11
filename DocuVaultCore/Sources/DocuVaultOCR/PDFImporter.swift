import Foundation
import CoreGraphics
import PDFKit
import DocuVaultCore

/// Turns a PDF into pages. Text PDFs keep their own text (exact, instant).
/// Scanned PDFs are rendered and sent through OCR.
public enum PDFImporter {

    public struct ImportedPage: Sendable {
        public let index: Int
        public let image: CGImage
        /// Present when the PDF carried a text layer; nil means "run OCR".
        public let embeddedText: String?
    }

    /// A page whose text layer has at least this many non-whitespace characters is treated as a text PDF.
    public static let minimumEmbeddedTextChars = 20

    /// Render DPI for OCR. 200 dpi keeps A4 under the 3000 px long-edge cap (A4 @ 200 dpi ≈ 1654 × 2339).
    public static let renderDPI: CGFloat = 200

    public static func importPDF(data: Data) throws -> [ImportedPage] {
        guard let doc = PDFDocument(data: data) else { throw OCRError.pdfUnreadable }
        return try importPDF(doc)
    }

    public static func importPDF(url: URL) throws -> [ImportedPage] {
        guard let doc = PDFDocument(url: url) else { throw OCRError.pdfUnreadable }
        return try importPDF(doc)
    }

    static func importPDF(_ doc: PDFDocument) throws -> [ImportedPage] {
        var out: [ImportedPage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasText = text.filter { !$0.isWhitespace }.count >= minimumEmbeddedTextChars
            guard let img = render(page) else { continue }
            out.append(ImportedPage(index: i, image: img, embeddedText: hasText ? text : nil))
        }
        if out.isEmpty { throw OCRError.pdfUnreadable }
        return out
    }

    /// Render a PDF page to a CGImage at `renderDPI`, white background, long edge capped.
    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        var scale = renderDPI / 72.0
        let longEdgePts = max(bounds.width, bounds.height)
        if longEdgePts * scale > CGFloat(ImageNormalizer.maxLongEdge) {
            scale = CGFloat(ImageNormalizer.maxLongEdge) / longEdgePts
        }
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        // Apply the page's own rotation (0/90/180/270) the same way PDFKit's thumbnail does.
        let rotation = page.rotation
        if rotation != 0 {
            let rad = -CGFloat(rotation) * .pi / 180
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: rad)
            ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        return ctx.makeImage()
    }
}
