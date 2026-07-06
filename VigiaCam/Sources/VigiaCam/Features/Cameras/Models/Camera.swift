import Foundation

struct Camera: Codable, Identifiable, Hashable {
    var id: String { url }
    let nome: String
    let categoria: String
    let tipo: CameraType
    let url: String

    enum CameraType: String, Codable, CaseIterable {
        case rtsp
        case hls
        case local

        var label: String { rawValue.uppercased() }
    }

    static func normalize(_ dict: [String: Any]) -> Camera? {
        guard let url = dict["url"] as? String, !url.isEmpty else { return nil }
        let tipo = CameraType(rawValue: dict["tipo"] as? String ?? "rtsp") ?? .rtsp
        return Camera(
            nome: dict["nome"] as? String ?? url,
            categoria: dict["categoria"] as? String ?? "Outras",
            tipo: tipo,
            url: url
        )
    }

    func groupingKey() -> String { categoria }

    static func groupByCategory(_ cameras: [Camera]) -> [(String, [Camera])] {
        let grouped = Dictionary(grouping: cameras) { $0.categoria }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// App configuration — validada com limites (equivalente a CFG no Python).
struct AppConfig: Codable {
    var fpsMax: Int
    var confianca: Float
    var imgsz: Int
    var classes: [Int]?
    var colunas: Int
    var linhas: Int
    var retencapDias: Int
    var zonasPrivacidade: [[PrivacyZone]]?

    struct PrivacyZone: Codable {
        let camera: String
        let points: [[Double]] // normalized 0.0-1.0
    }

    static let `default` = AppConfig(
        fpsMax: 15,
        confianca: 0.40,
        imgsz: 480,
        classes: nil,
        colunas: 2,
        linhas: 2,
        retencapDias: 30,
        zonasPrivacidade: nil
    )

    static let limites: (fpsMax: (Int, Int), confianca: (Float, Float), imgsz: (Int, Int)) = (
        fpsMax: (1, 60),
        confianca: (0.05, 0.95),
        imgsz: (96, 1280)
    )

    func validated() -> AppConfig {
        var cfg = self
        cfg.fpsMax = max(Config.limites.fpsMax.0, min(Config.limites.fpsMax.1, fpsMax))
        cfg.confianca = max(Config.limites.confianca.0, min(Config.limites.confianca.1, confianca))
        cfg.imgsz = max(Config.limites.imgsz.0, min(Config.limites.imgsz.1, imgsz))
        cfg.imgsz = (cfg.imgsz / 32) * 32
        return cfg
    }
}

// Typealias for clarity
typealias Config = AppConfig
