// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocuVaultCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DocuVaultCore", targets: ["DocuVaultCore"]),
        .library(name: "DocuVaultOCR", targets: ["DocuVaultOCR"])
    ],
    targets: [
        // Pure logic: models, checkers, text rules. No Apple frameworks beyond Foundation.
        .target(name: "DocuVaultCore"),
        // OCR pipeline: Vision, PDFKit, ImageIO. Runs on iOS and macOS, so CI can test it.
        .target(name: "DocuVaultOCR", dependencies: ["DocuVaultCore"]),
        .testTarget(name: "DocuVaultCoreTests", dependencies: ["DocuVaultCore"]),
        .testTarget(name: "DocuVaultOCRTests", dependencies: ["DocuVaultOCR", "DocuVaultCore"])
    ]
)
