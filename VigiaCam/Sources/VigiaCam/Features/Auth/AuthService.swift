import Foundation
import Combine
import CommonCrypto

/// Papel do operador — controla o que cada aba/ação permite.
enum Papel: String, Codable, CaseIterable, Identifiable {
    case admin, operador, visualizador
    var id: String { rawValue }
    var label: String {
        switch self {
        case .admin: return "Administrador"
        case .operador: return "Operador"
        case .visualizador: return "Visualizador"
        }
    }
    /// Pode alterar configurações, câmeras, regras e usuários.
    var podeConfigurar: Bool { self == .admin }
    /// Pode gravar, tratar ocorrências e exportar evidência.
    var podeOperar: Bool { self != .visualizador }
}

struct Usuario: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nome: String
    var papel: Papel
    var salt: String        // hex
    var hash: String        // PBKDF2-SHA256 hex
    var criadoEm: Date = Date()
    var ultimoAcesso: Date?
}

/// Autenticação local com PBKDF2 (SHA-256, 120k iterações) e papéis.
/// Usuários persistidos criptografados em repouso (usuarios.json via Storage).
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var usuarios: [Usuario] = []
    @Published private(set) var logado: Usuario?

    private let storage = StorageService.shared
    private let arquivo = "usuarios.json"
    private let iteracoes: UInt32 = 120_000

    private init() {
        usuarios = storage.carregarJSONCriptografado(arquivo, as: [Usuario].self) ?? []
        // Primeira execução: cria o admin padrão (admin/admin) — a tela de login
        // avisa para trocar a senha.
        if usuarios.isEmpty {
            _ = criar(nome: "admin", senha: "admin", papel: .admin)
        }
    }

    var precisaTrocarSenhaPadrao: Bool {
        guard let u = usuarios.first(where: { $0.nome == "admin" }) else { return false }
        return verificar(senha: "admin", usuario: u)
    }

    // MARK: - Sessão

    @discardableResult
    func login(nome: String, senha: String) -> Bool {
        guard var u = usuarios.first(where: { $0.nome.lowercased() == nome.lowercased() }),
              verificar(senha: senha, usuario: u) else {
            storage.auditar("login_falhou", detalhe: "usuario=\(nome)", usuario: nome)
            return false
        }
        u.ultimoAcesso = Date()
        atualizar(u)
        logado = u
        storage.auditar("login", detalhe: "papel=\(u.papel.rawValue)", usuario: u.nome)
        RecordingService.shared.definirUsuario(u.nome)
        return true
    }

    func logout() {
        if let u = logado { storage.auditar("logout", usuario: u.nome) }
        logado = nil
        RecordingService.shared.definirUsuario("sistema")
    }

    // MARK: - Gestão de usuários

    @discardableResult
    func criar(nome: String, senha: String, papel: Papel) -> Bool {
        let limpo = nome.trimmingCharacters(in: .whitespaces)
        guard !limpo.isEmpty, !senha.isEmpty,
              !usuarios.contains(where: { $0.nome.lowercased() == limpo.lowercased() }) else { return false }
        let salt = Self.saltAleatorio()
        guard let hash = Self.pbkdf2(senha: senha, saltHex: salt, iteracoes: iteracoes) else { return false }
        usuarios.append(Usuario(nome: limpo, papel: papel, salt: salt, hash: hash))
        salvar()
        storage.auditar("usuario_criado", detalhe: "nome=\(limpo) papel=\(papel.rawValue)",
                        usuario: logado?.nome)
        return true
    }

    func remover(_ u: Usuario) {
        // Nunca deixa o sistema sem nenhum admin.
        let adminsRestantes = usuarios.filter { $0.papel == .admin && $0.id != u.id }
        guard u.papel != .admin || !adminsRestantes.isEmpty else { return }
        usuarios.removeAll { $0.id == u.id }
        salvar()
        storage.auditar("usuario_removido", detalhe: "nome=\(u.nome)", usuario: logado?.nome)
    }

    @discardableResult
    func trocarSenha(_ u: Usuario, nova: String) -> Bool {
        guard !nova.isEmpty, var alvo = usuarios.first(where: { $0.id == u.id }) else { return false }
        let salt = Self.saltAleatorio()
        guard let hash = Self.pbkdf2(senha: nova, saltHex: salt, iteracoes: iteracoes) else { return false }
        alvo.salt = salt; alvo.hash = hash
        atualizar(alvo)
        if logado?.id == alvo.id { logado = alvo }
        storage.auditar("senha_alterada", detalhe: "nome=\(alvo.nome)", usuario: logado?.nome)
        return true
    }

    private func atualizar(_ u: Usuario) {
        if let i = usuarios.firstIndex(where: { $0.id == u.id }) { usuarios[i] = u; salvar() }
    }

    private func salvar() { storage.salvarJSONCriptografado(usuarios, para: arquivo) }

    // MARK: - Criptografia

    private func verificar(senha: String, usuario: Usuario) -> Bool {
        Self.pbkdf2(senha: senha, saltHex: usuario.salt, iteracoes: iteracoes) == usuario.hash
    }

    private static func saltAleatorio() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func pbkdf2(senha: String, saltHex: String, iteracoes: UInt32) -> String? {
        guard let salt = dadosDeHex(saltHex), let pw = senha.data(using: .utf8) else { return nil }
        var derived = [UInt8](repeating: 0, count: 32)
        let ok = pw.withUnsafeBytes { pwBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes.bindMemory(to: Int8.self).baseAddress, pw.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iteracoes, &derived, derived.count)
            }
        }
        guard ok == kCCSuccess else { return nil }
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    private static func dadosDeHex(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(b)
            idx = next
        }
        return data
    }
}
