import Foundation
import CoreGraphics
import CoreText

/// Renders text into images and PDFs so OCR tests have deterministic input without binary fixtures.
enum TestImageFactory {

    static func font(_ name: String, size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    /// White canvas, black text, one line per array element, top-left aligned.
    static func image(lines: [String], width: Int = 1600, height: Int = 800,
                      fontName: String = "Helvetica", fontSize: CGFloat = 64, lineGap: CGFloat = 1.5) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawLines(lines, in: ctx, canvasHeight: CGFloat(height), fontName: fontName, fontSize: fontSize, lineGap: lineGap)
        return ctx.makeImage()!
    }

    /// A single-page PDF. `drawText: true` writes a real text layer; false draws only a rectangle (a "scan").
    static func pdf(lines: [String], drawText: Bool, pageSize: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(mediaBox)
        if drawText {
            drawLines(lines, in: ctx, canvasHeight: pageSize.height, fontName: "Helvetica", fontSize: 24, lineGap: 1.5)
        } else {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 100, y: 400, width: 200, height: 40))
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func drawLines(_ lines: [String], in ctx: CGContext, canvasHeight: CGFloat,
                                  fontName: String, fontSize: CGFloat, lineGap: CGFloat) {
        let f = font(fontName, size: fontSize)
        var y = canvasHeight - fontSize * 1.5
        for line in lines {
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): f,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
            let attributed = NSAttributedString(string: line, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 60, y: y)
            CTLineDraw(ctLine, ctx)
            y -= fontSize * lineGap
        }
    }
}
