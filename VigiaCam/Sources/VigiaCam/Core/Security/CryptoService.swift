import Foundation
import CryptoKit

/// Criptografia at-rest com AES-GCM (256-bit) para dados sensíveis.
/// Equivalente ao Fernet/Python: chave em Keychain + seal/open com Nonce.
enum CryptoService {

    // MARK: - Key Management

    private static let tag = "com.vigia.cam.encryption.key"
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tag,
        kSecAttrKeyType as String: kSecAttrKeyTypeAES,
        kSecAttrKeySizeInBits as String: 256,
    ]

    static func loadOrCreateKey() -> SymmetricKey {
        if let existing = loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        saveKey(key)
        return key
    }

    private static func loadKey() -> SymmetricKey? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) {
        var query = keychainQuery
        query[kSecValueData as String] = withUnsafeBytes(of: key) { Data($0) }
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Encrypt / Decrypt

    static func encrypt(_ plaintext: Data) -> Data {
        let key = loadOrCreateKey()
        let sealed = try! AES.GCM.seal(plaintext, using: key)
        return sealed.combined!
    }

    static func decrypt(_ ciphertext: Data) -> Data? {
        let key = loadOrCreateKey()
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    // MARK: - Convenience

    static func encryptString(_ text: String) -> Data {
        encrypt(Data(text.utf8))
    }

    static func decryptString(_ data: Data) -> String? {
        guard let decrypted = decrypt(data) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    // MARK: - Hashing

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256File(at url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            hasher.update(data: Data(bytes: buffer, count: bytesRead))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
