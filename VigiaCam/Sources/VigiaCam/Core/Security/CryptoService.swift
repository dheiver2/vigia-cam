import Foundation
import CryptoKit

/// Criptografia at-rest com AES-GCM (256-bit) para dados sensíveis.
/// Equivalente ao Fernet/Python: chave em Keychain + seal/open com Nonce.
enum CryptoService {

    // MARK: - Key Management

    private static let tag = "com.vigia.cam.encryption.key"

    /// Item de senha genérica, NÃO `kSecClassKey`. Guardar bytes crus de uma
    /// chave simétrica como `kSecClassKey` + `kSecAttrKeyType: AES` é rejeitado
    /// pelo Keychain do macOS (o `SecItemAdd` falhava calado), e sem o item
    /// gravado toda chamada gerava uma chave nova: nada do que era salvo
    /// conseguia ser lido de volta depois.
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: tag,
        kSecAttrAccount as String: "aes256",
    ]

    /// A chave é lida do Keychain uma vez por processo. Sem isso, cada
    /// `encrypt`/`decrypt` fazia sua própria consulta e uma falha pontual
    /// virava chave nova no meio da execução.
    private static let chave: SymmetricKey = loadOrCreateKey()

    /// Chave de reserva em disco, usada quando o Keychain não devolve o item.
    ///
    /// O app é assinado ad-hoc, e o Keychain do macOS amarra a ACL do item à
    /// identidade do binário — que MUDA a cada rebuild. Sem esta reserva, toda
    /// atualização do app tornaria ilegível tudo que já havia sido salvo.
    /// É proteção mais fraca que o Keychain (arquivo 0600 no Documents do
    /// usuário), mas evita perda silenciosa de dados.
    private static var arquivoChave: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VigiaCam", isDirectory: true)
            .appendingPathComponent(".chave")
    }

    /// Chave efêmera para TESTES: quando o processo roda com
    /// VIGIA_CHAVE_TESTE=1, nada de Keychain/arquivo é tocado. Binários de
    /// teste da CLI são recompilados (não assinados) a cada execução — cada
    /// acesso ao Keychain deles dispara um diálogo de senha do macOS e trava
    /// a suíte até alguém clicar.
    private static let chaveTeste: SymmetricKey? =
        ProcessInfo.processInfo.environment["VIGIA_CHAVE_TESTE"] == "1"
            ? SymmetricKey(size: .bits256) : nil

    static func loadOrCreateKey() -> SymmetricKey {
        if let t = chaveTeste { return t }
        if let doKeychain = loadKey() {
            // As duas cópias TÊM de bater. Se divergirem, um lançamento que só
            // consiga ler o arquivo decifraria com a chave errada e trataria
            // todos os dados como ilegíveis — o Keychain manda, o arquivo segue.
            if loadKeyArquivo()?.bytes != doKeychain.bytes { saveKeyArquivo(doKeychain) }
            return doKeychain
        }
        if let doArquivo = loadKeyArquivo() {
            saveKey(doArquivo)   // repovoa o Keychain com a chave já em uso
            return doArquivo
        }
        let key = SymmetricKey(size: .bits256)
        saveKey(key)
        saveKeyArquivo(key)
        // Só confia na chave nova se ela realmente foi gravada em algum lugar:
        // senão o próximo lançamento geraria outra e o que for salvo agora
        // ficaria ilegível para sempre.
        return loadKey() ?? loadKeyArquivo() ?? key
    }

    private static func loadKey() -> SymmetricKey? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    private static func saveKey(_ key: SymmetricKey) -> Bool {
        // `withUnsafeBytes(of: key)` pegava os bytes da STRUCT `SymmetricKey`
        // (um ponteiro), não o material da chave — o valor mudava a cada
        // execução. O correto é `key.withUnsafeBytes`.
        let material = key.withUnsafeBytes { Data($0) }
        var atributos = keychainQuery
        atributos[kSecValueData as String] = material
        atributos[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var status = SecItemAdd(atributos as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Item já existe (possivelmente de uma build anterior, cuja ACL não
            // deixa ler): sobrescreve em vez de desistir.
            status = SecItemUpdate(keychainQuery as CFDictionary,
                                   [kSecValueData as String: material] as CFDictionary)
        }
        if status != errSecSuccess {
            print("[CryptoService] Keychain indisponível (OSStatus \(status)); usando chave em arquivo")
        }
        return status == errSecSuccess
    }

    private static func loadKeyArquivo() -> SymmetricKey? {
        guard let data = try? Data(contentsOf: arquivoChave), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyArquivo(_ key: SymmetricKey) {
        let fm = FileManager.default
        let dir = arquivoChave.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let material = key.withUnsafeBytes { Data($0) }
        do {
            try material.write(to: arquivoChave, options: [.atomic, .completeFileProtection])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arquivoChave.path)
        } catch {
            print("[CryptoService] não foi possível gravar a chave de reserva: \(error)")
        }
    }

    // MARK: - Encrypt / Decrypt


    /// Devolve `nil` se o seal falhar. Antes era `try!` + `.combined!`: qualquer
    /// falha do CryptoKit derrubava o app inteiro no meio de um salvamento.
    static func encryptOrNil(_ plaintext: Data) -> Data? {
        guard let sealed = try? AES.GCM.seal(plaintext, using: chave),
              let combined = sealed.combined else {
            print("[CryptoService] falha ao cifrar \(plaintext.count) bytes")
            return nil
        }
        return combined
    }

    static func encrypt(_ plaintext: Data) -> Data {
        encryptOrNil(plaintext) ?? Data()
    }

    static func decrypt(_ ciphertext: Data) -> Data? {
        let key = chave
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

private extension SymmetricKey {
    /// Material da chave. `withUnsafeBytes(of:)` na struct devolveria o
    /// ponteiro, não os bytes — foi exatamente essa confusão que quebrou a
    /// persistência da chave no Keychain.
    var bytes: Data { withUnsafeBytes { Data($0) } }
}
