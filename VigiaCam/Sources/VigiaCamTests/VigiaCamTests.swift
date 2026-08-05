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

    // MARK: - AppConfig Tests

    func testConfigValidation() {
        let cfg = AppConfig(fpsMax: 999, confianca: -1, imgsz: 500, classesMonitoradas: nil, colunas: 2, linhas: 2, retencaoDias: 30)
        let validated = cfg.validated()
        XCTAssertEqual(validated.fpsMax, 60)
        XCTAssertEqual(validated.confianca, 0.05)
        XCTAssertEqual(validated.imgsz % 32, 0)
    }

    func testConfigDefault() {
        let cfg = AppConfig.default
        XCTAssertEqual(cfg.fpsMax, 15)
        XCTAssertEqual(cfg.confianca, 0.40)
        XCTAssertEqual(cfg.imgsz, 640)
    }

    // MARK: - Camera Tests

    func testCameraGroupByCategory() {
        let cameras = [
            Camera(nome: "A1", categoria: "Entrada", url: "rtsp://a.com/1")!,
            Camera(nome: "A2", categoria: "Entrada", url: "rtsp://a.com/2")!,
            Camera(nome: "B1", categoria: "Estacionamento", url: "https://b.com/1")!,
        ]
        let groups = Camera.groupByCategory(cameras)
        XCTAssertEqual(groups.count, 2)
    }

    func testCameraTipoDerivadoDaURL() {
        XCTAssertEqual(Camera(nome: "T", categoria: "X", url: "rtsp://example.com/s")?.tipo, .rtsp)
        XCTAssertEqual(Camera(nome: "T", categoria: "X", url: "https://example.com/s.m3u8")?.tipo, .hls)
    }

    func testCameraInvalidURL() {
        XCTAssertNil(Camera(nome: "T", categoria: "X", url: ""))
        XCTAssertNil(Camera(nome: "T", categoria: "X", url: "ftp://x.com/a"))
    }

    func testCameraCoordenadaCodableRoundtrip() throws {
        var cam = Camera(nome: "Geo", categoria: "X", url: "rtsp://a.com/1")!
        cam.latitude = -9.66; cam.longitude = -35.73
        let data = try JSONEncoder().encode(cam)
        let lido = try JSONDecoder().decode(Camera.self, from: data)
        XCTAssertEqual(lido.latitude, -9.66)
        XCTAssertEqual(lido.longitude, -35.73)
    }

    // MARK: - Alarm Tests

    func testAlarmScopeTodasMatchesAny() {
        let r = AlarmRule(nome: "R", alvo: .classe("person"), limite: 5, escopo: .todas, severidade: .aviso)
        XCTAssertTrue(r.casaCamera(nome: "Qualquer", categoria: "X"))
    }

    func testAlarmScopeCategoriaECamera() {
        let porCategoria = AlarmRule(nome: "R", alvo: .classe("car"), limite: 3,
                                     escopo: .categoria("Pátio"), severidade: .info)
        XCTAssertTrue(porCategoria.casaCamera(nome: "Z", categoria: "Pátio"))
        XCTAssertFalse(porCategoria.casaCamera(nome: "Pátio", categoria: "Outra"))
        let porCamera = AlarmRule(nome: "R", alvo: .classe("car"), limite: 3,
                                  escopo: .camera("Portaria"), severidade: .info)
        XCTAssertTrue(porCamera.casaCamera(nome: "Portaria", categoria: "Outra"))
        XCTAssertFalse(porCamera.casaCamera(nome: "Z", categoria: "Portaria"))
    }

    // MARK: - Analíticos de zona (evasão / ausência)

    func testZonaEvasaoDisparaAoSair() {
        let zm = ZoneMonitor()
        zm.zonas = [ZonaAnalise(x: 0, y: 0, w: 0.5, h: 0.5, tipo: .evasao)]
        _ = zm.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.2, y: 0.2))], now: 0)
        let eventos = zm.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.9, y: 0.9))], now: 1)
        XCTAssertTrue(eventos.contains { $0.tipo == .evasao })
    }

    func testZonaAusenciaDisparaAposLimiar() {
        let zm = ZoneMonitor()
        zm.limiarAusenciaSeg = 10
        zm.zonas = [ZonaAnalise(x: 0, y: 0, w: 0.5, h: 0.5, tipo: .ausencia)]
        // arma só depois da primeira presença
        _ = zm.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.2, y: 0.2))], now: 0)
        XCTAssertTrue(zm.update([], now: 5).isEmpty)              // vazio, mas < limiar
        let eventos = zm.update([], now: 20)                       // vazio além do limiar
        XCTAssertTrue(eventos.contains { $0.tipo == .ausencia })
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
        let config = AppConfig(fpsMax: 30, confianca: 0.5, imgsz: 640, classesMonitoradas: nil, colunas: 3, linhas: 3, retencaoDias: 60)
        storage.salvarConfig(config)
        let loaded = storage.carregarConfig()
        XCTAssertEqual(loaded.fpsMax, 30)
        XCTAssertEqual(loaded.confianca, 0.5)
    }
}
