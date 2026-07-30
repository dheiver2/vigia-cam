import Foundation

/// Câmeras de demonstração usadas no primeiro uso.
///
/// Ficavam dentro de `Camera` como `static let camerasPublicas`: um tipo de
/// domínio carregando ~30 endereços fixos. Separar deixa o modelo enxuto e o
/// conjunto de exemplo trocável sem tocar no tipo.
///
/// Jul/2026: o lote original de Seattle (SDOT, host streamlock.net) saiu do ar
/// permanentemente e as câmeras da PA passaram a exigir autenticação; foram
/// substituídas por câmeras NYSDOT (skyvdn) verificadas. Os hosts mortos estão
/// em `hostsMortos` para o StorageService expurgar do `cameras.json` já
/// persistido em instalações antigas.
enum CamerasSeed {

    /// Hosts de seeds antigos que morreram; câmeras persistidas apontando para
    /// eles são removidas no carregamento.
    static let hostsMortos = ["61e0c5d388c2e.streamlock.net", "arcadis-ivds.com", "rtplive/R9_013"]

    /// `compactMap` porque `Camera.init?` recusa endereço inválido: uma linha
    /// com URL quebrada some do seed em vez de virar uma câmera fantasma.
    static let publicas: [Camera] = bruto.compactMap {
        Camera(nome: $0.nome, categoria: $0.categoria, url: $0.url, id: $0.url)
    }

    private struct Linha { let nome: String; let categoria: String; let url: String }

    private static let nysdot = "https://s7.nysdot.skyvdn.com:443/rtplive"

    private static let bruto: [Linha] = [
        // NYSDOT Região 8 — Hudson Valley
        Linha(nome: "NY Hudson Valley, câmera R8-001", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_001/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-002", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_002/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-003", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_003/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-004", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_004/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-005", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_005/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-006", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_006/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-007", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_007/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-008", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_008/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-009", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_009/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-018", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_018/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-021", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_021/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-031", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_031/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-032", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_032/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-037", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_037/playlist.m3u8"),
        Linha(nome: "NY Hudson Valley, câmera R8-038", categoria: "Hudson Valley (NY)", url: "\(nysdot)/R8_038/playlist.m3u8"),

        // NYSDOT Região 7 — North Country
        Linha(nome: "NY North Country, câmera R7-001", categoria: "North Country (NY)", url: "\(nysdot)/R7_001/playlist.m3u8"),
        Linha(nome: "NY North Country, câmera R7-003", categoria: "North Country (NY)", url: "\(nysdot)/R7_003/playlist.m3u8"),
        Linha(nome: "NY North Country, câmera R7-004", categoria: "North Country (NY)", url: "\(nysdot)/R7_004/playlist.m3u8"),
        Linha(nome: "NY North Country, câmera R7-005", categoria: "North Country (NY)", url: "\(nysdot)/R7_005/playlist.m3u8"),
        Linha(nome: "NY North Country, câmera R7-006", categoria: "North Country (NY)", url: "\(nysdot)/R7_006/playlist.m3u8"),
        Linha(nome: "NY North Country, câmera R7-007", categoria: "North Country (NY)", url: "\(nysdot)/R7_007/playlist.m3u8"),

        // NYSDOT Região 6 — Southern Tier
        Linha(nome: "NY Southern Tier, câmera R6-005", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_005/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-011", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_011/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-013", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_013/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-015", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_015/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-016", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_016/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-017", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_017/playlist.m3u8"),
        Linha(nome: "NY Southern Tier, câmera R6-019", categoria: "Southern Tier (NY)", url: "\(nysdot)/R6_019/playlist.m3u8"),

        // Trânsito / Demo (DOT público) — câmeras de trânsito de DOTs estaduais
        // dos EUA. NÃO são câmeras de canteiro de obra: servem só para
        // demonstrar uma fonte HLS pública no nicho "Canteiro de Obras / EPI",
        // que em uso real deve apontar para o RTSP do próprio canteiro.
        Linha(nome: "NY, I-86 Exit 54 @ NY-13", categoria: "Trânsito / Demo (DOT público)", url: "\(nysdot)/R6_030/playlist.m3u8"),
        Linha(nome: "LA, Shreveport (shr-cam-030)", categoria: "Trânsito / Demo (DOT público)", url: "https://ITSStreamingBR2.dotd.la.gov/public/shr-cam-030.streams/playlist.m3u8"),
    ]
}
