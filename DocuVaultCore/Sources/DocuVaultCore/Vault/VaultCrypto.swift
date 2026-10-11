import Foundation
import CryptoKit

/// AES-256-GCM sealing for vault field values, page images and text.
/// The key itself lives in the Keychain (app layer), bound to Face ID and this device only.
public enum VaultCrypto {

    public static let keyBits = 256
    /// Prefix so a sealed blob is recognisable and a plain value is never mistaken for one.
    static let magic = Data("DVv1".utf8)

    public static func makeKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    /// Seal `plain`. Output = magic ‖ nonce(12) ‖ ciphertext ‖ tag(16).
    public static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw VaultError.sealFailed }
        return magic + combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard sealed.count > magic.count + 28, sealed.prefix(magic.count) == magic else { throw VaultError.notSealed }
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(magic.count))
        do { return try AES.GCM.open(box, using: key) } catch { throw VaultError.wrongKeyOrTampered }
    }

    public static func seal(_ string: String, key: SymmetricKey) throws -> Data { try seal(Data(string.utf8), key: key) }
    public static func openString(_ sealed: Data, key: SymmetricKey) throws -> String {
        String(decoding: try open(sealed, key: key), as: UTF8.self)
    }

    public static func isSealed(_ data: Data) -> Bool { data.prefix(magic.count) == magic }

    /// Raw key bytes for Keychain storage and back.
    public static func keyData(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
    public static func key(from data: Data) -> SymmetricKey? {
        guard data.count == keyBits / 8 else { return nil }
        return SymmetricKey(data: data)
    }
}

public enum VaultError: Error, Equatable {
    case sealFailed
    case notSealed
    case wrongKeyOrTampered
    case locked            // vault key not available (Face ID not passed yet)
    case keychain(Int32)
}
