import Foundation
import Combine
import CoreGraphics

/// Guarda, por câmera, a configuração de analítico de negócio: a linha virtual
/// de contagem (tripwire) e as zonas de análise. Persistido em disco.
final class AnalyticsConfigService: ObservableObject {
    static let shared = AnalyticsConfigService()

    struct Config: Codable, Hashable {
        var linhaAtiva = false
        var ax = 0.5, ay = 0.1, bx = 0.5, by = 0.9    // linha (normalizada)
        var zonas: [ZonaAnalise] = []
    }

    @Published private(set) var porCamera: [String: Config] = [:]
    private let storage = StorageService.shared
    private init() { porCamera = carregar() }

    func config(_ cameraURL: String) -> Config { porCamera[cameraURL] ?? Config() }

    func definirLinha(_ cameraURL: String, a: CGPoint, b: CGPoint) {
        var c = config(cameraURL)
        c.linhaAtiva = true
        c.ax = Double(a.x); c.ay = Double(a.y); c.bx = Double(b.x); c.by = Double(b.y)
        porCamera[cameraURL] = c; salvar()
        storage.auditar("linha_contagem", detalhe: "camera=\(cameraURL)")
    }

    func removerLinha(_ cameraURL: String) {
        var c = config(cameraURL); c.linhaAtiva = false; porCamera[cameraURL] = c; salvar()
    }

    func adicionarZona(_ cameraURL: String, rect: CGRect, tipo: TipoZona) {
        var c = config(cameraURL)
        let r = rect.standardized
        c.zonas.append(ZonaAnalise(x: Double(r.minX), y: Double(r.minY),
                                   w: Double(r.width), h: Double(r.height), tipo: tipo))
        porCamera[cameraURL] = c; salvar()
        storage.auditar("zona_analise", detalhe: "camera=\(cameraURL) tipo=\(tipo.rawValue)")
    }

    func limparZonas(_ cameraURL: String) {
        var c = config(cameraURL); c.zonas.removeAll(); porCamera[cameraURL] = c; salvar()
    }

    private func salvar() {
        if let d = try? JSONEncoder().encode(porCamera) {
            storage.salvarRaw(d, para: "analitico_config.json")
        }
    }
    private func carregar() -> [String: Config] {
        guard let d = storage.carregarRaw("analitico_config.json"),
              let v = try? JSONDecoder().decode([String: Config].self, from: d) else { return [:] }
        return v
    }
}
