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

/// Regra de alarme configurável (estilo analítico de VMS: intrusão, aglomeração,
/// presença de classe/veículo, limite por câmera).
struct AlarmRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nome: String
    /// Classe COCO monitorada (ex.: "person", "car") ou "qualquer" p/ total.
    var classe: String
    /// Dispara quando a contagem for MAIOR OU IGUAL a este limite.
    var limite: Int
    /// Escopo: nil/"" = todas as câmeras; senão casa por nome OU categoria.
    var escopo: String?
    var severidade: Severidade
    var ativo: Bool = true

    func casaCamera(nome: String, categoria: String) -> Bool {
        guard let e = escopo, !e.isEmpty, e != "Todas" else { return true }
        return nome == e || categoria == e
    }

    static let exemplos: [AlarmRule] = [
        AlarmRule(nome: "Aglomeração de pessoas", classe: "person", limite: 5,
                  escopo: nil, severidade: .aviso),
        AlarmRule(nome: "Congestionamento de veículos", classe: "car", limite: 8,
                  escopo: nil, severidade: .info),
        AlarmRule(nome: "Presença de caminhão", classe: "truck", limite: 1,
                  escopo: nil, severidade: .info),
    ]
}

/// Ocorrência de alarme (registrada em Eventos e exibida no painel/banner).
struct AlarmEvent: Identifiable, Hashable {
    let id = UUID()
    let quando: Date
    let regra: String
    let camera: String
    let mensagem: String
    let severidade: Severidade
}
