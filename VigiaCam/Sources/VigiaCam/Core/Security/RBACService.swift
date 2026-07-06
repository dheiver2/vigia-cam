import Foundation

/// Perfis de acesso (RBAC) — idêntico ao Python.
enum Perfil: String, Codable, CaseIterable {
    case admin
    case operador
    case visualizador

    var label: String {
        switch self {
        case .admin: return "Administrador"
        case .operador: return "Operador"
        case .visualizador: return "Visualizador"
        }
    }

    /// Camera-level permissions
    var canAddCamera: Bool { self == .admin }
    var canManageUsers: Bool { self == .admin }
    var canViewAudit: Bool { self == .admin }
    var canExportEvidence: Bool { self != .visualizador }
    var canViewEvents: Bool { true }
    var canViewDashboard: Bool { true }
    var canConfigureDetection: Bool { self != .visualizador }
}

/// Modelo de usuário (serializado em usuarios.json criptografado).
struct Usuario: Codable, Identifiable, Hashable {
    var id: String { usuario }
    let usuario: String
    let perfil: Perfil
    let salt: String
    let hash: String
    var cameras: [String]? // nil = acesso total; lista = apenas essas

    func podeAcessar(_ cameraUrl: String) -> Bool {
        if perfil == .admin || perfil == .operador, cameras == nil { return true }
        guard let permitidas = cameras else { return true }
        return permitidas.contains(cameraUrl)
    }
}

/// Serviço de RBAC com persistência criptografada.
/// Gerencia: login, CRUD de usuários, verificação de senha (PBKDF2-SHA256).
final class RBACService: ObservableObject {
    @Published var usuarioAtual: Usuario?
    @Published var usuarios: [Usuario] = []

    private let storage: StorageService

    init(storage: StorageService = .shared) {
        self.storage = storage
        garantirAdminPadrao()
        usuarios = carregarUsuarios()
    }

    // MARK: - Login

    func login(usuario: String, senha: String) -> Usuario? {
        let key = usuario.lowercased().trimmingCharacters(in: .whitespaces)
        guard let u = usuarios.first(where: { $0.usuario == key }),
              verifyPassword(senha, salt: u.salt, expectedHash: u.hash) else {
            return nil
        }
        DispatchQueue.main.async { self.usuarioAtual = u }
        StorageService.shared.auditar("login", detalhe: "usuario=\(key)")
        return u
    }

    func logout() {
        DispatchQueue.main.async { self.usuarioAtual = nil }
    }

    // MARK: - CRUD

    func adicionar(usuario u: String, senha: String, perfil: Perfil, cameras: [String]? = nil) throws {
        let key = u.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !senha.isEmpty else {
            throw RBACError.camposObrigatorios
        }
        guard !usuarios.contains(where: { $0.usuario == key }) else {
            throw RBACError.usuarioJaExiste
        }
        let salt = generateSalt()
        let hash = hashPassword(senha, salt: salt)
        let novo = Usuario(usuario: key, perfil: perfil, salt: salt, hash: hash, cameras: cameras)
        usuarios.append(novo)
        salvarUsuarios()
        StorageService.shared.auditar("adicionar_usuario", detalhe: "usuario=\(key) perfil=\(perfil.rawValue)")
    }

    func remover(usuario u: String) throws {
        var restantes = usuarios.filter { $0.usuario != u }
        let admins = restantes.filter { $0.perfil == .admin }
        guard !admins.isEmpty else { throw RBACError.naoPodeRemoverUltimoAdmin }
        usuarios = restantes
        salvarUsuarios()
        StorageService.shared.auditar("remover_usuario", detalhe: "usuario=\(u)")
    }

    func definirCameras(usuario u: String, cameras: [String]?) {
        if let idx = usuarios.firstIndex(where: { $0.usuario == u }) {
            usuarios[idx] = Usuario(
                usuario: usuarios[idx].usuario,
                perfil: usuarios[idx].perfil,
                salt: usuarios[idx].salt,
                hash: usuarios[idx].hash,
                cameras: cameras
            )
            salvarUsuarios()
        }
    }

    // MARK: - Password

    private func hashPassword(_ senha: String, salt: String) -> String {
        let saltData = Data(hex: salt)
        let senhaData = Data(senha.utf8)
        let derived = PBKDF2.deriveKey(password: senhaData, salt: saltData, iterations: 100_000, keyLength: 32)
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyPassword(_ senha: String, salt: String, expectedHash: String) -> Bool {
        hashPassword(senha, salt: salt) == expectedHash
    }

    private func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    private func salvarUsuarios() {
        let data = try? JSONEncoder().encode(usuarios)
        guard let data else { return }
        let encrypted = CryptoService.encrypt(data)
        storage.salvarRaw(encrypted, para: "usuarios.json")
    }

    private func carregarUsuarios() -> [Usuario] {
        guard let encrypted = storage.carregarRaw("usuarios.json") else { return [] }
        guard let data = CryptoService.decrypt(encrypted),
              let decoded = try? JSONDecoder().decode([Usuario].self, from: data) else {
            return []
        }
        return decoded
    }

    private func garantirAdminPadrao() {
        guard usuarios.isEmpty else { return }
        try? adicionar(usuario: "admin", senha: "admin", perfil: .admin)
    }
}

enum RBACError: LocalizedError {
    case camposObrigatorios
    case usuarioJaExiste
    case naoPodeRemoverUltimoAdmin

    var errorDescription: String? {
        switch self {
        case .camposObrigatorios: return "Usuário, senha e perfil são obrigatórios"
        case .usuarioJaExiste: return "Usuário já existe"
        case .naoPodeRemoverUltimoAdmin: return "Não é possível remover o último administrador"
        }
    }
}
