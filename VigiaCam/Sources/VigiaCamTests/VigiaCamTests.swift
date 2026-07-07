import XCTest
@testable import VigiaCam

final class VigiaCamTests: XCTestCase {

    // MARK: - CryptoService Tests

    func testEncryptDecryptRoundtrip() {
        let plaintext = Data("Hello, VigiaCam!".utf8)
        let ciphertext = CryptoService.encrypt(plaintext)
        XCTAssertNotEqual(plaintext, ciphertext)
        let decrypted = CryptoService.decrypt(ciphertext)
        XCTAssertEqual(plaintext, decrypted)
    }

    func testDecryptInvalidDataReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(CryptoService.decrypt(garbage))
    }

    func testSHA256Consistent() {
        let data = Data("test".utf8)
        let h1 = CryptoService.sha256(data)
        let h2 = CryptoService.sha256(data)
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 64) // hex string of 32 bytes
    }

    // MARK: - RBAC Tests

    func testDefaultAdminCreated() {
        let rbac = RBACService()
        XCTAssertFalse(rbac.usuarios.isEmpty)
        XCTAssertEqual(rbac.usuarios.first?.perfil, .admin)
    }

    func testLoginSuccess() {
        let rbac = RBACService()
        let user = rbac.login(usuario: "admin", senha: "admin")
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.perfil, .admin)
    }

    func testLoginFailure() {
        let rbac = RBACService()
        let user = rbac.login(usuario: "admin", senha: "wrong")
        XCTAssertNil(user)
    }

    func testAddAndRemoveUser() throws {
        let rbac = RBACService()
        try rbac.adicionar(usuario: "operador1", senha: "pass123", perfil: .operador)
        XCTAssertEqual(rbac.usuarios.count, 2)
        try rbac.remover(usuario: "operador1")
        XCTAssertEqual(rbac.usuarios.count, 1)
    }

    func testCannotRemoveLastAdmin() {
        let rbac = RBACService()
        XCTAssertThrowsError(try rbac.remover(usuario: "admin")) { error in
            XCTAssertEqual(error as? RBACError, .naoPodeRemoverUltimoAdmin)
        }
    }

    // MARK: - AppConfig Tests

    func testConfigValidation() {
        let cfg = AppConfig(fpsMax: 999, confianca: -1, imgsz: 500, classes: nil, colunas: 2, linhas: 2, retencapDias: 30, zonasPrivacidade: nil)
        let validated = cfg.validated()
        XCTAssertEqual(validated.fpsMax, 60)
        XCTAssertEqual(validated.confianca, 0.05)
        XCTAssertEqual(validated.imgsz % 32, 0)
    }

    func testConfigDefault() {
        let cfg = AppConfig.default
        XCTAssertEqual(cfg.fpsMax, 15)
        XCTAssertEqual(cfg.confianca, 0.40)
        XCTAssertEqual(cfg.imgsz, 480)
    }

    // MARK: - Camera Tests

    func testCameraGroupByCategory() {
        let cameras = [
            Camera(nome: "A1", categoria: "Entrada", tipo: .rtsp, url: "rtsp://a.com/1"),
            Camera(nome: "A2", categoria: "Entrada", tipo: .rtsp, url: "rtsp://a.com/2"),
            Camera(nome: "B1", categoria: "Estacionamento", tipo: .hls, url: "https://b.com/1"),
        ]
        let groups = Camera.groupByCategory(cameras)
        XCTAssertEqual(groups.count, 2)
    }

    func testCameraNormalize() {
        let dict: [String: Any] = ["url": "rtsp://example.com/stream", "nome": "Test"]
        let cam = Camera.normalize(dict)
        XCTAssertNotNil(cam)
        XCTAssertEqual(cam?.nome, "Test")
        XCTAssertEqual(cam?.tipo, .rtsp)
    }

    func testCameraNormalizeInvalidURL() {
        let dict: [String: Any] = ["url": ""]
        XCTAssertNil(Camera.normalize(dict))
    }

    // MARK: - Alarm Tests

    func testAlarmScopeNilMatchesAny() {
        let r = AlarmRule(nome: "R", classe: "person", limite: 5, escopo: nil, severidade: .aviso)
        XCTAssertTrue(r.casaCamera(nome: "Qualquer", categoria: "X"))
    }

    func testAlarmScopeMatchesByCategoryAndName() {
        let r = AlarmRule(nome: "R", classe: "car", limite: 3, escopo: "Pátio", severidade: .info)
        XCTAssertTrue(r.casaCamera(nome: "Z", categoria: "Pátio"))   // por categoria
        XCTAssertTrue(r.casaCamera(nome: "Pátio", categoria: "Outra")) // por nome
        XCTAssertFalse(r.casaCamera(nome: "Z", categoria: "Outra"))    // fora do alvo
    }

    func testAlarmExamplesAndSeverity() {
        XCTAssertEqual(AlarmRule.exemplos.count, 3)
        XCTAssertEqual(Severidade.allCases.count, 3)
        XCTAssertEqual(Severidade.critico.label, "Crítico")
    }

    // MARK: - StorageService Tests

    func testStorageDirectoriesCreated() {
        let storage = StorageService()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.dirGravacoes.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.dirCapturas.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.dirEventos.path))
    }

    func testSaveLoadConfig() {
        let storage = StorageService()
        let config = AppConfig(fpsMax: 30, confianca: 0.5, imgsz: 640, classes: nil, colunas: 3, linhas: 3, retencapDias: 60, zonasPrivacidade: nil)
        storage.salvarConfig(config)
        let loaded = storage.carregarConfig()
        XCTAssertEqual(loaded.fpsMax, 30)
        XCTAssertEqual(loaded.confianca, 0.5)
    }
}
