import Foundation

/// Pacotes de solução por VERTICAL (nicho de alta demanda em CFTV corporativo).
/// Aplicar um nicho pré-configura as regras de alarme e as classes monitoradas
/// adequadas àquele mercado — entrega de negócio pronta, não só tecnologia.
enum Nicho: String, CaseIterable, Identifiable {
    case varejo, transito, industria, perimetro, estacionamento, canteiroDeObras
    var id: String { rawValue }

    var nome: String {
        switch self {
        case .varejo: return "Varejo"
        case .transito: return "Trânsito / Cidade"
        case .industria: return "Indústria / SST"
        case .perimetro: return "Segurança Perimetral"
        case .estacionamento: return "Estacionamento"
        case .canteiroDeObras: return "Canteiro de Obras / EPI"
        }
    }

    var icone: String {
        switch self {
        case .varejo: return "cart.fill"
        case .transito: return "car.2.fill"
        case .industria: return "gearshape.2.fill"
        case .perimetro: return "shield.lefthalf.filled"
        case .estacionamento: return "parkingsign.circle.fill"
        case .canteiroDeObras: return "hammer.fill"
        }
    }

    var descricao: String {
        switch self {
        case .varejo: return "Fluxo de pessoas (footfall), filas, aglomeração e horário de pico."
        case .transito: return "Contagem e classificação de veículos, congestionamento e fluxo por via."
        case .industria: return "Presença em área restrita, intrusão em zonas de risco e circulação de veículos."
        case .perimetro: return "Intrusão, permanência suspeita (loitering) e cruzamento de linha."
        case .estacionamento: return "Ocupação de vagas, entrada/saída de veículos e rotatividade."
        case .canteiroDeObras: return "Detecção de pessoas sem capacete ou sem colete de segurança em canteiro de obras."
        }
    }

    /// Modelo CoreML que este nicho exige. Nichos que só filtram classes COCO
    /// usam o modelo geral; EPI precisa de vocabulário fora do COCO, logo de
    /// um `.mlpackage` próprio.
    var modelo: TipoModelo {
        switch self {
        case .canteiroDeObras: return .ppe
        default: return .geral
        }
    }

    /// Categoria de câmera (aba Ao Vivo) a mostrar automaticamente ao aplicar
    /// este nicho. `nil` = não muda o filtro (nichos gerais não têm um lote
    /// de câmera dedicado). Só Canteiro de Obras tem hoje.
    var categoriaCamera: String? {
        switch self {
        case .canteiroDeObras: return "Trânsito / Demo (DOT público)"
        default: return nil
        }
    }

    /// Classes relevantes ao nicho, no vocabulário do MODELO daquele nicho
    /// (COCO para os nichos gerais, EPI para Canteiro de Obras). Vazio = todas.
    var classes: Set<String> {
        switch self {
        case .varejo, .perimetro: return ["person"]
        case .transito, .estacionamento: return ["car", "truck", "bus", "motorcycle", "bicycle"]
        case .industria: return ["person", "truck", "car"]
        case .canteiroDeObras: return ["Person", "Hardhat", "NO-Hardhat", "Safety Vest", "NO-Safety Vest"]
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
        case .canteiroDeObras: return ["Pessoas", "Sem capacete", "Sem colete", "Capacetes OK"]
        }
    }

    /// Regras de alarme sugeridas para o nicho.
    var regras: [AlarmRule] {
        switch self {
        case .varejo:
            return [AlarmRule(nome: "Aglomeração no PDV", alvo: .classe("person"), limite: 8, severidade: .aviso),
                    AlarmRule(nome: "Fila longa", alvo: .classe("person"), limite: 5, severidade: .info)]
        case .transito:
            return [AlarmRule(nome: "Congestionamento", alvo: .classe("car"), limite: 10, severidade: .aviso),
                    AlarmRule(nome: "Caminhão em via", alvo: .classe("truck"), limite: 1, severidade: .info)]
        case .industria:
            return [AlarmRule(nome: "Pessoa em área de risco", alvo: .classe("person"), limite: 1, severidade: .critico),
                    AlarmRule(nome: "Veículo na área", alvo: .classe("truck"), limite: 1, severidade: .aviso)]
        case .perimetro:
            return [AlarmRule(nome: "Intrusão perimetral", alvo: .classe("person"), limite: 1, severidade: .critico)]
        case .estacionamento:
            return [AlarmRule(nome: "Pátio lotado", alvo: .classe("car"), limite: 12, severidade: .aviso)]
        case .canteiroDeObras:
            // O modelo já emite a classe combinada "NO-Hardhat"/"NO-Safety Vest"
            // (pessoa detectada SEM o EPI) — não precisa de regra relacional
            // "classe A sem classe B", só presença dessa classe já é o alarme.
            return [AlarmRule(nome: "Pessoa sem capacete", alvo: .classe("NO-Hardhat"), limite: 1, severidade: .critico),
                    AlarmRule(nome: "Pessoa sem colete", alvo: .classe("NO-Safety Vest"), limite: 1, severidade: .critico)]
        }
    }

    /// Aplica o pacote: troca o modelo CoreML ativo (se necessário), substitui
    /// as regras de alarme e fixa as classes do nicho.
    func aplicar() {
        ModelProvider.tipoAtivo = modelo
        if let cat = categoriaCamera { CameraFilterStore.shared.categoria = cat }
        let a = AlarmService.shared
        a.regras = regras
        a.classesMonitoradas = classes
        a.persistirRegras()
        StorageService.shared.auditar("nicho_aplicado", detalhe: nome)
    }
}
