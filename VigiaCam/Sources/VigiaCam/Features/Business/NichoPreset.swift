import Foundation

/// Pacotes de solução por VERTICAL (nicho de alta demanda em CFTV corporativo).
/// Aplicar um nicho pré-configura as regras de alarme e as classes monitoradas
/// adequadas àquele mercado — entrega de negócio pronta, não só tecnologia.
enum Nicho: String, CaseIterable, Identifiable {
    case varejo, transito, industria, perimetro, estacionamento
    var id: String { rawValue }

    var nome: String {
        switch self {
        case .varejo: return "Varejo"
        case .transito: return "Trânsito / Cidade"
        case .industria: return "Indústria / SST"
        case .perimetro: return "Segurança Perimetral"
        case .estacionamento: return "Estacionamento"
        }
    }

    var icone: String {
        switch self {
        case .varejo: return "cart.fill"
        case .transito: return "car.2.fill"
        case .industria: return "gearshape.2.fill"
        case .perimetro: return "shield.lefthalf.filled"
        case .estacionamento: return "parkingsign.circle.fill"
        }
    }

    var descricao: String {
        switch self {
        case .varejo: return "Fluxo de pessoas (footfall), filas, aglomeração e horário de pico."
        case .transito: return "Contagem e classificação de veículos, congestionamento e fluxo por via."
        case .industria: return "Presença em área restrita, intrusão em zonas de risco e circulação de veículos."
        case .perimetro: return "Intrusão, permanência suspeita (loitering) e cruzamento de linha."
        case .estacionamento: return "Ocupação de vagas, entrada/saída de veículos e rotatividade."
        }
    }

    /// Classes COCO relevantes ao nicho (vazio = todas).
    var classes: Set<String> {
        switch self {
        case .varejo, .perimetro: return ["person"]
        case .transito, .estacionamento: return ["car", "truck", "bus", "motorcycle", "bicycle"]
        case .industria: return ["person", "truck", "car"]
        }
    }

    /// KPIs destacados no painel de negócio deste nicho.
    var kpis: [String] {
        switch self {
        case .varejo: return ["Pessoas únicas", "Entradas", "Saídas", "Aglomeração máx."]
        case .transito: return ["Veículos únicos", "Fluxo (cruzamentos)", "Caminhões", "Pico"]
        case .industria: return ["Pessoas", "Intrusões", "Permanências", "Veículos"]
        case .perimetro: return ["Intrusões", "Permanências", "Cruzamentos", "Pessoas"]
        case .estacionamento: return ["Ocupação", "Entradas", "Saídas", "Veículos únicos"]
        }
    }

    /// Regras de alarme sugeridas para o nicho.
    var regras: [AlarmRule] {
        switch self {
        case .varejo:
            return [AlarmRule(nome: "Aglomeração no PDV", classe: "person", limite: 8, escopo: nil, severidade: .aviso),
                    AlarmRule(nome: "Fila longa", classe: "person", limite: 5, escopo: nil, severidade: .info)]
        case .transito:
            return [AlarmRule(nome: "Congestionamento", classe: "car", limite: 10, escopo: nil, severidade: .aviso),
                    AlarmRule(nome: "Caminhão em via", classe: "truck", limite: 1, escopo: nil, severidade: .info)]
        case .industria:
            return [AlarmRule(nome: "Pessoa em área de risco", classe: "person", limite: 1, escopo: nil, severidade: .critico),
                    AlarmRule(nome: "Veículo na área", classe: "truck", limite: 1, escopo: nil, severidade: .aviso)]
        case .perimetro:
            return [AlarmRule(nome: "Intrusão perimetral", classe: "person", limite: 1, escopo: nil, severidade: .critico)]
        case .estacionamento:
            return [AlarmRule(nome: "Pátio lotado", classe: "car", limite: 12, escopo: nil, severidade: .aviso)]
        }
    }

    /// Aplica o pacote: substitui as regras de alarme e fixa as classes do nicho.
    func aplicar() {
        let a = AlarmService.shared
        a.regras = regras
        a.classesMonitoradas = classes
        a.persistirRegras()
        StorageService.shared.auditar("nicho_aplicado", detalhe: nome)
    }
}
