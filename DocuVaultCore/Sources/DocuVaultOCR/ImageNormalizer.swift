import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Loads images from any source, applies EXIF orientation, caps size, encodes JPEG for storage.
public enum ImageNormalizer {

    /// Long edge cap for stored pages. Enough for re-OCR, ~1 MB per page at q0.85.
    public static let maxLongEdge = 3000
    public static let jpegQuality: CGFloat = 0.85

    /// Decode image data (JPEG, PNG, HEIC, TIFF…) with orientation applied and long edge ≤ `maxLongEdge`.
    public static func load(data: Data, maxLongEdge: Int = ImageNormalizer.maxLongEdge) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxLongEdge: maxLongEdge)
    }

    public static func load(url: URL, maxLongEdge: Int = ImageNormalizer.maxLongEdge) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxLongEdge: maxLongEdge)
    }

    private static func thumbnail(from source: CGImageSource, maxLongEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // applies EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Encode to JPEG. Returns nil on failure.
    public static func jpegData(_ image: CGImage, quality: CGFloat = ImageNormalizer.jpegQuality) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Rotate by multiples of 90° clockwise. Used by the pages editor.
    public static func rotated(_ image: CGImage, quarterTurnsClockwise turns: Int) -> CGImage? {
        let t = ((turns % 4) + 4) % 4
        if t == 0 { return image }
        let w = image.width, h = image.height
        let swap = (t % 2 == 1)
        let outW = swap ? h : w, outH = swap ? w : h
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
        // CoreGraphics rotates counter-clockwise for positive angles; clockwise turn = negative.
        ctx.rotate(by: -CGFloat(t) * .pi / 2)
        ctx.draw(image, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()
    }

    /// Convert to greyscale. B&W thresholding is left to CoreImage in the app (needs GPU for speed).
    public static func greyscale(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
