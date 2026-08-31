import Foundation

/// Severidade do alarme — controla cor/prioridade no painel e no banner.
enum Severidade: String, Codable, CaseIterable, Identifiable {
    case info, aviso, critico
    var id: String { rawValue }
    var label: String {
        switch self {
        case .info: return "Informativo"
        case .aviso: return "Aviso"
        case .critico: return "Crítico"
        }
    }
}

/// O que a regra conta.
///
/// Antes era `classe: String` com a string mágica `"qualquer"` significando
/// "total de objetos". Um modelo com uma classe realmente chamada "qualquer"
/// (ou um erro de digitação) mudava o sentido da regra sem aviso.
enum AlvoAlarme: Hashable {
    case qualquerObjeto
    case classe(String)

    var descricao: String {
        switch self {
        case .qualquerObjeto: return "objetos"
        case .classe(let c): return ClassesPT.pt(c)
        }
    }

    /// Contagem observada por esta regra, dado o mapa classe -> quantidade.
    /// `monitorada` filtra as classes ativas (vazio/`nil` = todas) — é o mesmo
    /// critério do `AlarmService`, que antes reimplementava esta conta e criava
    /// duas fontes de verdade para "a regra disparou".
    func valor(em counts: [String: Int], monitorada: (String) -> Bool = { _ in true }) -> Int? {
        switch self {
        case .qualquerObjeto:
            return counts.filter { monitorada($0.key) }.values.reduce(0, +)
        case .classe(let c):
            guard monitorada(c) else { return nil }   // classe desativada: regra não se aplica
            return counts[c] ?? 0
        }
    }
}

extension AlvoAlarme: Codable {
    // Serializa como a String de antes ("qualquer" | nome da classe), então os
    // arquivos já gravados continuam sendo lidos.
    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        self = (bruto == "qualquer" || bruto.isEmpty) ? .qualquerObjeto : .classe(bruto)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .qualquerObjeto: try c.encode("qualquer")
        case .classe(let nome): try c.encode(nome)
        }
    }
}

/// Onde a regra vale.
///
/// Antes era `escopo: String?` com significados sobrepostos: `nil`, `""` e
/// `"Todas"` queriam dizer "todas as câmeras", e qualquer outro texto era
/// comparado ao NOME e à CATEGORIA ao mesmo tempo. Uma câmera com o mesmo nome
/// de uma categoria casava nos dois, e não havia como escrever uma regra "só
/// desta câmera" quando esse nome coincidia com uma categoria.
enum EscopoAlarme: Hashable {
    case todas
    case categoria(String)
    case camera(String)

    var descricao: String {
        switch self {
        case .todas: return "Todas"
        case .categoria(let c): return "Categoria: \(c)"
        case .camera(let c): return c
        }
    }

    func casa(nomeCamera: String, categoria: String) -> Bool {
        switch self {
        case .todas: return true
        case .categoria(let c): return categoria == c
        case .camera(let n): return nomeCamera == n
        }
    }
}

extension EscopoAlarme: Codable {
    private enum CodingKeys: String, CodingKey { case tipo, valor }

    init(from decoder: Decoder) throws {
        // Formato novo: objeto {tipo, valor}.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let tipo = try? c.decode(String.self, forKey: .tipo) {
            let valor = (try? c.decode(String.self, forKey: .valor)) ?? ""
            switch tipo {
            case "categoria": self = valor.isEmpty ? .todas : .categoria(valor)
            case "camera": self = valor.isEmpty ? .todas : .camera(valor)
            default: self = .todas
            }
            return
        }
        // Formato antigo: String solta (ou null) — vira escopo por câmera, que
        // é como a tela de alarmes sempre preencheu esse campo.
        let bruto = try? decoder.singleValueContainer().decode(String.self)
        guard let bruto, !bruto.isEmpty, bruto != "Todas" else { self = .todas; return }
        self = .camera(bruto)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .todas:
            try c.encode("todas", forKey: .tipo)
        case .categoria(let v):
            try c.encode("categoria", forKey: .tipo); try c.encode(v, forKey: .valor)
        case .camera(let v):
            try c.encode("camera", forKey: .tipo); try c.encode(v, forKey: .valor)
        }
    }
}

