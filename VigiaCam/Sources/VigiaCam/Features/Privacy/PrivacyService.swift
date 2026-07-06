import Foundation
import Combine
import CoreGraphics

/// Zonas de privacidade (LGPD): retângulos normalizados (0–1) por câmera que são
/// tampados/borrados sobre o vídeo ao vivo, nas gravações e nos snapshots.
final class PrivacyService: ObservableObject {
    static let shared = PrivacyService()

    /// camera.url -> lista de retângulos normalizados (origem superior-esquerda).
    @Published private(set) var zonas: [String: [Zona]] = [:]

    struct Zona: Codable, Hashable, Identifiable {
        var id = UUID().uuidString
        var x: Double, y: Double, w: Double, h: Double
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    private let storage = StorageService.shared
    private init() { zonas = carregar() }

    func zonasDe(_ cameraURL: String) -> [Zona] { zonas[cameraURL] ?? [] }

    func adicionar(_ cameraURL: String, rect: CGRect) {
        // normaliza para largura/altura positivas
        let r = rect.standardized
        var z = zonas[cameraURL] ?? []
        z.append(Zona(x: Double(r.minX), y: Double(r.minY),
                      w: Double(r.width), h: Double(r.height)))
        zonas[cameraURL] = z; salvar()
        storage.auditar("zona_privacidade_add", detalhe: "camera=\(cameraURL)")
    }

    func limpar(_ cameraURL: String) {
        zonas[cameraURL] = nil; salvar()
        storage.auditar("zona_privacidade_limpar", detalhe: "camera=\(cameraURL)")
    }

    func removerUltima(_ cameraURL: String) {
        guard var z = zonas[cameraURL], !z.isEmpty else { return }
        z.removeLast(); zonas[cameraURL] = z.isEmpty ? nil : z; salvar()
    }

    private func salvar() {
        if let data = try? JSONEncoder().encode(zonas) {
            storage.salvarRaw(data, para: "zonas_privacidade.json")
        }
    }

    private func carregar() -> [String: [Zona]] {
        guard let data = storage.carregarRaw("zonas_privacidade.json"),
              let z = try? JSONDecoder().decode([String: [Zona]].self, from: data) else { return [:] }
        return z
    }
}
