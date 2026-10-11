import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// CoreImage enhancements for the pages editor.
enum ImageEnhancer {
    // CIContext is documented as thread-safe; Swift 6 cannot see that, so we vouch for it.
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Adaptive-ish black and white: boost contrast, then threshold. Good for paper, bad for photos of cards.
    static func blackAndWhite(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let contrast = CIFilter.colorControls()
        contrast.inputImage = input
        contrast.saturation = 0
        contrast.contrast = 1.4
        guard let boosted = contrast.outputImage else { return nil }
        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = boosted
        threshold.threshold = 0.55
        guard let out = threshold.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }
}

extension UIImage {
    /// A CGImage with the orientation baked in (camera scans sometimes carry .right/.left).
    func uprightCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let drawn = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return drawn.cgImage
    }
}
