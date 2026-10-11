import Foundation
import SwiftData
import CoreGraphics
import DocuVaultOCR

/// Where everything lives: the App Group container, so the keyboard extension (Phase 5) can read it.
/// Every file gets NSFileProtectionComplete — unreadable while the phone is locked.
enum AppFiles {
    static let appGroupID = "group.com.evanlai.docuvault"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        // Simulator or missing entitlement: fall back to Application Support so the app still runs.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var storeURL: URL { containerURL.appendingPathComponent("DocuVault.store") }
    static var pagesDirectory: URL { containerURL.appendingPathComponent("Pages", isDirectory: true) }

    static func makeContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: StoredDocument.self, StoredPage.self, configurations: config)
        applyProtection(to: storeURL)
        return container
    }

    static func applyProtection(to url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}

/// Page images on disk. JPEG, long edge ≤ 3000 px, Complete protection.
enum PageStore {
    static func save(_ image: CGImage) throws -> String {
        guard let data = ImageNormalizer.jpegData(image) else { throw OCRError.noImage }
        let name = UUID().uuidString + ".jpg"
        let url = AppFiles.pagesDirectory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }

    static func load(_ fileName: String) -> CGImage? {
        ImageNormalizer.load(url: AppFiles.pagesDirectory.appendingPathComponent(fileName))
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: AppFiles.pagesDirectory.appendingPathComponent(fileName))
    }
}
