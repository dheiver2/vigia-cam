import Foundation

/// Uma câmera monitorada.
///
/// Modelagem: a identidade (`id`) é separada do endereço (`url`). Antes
/// `id` ERA a URL, então corrigir o endereço de uma câmera equivalia a apagá-la
/// e criar outra — as zonas de privacidade, a linha de contagem e as zonas de
/// análise (todas indexadas por câmera) ficavam órfãs silenciosamente.
struct Camera: Codable, Identifiable, Hashable {
    /// Estável durante toda a vida da câmera, independente da URL.
    let id: String
    var nome: String
    var categoria: String
    var url: String
    /// Posição geográfica (opcional) — alimenta o Mapa de câmeras.
    var latitude: Double?
    var longitude: Double?

    /// Modelo de detecção fixado PARA ESTA câmera (`TipoModelo.rawValue`).
    /// `nil` = seguir o modelo global (`ModelProvider.tipoAtivo`), que os
    /// presets de nicho continuam controlando. Optional para que cameras.json
    /// antigos decodifiquem sem migração.
    var modeloDeteccao: String? = nil

    // MARK: - ONVIF (opcional)
    //
    // Preenchidos quando a câmera foi cadastrada via descoberta ONVIF
    // (`OnvifDiscoverySheet`). `onvifPTZXAddr` só existe se o dispositivo
    // anunciou o serviço PTZ em `GetCapabilities` — sua ausência é o sinal
    // usado pela UI pra decidir se mostra os controles de PTZ.
    // Persistidos junto do resto de `cameras.json`, que já é gravado
    // cifrado (AES-GCM) por `StorageService.salvarJSONCriptografado`.
    var onvifXAddr: String? = nil
    var onvifPTZXAddr: String? = nil
    var onvifProfileToken: String? = nil
    var onvifUsuario: String? = nil
    var onvifSenha: String? = nil

    /// Derivado do esquema da URL — não é mais um campo solto que podia
    /// contradizer o endereço (`tipo: .hls` com `url: "rtsp://…"`).
    var tipo: CameraType { CameraType(url: url) }

    /// URL já validada. Os pontos de uso liam a `String` crua e só descobriam
    /// que era inválida quando o player falhava em silêncio.
    var streamURL: URL? { Self.urlSuportada(url) ? URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) : nil }

    enum CameraType: String, Codable, CaseIterable {
        case rtsp
        case hls
        case local

        var label: String { rawValue.uppercased() }

        init(url: String) {
            let esquema = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased()
            switch esquema {
            case "rtsp", "rtsps": self = .rtsp
            case "http", "https": self = .hls
            default: self = .local
            }
        }
    }

    // MARK: - Construção

    /// `nil` quando a URL não é utilizável. Antes dava para construir uma
    /// `Camera` com URL vazia ou com lixo e ela ia parar na lista, exibindo
    /// "Reconectando…" para sempre.
    init?(nome: String, categoria: String, url: String, id: String = UUID().uuidString) {
        let urlLimpa = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.urlSuportada(urlLimpa) else { return nil }
        let nomeLimpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let catLimpa = categoria.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.url = urlLimpa
        self.nome = nomeLimpo.isEmpty ? urlLimpa : nomeLimpo
        self.categoria = catLimpa.isEmpty ? Self.categoriaPadrao : catLimpa
    }

    static let categoriaPadrao = "Outras"

    // MARK: - Validação de endereço

    /// Esquemas que o player sabe abrir. Mora no modelo (não na tela de
    /// cadastro) para poder ser testado sem subir UI.
    static let esquemasSuportados = ["rtsp", "rtsps", "http", "https"]

    static func urlSuportada(_ texto: String) -> Bool {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty,
              let u = URL(string: limpo),
              let esquema = u.scheme?.lowercased(),
              let host = u.host, !host.isEmpty else { return false }
        return esquemasSuportados.contains(esquema)
    }

    // MARK: - Codable (compatível com o formato antigo)

    private enum CodingKeys: String, CodingKey {
        case id, nome, categoria, url, latitude, longitude
        case onvifXAddr, onvifPTZXAddr, onvifProfileToken, onvifUsuario, onvifSenha
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        // Arquivos gravados antes desta versão não têm `id` — nesses casos a
        // identidade continua sendo a URL, para que a configuração por câmera
        // já persistida (privacidade, linha, zonas) siga casando.
        id = (try? c.decode(String.self, forKey: .id)) ?? url
        nome = (try? c.decode(String.self, forKey: .nome)) ?? url
        categoria = (try? c.decode(String.self, forKey: .categoria)) ?? Self.categoriaPadrao
        latitude = try? c.decode(Double.self, forKey: .latitude)
        longitude = try? c.decode(Double.self, forKey: .longitude)
        onvifXAddr = try? c.decode(String.self, forKey: .onvifXAddr)
        onvifPTZXAddr = try? c.decode(String.self, forKey: .onvifPTZXAddr)
        onvifProfileToken = try? c.decode(String.self, forKey: .onvifProfileToken)
        onvifUsuario = try? c.decode(String.self, forKey: .onvifUsuario)
        onvifSenha = try? c.decode(String.self, forKey: .onvifSenha)
    }

    /// Sintetizado automaticamente pelo compilador a partir de `CodingKeys`
    /// (todo campo tem case correspondente) — só existe `init(from:)` custom
    /// aqui por causa da migração de formato antigo, então o `encode(to:)`
    /// sintetizado grava os campos ONVIF como `nil` até serem preenchidos.

    // MARK: - Agrupamento

    func groupingKey() -> String { categoria }

    static func groupByCategory(_ cameras: [Camera]) -> [(String, [Camera])] {
        let grouped = Dictionary(grouping: cameras) { $0.categoria }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
