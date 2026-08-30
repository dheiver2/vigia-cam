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

        // São Paulo — Via Dutra (BR-116), câmeras públicas da concessionária
        // CCR RioSP (rodovias.grupoccr.com.br/riosp/cameras-ao-vivo). HLS via
        // CloudFront; verificadas em 30/ago/2026. Trecho paulista da rodovia.
        Linha(nome: "SP, Dutra km 78 — Roseira", categoria: "São Paulo (Via Dutra)", url: "https://d3b8201cy0qzzb.cloudfront.net/out/v1/db7ff89ac2dc4a2fa37f763f27429d86/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 100 — Taubaté", categoria: "São Paulo (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/e324b6a41320417c9e63b06835fd3a5f/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 156 — São José dos Campos", categoria: "São Paulo (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/0fc685c0aa5c468687bbd6c0f751edd6/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 160 — Jacareí", categoria: "São Paulo (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/776fef1557fd49569d4528f0f41fcf98/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 202 — Arujá", categoria: "São Paulo (Via Dutra)", url: "https://d3b8201cy0qzzb.cloudfront.net/out/v1/f7d3e1cb49d04cd9a8f4d18c17cb4d1f/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 210 — Guarulhos", categoria: "São Paulo (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/3cda6b49f31b4e129cb917f78bf36c26/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 225 — Guarulhos", categoria: "São Paulo (Via Dutra)", url: "https://d3b8201cy0qzzb.cloudfront.net/out/v1/4bd31ad7560846e08093f9552f92a8d0/CMAF_HLS/index.m3u8"),
        Linha(nome: "SP, Dutra km 230 — São Paulo", categoria: "São Paulo (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/e664a9b9ae1d4de38ac33c70857a1371/CMAF_HLS/index.m3u8"),

        // Rio de Janeiro — Via Dutra (BR-116), trecho fluminense (CCR RioSP).
        Linha(nome: "RJ, Dutra km 224 — Paracambi", categoria: "Rio de Janeiro (Via Dutra)", url: "https://dlziwpy8wmigq.cloudfront.net/out/v1/4e01de7aff184385a6a4cff8524c742f/CMAF_HLS/index.m3u8"),
        Linha(nome: "RJ, Dutra km 315 — Itatiaia", categoria: "Rio de Janeiro (Via Dutra)", url: "https://d3b8201cy0qzzb.cloudfront.net/out/v1/12d7e2e551894165a5e2d08fc2b58b20/CMAF_HLS/index.m3u8"),

        // Espírito Santo — câmeras de surf de Guarapari (OndasOnline, Wowza
        // logicahost aberto). "Praia do Buraco" é HEVC — fica de fora até
        // validar o decode no pipeline.
        Linha(nome: "ES, Guarapari — Praia D'Ulé (Escolinha)", categoria: "Espírito Santo (Guarapari)", url: "https://video02.logicahost.com.br/ledrusso/escolinha.stream/playlist.m3u8"),
        Linha(nome: "ES, Guarapari — Praia D'Ulé (1ª Entrada)", categoria: "Espírito Santo (Guarapari)", url: "https://video02.logicahost.com.br/ledrusso/primeiraentrada.stream/playlist.m3u8"),
        Linha(nome: "ES, Guarapari — Praia D'Ulé (Pico da Belina)", categoria: "Espírito Santo (Guarapari)", url: "https://video02.logicahost.com.br/ledrusso/picodabelina.stream/playlist.m3u8"),

        // Paraná — Guaratuba (Grupo Litorânea, logicahost).
        Linha(nome: "PR, Guaratuba — Praia de Caieiras (ponte)", categoria: "Paraná (Guaratuba)", url: "https://video02.logicahost.com.br/camlitoranea/caieirasponte.stream/playlist.m3u8"),
        Linha(nome: "PR, Guaratuba — Trevo do Coroados (PR-412)", categoria: "Paraná (Guaratuba)", url: "https://video02.logicahost.com.br/camlitoranea/coroados.stream/playlist.m3u8"),

        // Santa Catarina — BNU.tv (Blumenau/região, Wowza streamlock).
        Linha(nome: "SC, Blumenau — BNU.tv feed 1", categoria: "Santa Catarina (Blumenau)", url: "https://5a8d73edc0407.streamlock.net:443/bnutv200/bnutv20005.stream/playlist.m3u8"),
        Linha(nome: "SC, Blumenau — BNU.tv feed 2", categoria: "Santa Catarina (Blumenau)", url: "https://5a8d73edc0407.streamlock.net:443/bnutv200/bnutv20007.stream/playlist.m3u8"),

        // Rio Grande do Sul — Torres (torresaovivo.com.br, logicahost).
        // 36 câmeras verificadas na cidade; seleção de 12 representativas
        // (orla, trânsito, aeroporto) para não inundar o videowall.
        Linha(nome: "RS, Torres — Quatro Praças", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/quatropraca/quatropraca/playlist.m3u8"),
        Linha(nome: "RS, Torres — Av. Beira Mar, Praia Grande II", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/praiagrande/praiagrande/playlist.m3u8"),
        Linha(nome: "RS, Torres — Praia dos Molhes", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/molhes/molhes/playlist.m3u8"),
        Linha(nome: "RS, Torres — Morro da Guarita", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/morrodaguarita/morrodaguarita/playlist.m3u8"),
        Linha(nome: "RS, Torres — Orla Gastronômica", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/orlagastronomica1/orlagastronomica1/playlist.m3u8"),
        Linha(nome: "RS, Torres — Praça Pinheiro Machado", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/pracapinheiro/pracapinheiro/playlist.m3u8"),
        Linha(nome: "RS, Torres — Rótula do Balão", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/rotulabalao/rotulabalao/playlist.m3u8"),
        Linha(nome: "RS, Torres — Rótula Itapeva x Estrada do Mar", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/itapeva/itapeva/playlist.m3u8"),
        Linha(nome: "RS, Torres — Aeroporto, Pátio Norte", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/aeropationorte/aeropationorte/playlist.m3u8"),
        Linha(nome: "RS, Torres — Ponte Pênsil", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/pensil/pensil/playlist.m3u8"),
        Linha(nome: "RS, Torres — Prainha", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/prainha/prainha/playlist.m3u8"),
        Linha(nome: "RS, Torres — Panorâmica Ilha dos Lobos", categoria: "Rio Grande do Sul (Torres)", url: "https://video02.logicahost.com.br/ilhalobo/ilhalobo/playlist.m3u8"),

        // Trânsito / Demo (DOT público) — câmeras de trânsito de DOTs estaduais
        // dos EUA. NÃO são câmeras de canteiro de obra: servem só para
        // demonstrar uma fonte HLS pública no nicho "Canteiro de Obras / EPI",
        // que em uso real deve apontar para o RTSP do próprio canteiro.
        Linha(nome: "NY, I-86 Exit 54 @ NY-13", categoria: "Trânsito / Demo (DOT público)", url: "\(nysdot)/R6_030/playlist.m3u8"),
        Linha(nome: "LA, Shreveport (shr-cam-030)", categoria: "Trânsito / Demo (DOT público)", url: "https://ITSStreamingBR2.dotd.la.gov/public/shr-cam-030.streams/playlist.m3u8"),
    ]
}
