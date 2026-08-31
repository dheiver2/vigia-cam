import Foundation
import Combine

/// Agrega as métricas de negócio de todas as câmeras para o painel executivo.
/// Cada câmera reporta seus números (contagem única, cruzamentos de linha,
/// ocupação de zona, intrusões); aqui viram KPIs consolidados por nicho.
final class BusinessMetricsService: ObservableObject {
    static let shared = BusinessMetricsService()

    struct Metrica: Hashable {
        var unicos: [String: Int] = [:]
        var entradas = 0
        var saidas = 0
        var ocupacao = 0
        var intrusoes = 0
        var permanencias = 0
    }

    @Published private(set) var porCamera: [String: Metrica] = [:]
    private init() {}

    func reportar(camera: String, metrica: Metrica) {
        porCamera[camera] = metrica
    }

    /// Remove uma câmera dos KPIs ao vivo (chamado quando a sessão termina):
    /// sem isto o painel seguia exibindo os últimos números de câmeras que já
    /// não estão rodando, inclusive de câmeras removidas do sistema.
    func remover(camera: String) {
        porCamera[camera] = nil
    }

    func limpar() { porCamera.removeAll() }

    /// Soma de todas as câmeras — a mesma agregação de sempre, só isolada
    /// numa `Metrica` p/ que `valor(kpi:)` funcione tanto com o "agora" (ao
    /// vivo, `porCamera`) quanto com uma janela histórica vinda do
    /// `EventStore.somarPeriodo`, sem duplicar o switch de KPIs.
    private func metricaAgregada() -> Metrica {
        var m = Metrica()
        for v in porCamera.values {
            for (k, val) in v.unicos { m.unicos[k, default: 0] += val }
            m.entradas += v.entradas; m.saidas += v.saidas; m.ocupacao += v.ocupacao
            m.intrusoes += v.intrusoes; m.permanencias += v.permanencias
        }
        return m
    }

    // KPIs consolidados (ao vivo — mantidos por compatibilidade com quem já lia estes campos)
    private func somaUnicos(_ classes: Set<String>, _ m: Metrica) -> Int {
        m.unicos.filter { classes.isEmpty || classes.contains($0.key) }.values.reduce(0, +)
    }
    var pessoasUnicas: Int { somaUnicos(["person", "Person"], metricaAgregada()) }
    var veiculosUnicos: Int { somaUnicos(["car", "truck", "bus", "motorcycle", "bicycle"], metricaAgregada()) }
    var totalEntradas: Int { porCamera.values.reduce(0) { $0 + $1.entradas } }
    var totalSaidas: Int { porCamera.values.reduce(0) { $0 + $1.saidas } }
    var ocupacaoAtual: Int { porCamera.values.reduce(0) { $0 + $1.ocupacao } }
    var totalIntrusoes: Int { porCamera.values.reduce(0) { $0 + $1.intrusoes } }
    var totalPermanencias: Int { porCamera.values.reduce(0) { $0 + $1.permanencias } }

    /// `metrica` = `nil` usa o agregado ao vivo (`porCamera`); passe uma
    /// `Metrica` vinda de `EventStore.somarPeriodo` para o mesmo KPI numa
    /// janela histórica.
    func valor(kpi: String, metrica: Metrica? = nil) -> String {
        let m = metrica ?? metricaAgregada()
        switch kpi {
        case "Pessoas únicas", "Pessoas": return "\(somaUnicos(["person", "Person"], m))"
        case "Veículos únicos", "Veículos": return "\(somaUnicos(["car", "truck", "bus", "motorcycle", "bicycle"], m))"
        case "Entradas": return "\(m.entradas)"
        case "Saídas": return "\(m.saidas)"
        case "Fluxo (cruzamentos)", "Cruzamentos": return "\(m.entradas + m.saidas)"
        case "Ocupação": return "\(m.ocupacao)"
        case "Intrusões": return "\(m.intrusoes)"
        case "Permanências": return "\(m.permanencias)"
        case "Caminhões": return "\(somaUnicos(["truck"], m))"
        case "Aglomeração máx.", "Pico":
            // Só faz sentido como pico instantâneo por câmera — não existe
            // "pico" agregado numa janela histórica sem série completa, então
            // cai pro ao vivo mesmo quando uma `Metrica` de período é passada.
            // `kpisSemJanela` avisa a UI para não rotular isso como "vs 7 dias".
            return "\(porCamera.values.map { $0.unicos["person"] ?? 0 }.max() ?? 0)"
        case "Sem capacete": return "\(somaUnicos(["NO-Hardhat"], m))"
        case "Sem colete": return "\(somaUnicos(["NO-Safety Vest"], m))"
        case "Capacetes OK": return "\(somaUnicos(["Hardhat"], m))"
        default: return "—"
        }
    }

    /// KPIs que sempre refletem o AO VIVO, mesmo com uma janela histórica
    /// selecionada — a UI precisa saber para não exibir "vs N dias anteriores"
    /// com variação eternamente 0%.
    static let kpisSemJanela: Set<String> = ["Aglomeração máx.", "Pico"]

    /// Compara o mesmo KPI em duas janelas (ex.: 7 dias atuais vs 7 dias
    /// anteriores). `variacaoPct` é `nil` quando não dá pra calcular variação
    /// percentual com sentido (KPI não numérico, ou ambos os períodos zerados).
    func valorComparado(kpi: String, atual: Metrica, anterior: Metrica) -> (atual: String, variacaoPct: Double?) {
        let strAtual = valor(kpi: kpi, metrica: atual)
        let strAnterior = valor(kpi: kpi, metrica: anterior)
        guard let vAtual = Double(strAtual), let vAnterior = Double(strAnterior) else { return (strAtual, nil) }
        // Sair de 0 para N não é "+100%": era indistinguível de dobrar. Sem
        // base de comparação, a variação simplesmente não existe.
        if vAnterior == 0 { return (strAtual, nil) }
        return (strAtual, (vAtual - vAnterior) / vAnterior * 100)
    }
}
