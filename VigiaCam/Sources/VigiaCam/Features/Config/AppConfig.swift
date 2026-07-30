import Foundation

/// Configuração do app, com limites aplicados por `validated()`.
///
/// Estava dentro de `Camera.swift` (junto do modelo de câmera e de um store de
/// UI), e o `typealias Config = AppConfig` fazia o mesmo tipo aparecer com dois
/// nomes — inclusive dentro do próprio `validated()`.
struct AppConfig: Codable {
    var fpsMax: Int
    var confianca: Float
    var imgsz: Int
    /// Classes monitoradas por NOME (ex.: "person", "NO-Hardhat").
    ///
    /// Antes era `[Int]` com índices COCO crus. Índice não tem significado
    /// próprio e não sobrevive à troca de modelo: ao ativar o modelo de EPI (10
    /// classes), um filtro salvo como `[0, 2, 7]` passava a apontar para
    /// classes completamente diferentes — ou para nenhuma.
    var classesMonitoradas: Set<String>?
    var colunas: Int
    var linhas: Int
    var retencaoDias: Int

    static let `default` = AppConfig(
        fpsMax: 15,
        confianca: 0.40,
        imgsz: 640,      // resolução nativa do YOLOv8n: melhora recall de objetos pequenos vs. 480
        classesMonitoradas: nil,   // nil = todas as classes do modelo ativo habilitadas
        colunas: 2,
        linhas: 2,
        retencaoDias: 30
    )

    // Todo campo numérico tem faixa declarada. Antes só fps/confiança/imgsz
    // tinham limite: colunas, linhas e retenção passavam direto e um valor
    // absurdo (ou zero, vindo de um arquivo corrompido) ia para a UI.
    static let limites: (fpsMax: ClosedRange<Int>,
                         confianca: ClosedRange<Float>,
                         imgsz: ClosedRange<Int>,
                         grade: ClosedRange<Int>,
                         retencao: ClosedRange<Int>) = (
        fpsMax: 1...60,
        confianca: 0.05...0.95,
        imgsz: 96...1280,
        grade: 1...8,
        retencao: 1...365
    )

    func validated() -> AppConfig {
        var cfg = self
        cfg.fpsMax = Self.limites.fpsMax.clamp(fpsMax)
        cfg.confianca = Self.limites.confianca.clamp(confianca)
        cfg.imgsz = (Self.limites.imgsz.clamp(imgsz) / 32) * 32
        cfg.colunas = Self.limites.grade.clamp(colunas)
        cfg.linhas = Self.limites.grade.clamp(linhas)
        cfg.retencaoDias = Self.limites.retencao.clamp(retencaoDias)
        cfg.classesMonitoradas = classesMonitoradas?.isEmpty == true ? nil : classesMonitoradas
        return cfg
    }

    // MARK: - Codable (compatível com o formato antigo)

    private enum CodingKeys: String, CodingKey {
        case fpsMax, confianca, imgsz, colunas, linhas
        case classesMonitoradas
        case classesLegado = "classes"          // [Int] de índices COCO
        case retencaoDias
        case retencaoLegado = "retencapDias"    // typo do formato anterior
    }

    init(fpsMax: Int, confianca: Float, imgsz: Int, classesMonitoradas: Set<String>?,
         colunas: Int, linhas: Int, retencaoDias: Int) {
        self.fpsMax = fpsMax
        self.confianca = confianca
        self.imgsz = imgsz
        self.classesMonitoradas = classesMonitoradas
        self.colunas = colunas
        self.linhas = linhas
        self.retencaoDias = retencaoDias
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let padrao = AppConfig.default
        fpsMax = (try? c.decode(Int.self, forKey: .fpsMax)) ?? padrao.fpsMax
        confianca = (try? c.decode(Float.self, forKey: .confianca)) ?? padrao.confianca
        imgsz = (try? c.decode(Int.self, forKey: .imgsz)) ?? padrao.imgsz
        colunas = (try? c.decode(Int.self, forKey: .colunas)) ?? padrao.colunas
        linhas = (try? c.decode(Int.self, forKey: .linhas)) ?? padrao.linhas
        // Aceita a chave nova e a antiga (com o typo), nessa ordem.
        retencaoDias = (try? c.decode(Int.self, forKey: .retencaoDias))
            ?? (try? c.decode(Int.self, forKey: .retencaoLegado))
            ?? padrao.retencaoDias
        if let nomes = try? c.decode(Set<String>.self, forKey: .classesMonitoradas) {
            classesMonitoradas = nomes
        } else if let indices = try? c.decode([Int].self, forKey: .classesLegado) {
            // Converte o filtro antigo (índices COCO) para nomes.
            classesMonitoradas = Set(indices.compactMap { ClassesCOCO.nome(indice: $0) })
        } else {
            classesMonitoradas = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fpsMax, forKey: .fpsMax)
        try c.encode(confianca, forKey: .confianca)
        try c.encode(imgsz, forKey: .imgsz)
        try c.encode(colunas, forKey: .colunas)
        try c.encode(linhas, forKey: .linhas)
        try c.encode(retencaoDias, forKey: .retencaoDias)
        try c.encodeIfPresent(classesMonitoradas, forKey: .classesMonitoradas)
    }
}

private extension ClosedRange {
    func clamp(_ v: Bound) -> Bound { Swift.max(lowerBound, Swift.min(upperBound, v)) }
}