/// Regra de alarme configurável (estilo analítico de VMS: intrusão,
/// aglomeração, presença de classe/veículo, limite por câmera).
struct AlarmRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nome: String
    var alvo: AlvoAlarme
    /// Dispara quando a contagem for MAIOR OU IGUAL a este limite.
    var limite: Int
    var escopo: EscopoAlarme
    var severidade: Severidade
    var ativo: Bool = true

    private enum CodingKeys: String, CodingKey {
        case id, nome, limite, escopo, severidade, ativo
        case alvo
        case alvoLegado = "classe"
    }

    init(id: String = UUID().uuidString, nome: String, alvo: AlvoAlarme, limite: Int,
         escopo: EscopoAlarme = .todas, severidade: Severidade, ativo: Bool = true) {
        self.id = id
        self.nome = nome
        self.alvo = alvo
        // Um limite < 1 dispararia a regra o tempo todo, inclusive com zero
        // objetos em cena.
        self.limite = max(1, limite)
        self.escopo = escopo
        self.severidade = severidade
        self.ativo = ativo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alvoDecodificado = (try? c.decode(AlvoAlarme.self, forKey: .alvo))
            ?? (try? c.decode(AlvoAlarme.self, forKey: .alvoLegado))
            ?? .qualquerObjeto
        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            nome: (try? c.decode(String.self, forKey: .nome)) ?? "Regra",
            alvo: alvoDecodificado,
            limite: (try? c.decode(Int.self, forKey: .limite)) ?? 1,
            escopo: (try? c.decode(EscopoAlarme.self, forKey: .escopo)) ?? .todas,
            severidade: (try? c.decode(Severidade.self, forKey: .severidade)) ?? .info,
            ativo: (try? c.decode(Bool.self, forKey: .ativo)) ?? true
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nome, forKey: .nome)
        try c.encode(alvo, forKey: .alvo)
        try c.encode(limite, forKey: .limite)
        try c.encode(escopo, forKey: .escopo)
        try c.encode(severidade, forKey: .severidade)
        try c.encode(ativo, forKey: .ativo)
    }

    func casaCamera(nome: String, categoria: String) -> Bool {
        escopo.casa(nomeCamera: nome, categoria: categoria)
    }

    /// Valor observado se a regra se aplica e atingiu o limite; `nil` caso
    /// contrário. Fonte de verdade única, usada por `AlarmService.avaliar`.
    func disparo(counts: [String: Int], monitorada: (String) -> Bool = { _ in true }) -> Int? {
        guard ativo, let v = alvo.valor(em: counts, monitorada: monitorada), v >= limite else { return nil }
        return v
    }

    static let exemplos: [AlarmRule] = [
        AlarmRule(nome: "Aglomeração de pessoas", alvo: .classe("person"), limite: 5,
                  severidade: .aviso),
        AlarmRule(nome: "Congestionamento de veículos", alvo: .classe("car"), limite: 8,
                  severidade: .info),
        AlarmRule(nome: "Presença de caminhão", alvo: .classe("truck"), limite: 1,
                  severidade: .info),
    ]
}

/// Ocorrência de alarme (registrada em Eventos e exibida no painel/banner).
///
/// Virou `Codable` com id estável: com `let id = UUID()` gerado na construção,
/// o mesmo alarme relido do histórico ganhava outra identidade, o que impedia
/// deduplicar ou referenciar a evidência ligada a ele.
struct AlarmEvent: Codable, Identifiable, Hashable {
    let id: String
    let quando: Date
    let regra: String
    let camera: String
    let mensagem: String
    let severidade: Severidade

    init(id: String = UUID().uuidString, quando: Date, regra: String,
         camera: String, mensagem: String, severidade: Severidade) {
        self.id = id
        self.quando = quando
        self.regra = regra
        self.camera = camera
        self.mensagem = mensagem
        self.severidade = severidade
    }
}
