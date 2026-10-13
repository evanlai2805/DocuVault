import Foundation
import SwiftData
import CoreGraphics
import CryptoKit
import DocuVaultCore
import DocuVaultOCR

/// Where everything lives: the App Group container, so the keyboard extension (Phase 5) can read it.
/// Every file gets NSFileProtectionComplete — unreadable while the phone is locked.
enum AppFiles {
    static let appGroupID = "group.com.evanlai.docuvault"

    /// How long the keyboard stays unlocked after the last key, in seconds; 0 = lock when it hides.
    /// Set in the app's Settings, read by the keyboard. Default 1 min (Evan, checkpoint 14).
    static let keyboardLockWindowKey = "keyboard.lockWindowSeconds"
    static let keyboardLockWindowDefault: Double = 60

    /// What the keyboard opens on after the lock window (checkpoint 13c): suggestions, the last
    /// document, or the full list. Set in the app's Settings, read by the keyboard.
    static let keyboardStartPageKey = "keyboard.startPage"
    enum KeyboardStartPage: String, CaseIterable {
        case suggestions, last, list
        var displayName: String {
            switch self { case .suggestions: "Suggestions"; case .last: "Last document"; case .list: "Documents list" }
        }
    }

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
        let container = try ModelContainer(for: StoredDocument.self, StoredPage.self, StoredField.self, StoredPerson.self, StoredTombstone.self, StoredCloudSend.self, configurations: config)
        applyProtection(to: storeURL)
        return container
    }

    static func applyProtection(to url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}

/// Page images on disk. JPEG, long edge ≤ 3000 px, Complete protection.
/// Vault pages are additionally sealed with the vault key and stored as `.jpg.enc`.
enum PageStore {
    static func save(_ image: CGImage, vaultKey: SymmetricKey? = nil) throws -> String {
        guard var data = ImageNormalizer.jpegData(image) else { throw OCRError.noImage }
        var name = UUID().uuidString + ".jpg"
        if let key = vaultKey {
            data = try VaultCrypto.seal(data, key: key)
            name += ".enc"
        }
        let url = AppFiles.pagesDirectory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }

    static func isSealed(_ fileName: String) -> Bool { fileName.hasSuffix(".enc") }

    /// Plain pages load directly. Sealed pages need the vault key; nil when locked.
    static func load(_ fileName: String, vaultKey: SymmetricKey? = nil) -> CGImage? {
        let url = AppFiles.pagesDirectory.appendingPathComponent(fileName)
        if isSealed(fileName) {
            guard let key = vaultKey, let sealed = try? Data(contentsOf: url),
                  let plain = try? VaultCrypto.open(sealed, key: key) else { return nil }
            return ImageNormalizer.load(data: plain)
        }
        return ImageNormalizer.load(url: url)
    }

    /// Raw JPEG bytes (decrypted) for export.
    static func jpegBytes(_ fileName: String, vaultKey: SymmetricKey?) -> Data? {
        let url = AppFiles.pagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if isSealed(fileName) {
            guard let key = vaultKey else { return nil }
            return try? VaultCrypto.open(data, key: key)
        }
        return data
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: AppFiles.pagesDirectory.appendingPathComponent(fileName))
    }

    /// A sealed copy of a plain page, bytes unchanged (Move to Vault, checkpoint 16). The plain file stays
    /// until the caller has switched the page over, so a failure part-way leaves nothing unreadable.
    static func sealedCopy(_ fileName: String, key: SymmetricKey) throws -> String {
        let url = AppFiles.pagesDirectory.appendingPathComponent(fileName)
        let sealed = try VaultCrypto.seal(try Data(contentsOf: url), key: key)
        let name = UUID().uuidString + ".jpg.enc"
        try sealed.write(to: AppFiles.pagesDirectory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }
}
