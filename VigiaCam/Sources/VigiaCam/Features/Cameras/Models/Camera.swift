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

    static let camerasPublicas: [Camera] = [
        Camera(nome: "Fauntleroy Way SW & SW Cloverdale St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/Fauntleroy_SW_Cloverdale_NS.stream/playlist.m3u8"),
        Camera(nome: "California Ave SW & SW Alaska St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/California_SW_Alaska_NS.stream/playlist.m3u8"),
        Camera(nome: "California Ave SW & SW Hanford St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/California_SW_Hanford_NS.stream/playlist.m3u8"),
        Camera(nome: "California Ave SW & SW Admiral Way", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/California_SW_Admiral_NS.stream/playlist.m3u8"),
        Camera(nome: "42nd Ave SW & SW Alaska St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/42_SW_Alaska.stream/playlist.m3u8"),
        Camera(nome: "41st Ave SW & SW Admiral Way", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/41_SW_Admiral.stream/playlist.m3u8"),
        Camera(nome: "Fauntleroy Way SW & SW Alaska St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/Fauntleroy_SW_Alaska_NS.stream/playlist.m3u8"),
        Camera(nome: "35th Ave SW & SW Roxbury St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/35_SW_Roxbury_EW.stream/playlist.m3u8"),
        Camera(nome: "35th Ave SW & SW Barton St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/35_SW_Barton_EW.stream/playlist.m3u8"),
        Camera(nome: "35th Ave SW & SW Holden St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/35_SW_Holden_NS.stream/playlist.m3u8"),
        Camera(nome: "35th Ave SW & SW Morgan St", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/35_SW_Morgan_NS.stream/playlist.m3u8"),
        Camera(nome: "35th Ave SW @ Fauntleroy Way SW", categoria: "West Seattle", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/35_SW_Fauntleroy_SWC.stream/playlist.m3u8"),
        Camera(nome: "24th Ave NW & NW Market St", categoria: "Ballard / Noroeste", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/24_NW_Market_EW.stream/playlist.m3u8"),
        Camera(nome: "15th Ave NW & NW 85th St", categoria: "Ballard / Noroeste", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_NW_85_NS.stream/playlist.m3u8"),
        Camera(nome: "15th Ave NW & NW 65th St NS", categoria: "Ballard / Noroeste", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_NW_65_1.stream/playlist.m3u8"),
        Camera(nome: "15th Ave NW & NW 65th St EW", categoria: "Ballard / Noroeste", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_NW_65_2.stream/playlist.m3u8"),
        Camera(nome: "15th Ave NW & NW Leary Way", categoria: "Ballard / Noroeste", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_NW_Leary_EW.stream/playlist.m3u8"),
        Camera(nome: "Alaskan Way W & W Galer Flyover", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/Alaskan_W_Galer_NS.stream/playlist.m3u8"),
        Camera(nome: "15th Ave W & W Dravus St", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_W_Dravus_NS.stream/playlist.m3u8"),
        Camera(nome: "15th Ave W & W Emerson St", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_W_Emerson_NS.stream/playlist.m3u8"),
        Camera(nome: "15th Ave W & W Garfield St", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_W_Garfield_NS.stream/playlist.m3u8"),
        Camera(nome: "15th Ave W & W Nickerson St", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_W_Nickerson.stream/playlist.m3u8"),
        Camera(nome: "15th Ave W & W Armory Way", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/15_W_Armory_NS.stream/playlist.m3u8"),
        Camera(nome: "Elliott & Galer Flyover", categoria: "Queen Anne / Magnolia", tipo: .hls, url: "https://61e0c5d388c2e.streamlock.net:443/live/Elliott_W_Galer-Flyover_NS.stream/playlist.m3u8"),
    ]
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
