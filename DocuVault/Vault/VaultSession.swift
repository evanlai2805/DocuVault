import Foundation
import SwiftUI
import CryptoKit
import Security
import LocalAuthentication
import DocuVaultCore

/// Holds the vault key while unlocked. Face ID is enforced by the Keychain item itself:
/// the key is stored with `.biometryCurrentSet`, so reading it triggers Face ID and fails if biometrics change.
/// Re-locks `autoLockSeconds` after the app leaves the foreground.
@MainActor @Observable
final class VaultSession {
    static let autoLockSeconds: TimeInterval = 60
    static let keychainService = "com.evanlai.docuvault.vault"
    static let keychainAccount = "vault-key-v1"
    /// Shared with the keyboard extension (Phase 5). Must match the keychain-access-groups entitlement.
    static let accessGroup = "group.com.evanlai.docuvault"

    private(set) var key: SymmetricKey?
    private(set) var lastError: String?
    private var backgroundedAt: Date?

    var isUnlocked: Bool { key != nil }

    /// Load the key (prompts Face ID) or create it on first use.
    func unlock(reason: String = "Unlock your DocuVault") async {
        lastError = nil
        do {
            key = try await Task.detached(priority: .userInitiated) { try VaultKeychain.loadOrCreateKey(reason: reason) }.value
        } catch {
            key = nil
            lastError = (error as? VaultError).map(Self.describe) ?? error.localizedDescription
        }
    }

    func lock() { key = nil }

    func sceneDidChange(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            if let t = backgroundedAt, Date().timeIntervalSince(t) >= Self.autoLockSeconds { lock() }
            backgroundedAt = nil
        @unknown default: break
        }
    }

    // MARK: - Convenience

    func reveal(_ field: StoredField) -> String? {
        guard let sealed = field.sealedValue else { return field.value }
        guard let key else { return nil }
        return try? VaultCrypto.openString(sealed, key: key)
    }

    func revealText(_ doc: StoredDocument) -> String? {
        guard let sealed = doc.sealedText else { return doc.fullText }
        guard let key else { return nil }
        return try? VaultCrypto.openString(sealed, key: key)
    }

    static func describe(_ e: VaultError) -> String {
        switch e {
        case .locked: "Face ID was cancelled."
        case .keychain(let s): "Keychain error \(s)."
        case .wrongKeyOrTampered: "The vault key does not match. Biometrics may have changed."
        case .notSealed, .sealFailed: "Vault data is unreadable."
        }
    }
}

/// Keychain storage for the vault key. Access control: this device only + current biometric set.
/// On the Simulator (no Face ID enrolled) it falls back to a non-biometric item so development still works.
enum VaultKeychain {

    static func loadOrCreateKey(reason: String) throws -> SymmetricKey {
        if let existing = try load(reason: reason) { return existing }
        let key = VaultCrypto.makeKey()
        try store(key)
        return key
    }

    static func load(reason: String) throws -> SymmetricKey? {
        let context = LAContext()
        context.localizedReason = reason
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultSession.keychainService,
            kSecAttrAccount as String: VaultSession.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        addAccessGroup(&query)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = VaultCrypto.key(from: data) else { throw VaultError.wrongKeyOrTampered }
            return key
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            throw VaultError.locked
        default:
            throw VaultError.keychain(status)
        }
    }

    static func store(_ key: SymmetricKey) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultSession.keychainService,
            kSecAttrAccount as String: VaultSession.keychainAccount,
            kSecValueData as String: VaultCrypto.keyData(key),
        ]
        addAccessGroup(&query)
        if let access = biometricAccessControl() {
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    /// Biometry-bound, this-device-only. nil when no biometrics are enrolled (Simulator), so we fall back.
    static func biometricAccessControl() -> SecAccessControl? {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return nil }
        return SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], nil)
    }

    /// Keychain sharing with the keyboard extension needs the entitlement; without it SecItem calls fail (-34018),
    /// so only add the group when the entitlement is present.
    static func addAccessGroup(_ query: inout [String: Any]) {
        if Bundle.main.object(forInfoDictionaryKey: "DocuVaultKeychainSharing") as? Bool == true {
            query[kSecAttrAccessGroup as String] = VaultSession.accessGroup
        }
    }

    /// For Settings → "Reset vault key" (destroys access to sealed data).
    static func deleteKey() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultSession.keychainService,
            kSecAttrAccount as String: VaultSession.keychainAccount,
        ]
        addAccessGroup(&query)
        SecItemDelete(query as CFDictionary)
    }
}
