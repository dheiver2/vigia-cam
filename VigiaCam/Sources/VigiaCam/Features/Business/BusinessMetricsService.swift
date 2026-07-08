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

    func limpar() { porCamera.removeAll() }

    // KPIs consolidados
    private func somaUnicos(_ classes: Set<String>) -> Int {
        porCamera.values.reduce(0) { acc, m in
            acc + m.unicos.filter { classes.isEmpty || classes.contains($0.key) }.values.reduce(0, +)
        }
    }
    var pessoasUnicas: Int { somaUnicos(["person"]) }
    var veiculosUnicos: Int { somaUnicos(["car", "truck", "bus", "motorcycle", "bicycle"]) }
    var totalEntradas: Int { porCamera.values.reduce(0) { $0 + $1.entradas } }
    var totalSaidas: Int { porCamera.values.reduce(0) { $0 + $1.saidas } }
    var ocupacaoAtual: Int { porCamera.values.reduce(0) { $0 + $1.ocupacao } }
    var totalIntrusoes: Int { porCamera.values.reduce(0) { $0 + $1.intrusoes } }
    var totalPermanencias: Int { porCamera.values.reduce(0) { $0 + $1.permanencias } }

    func valor(kpi: String) -> String {
        switch kpi {
        case "Pessoas únicas", "Pessoas": return "\(pessoasUnicas)"
        case "Veículos únicos", "Veículos": return "\(veiculosUnicos)"
        case "Entradas": return "\(totalEntradas)"
        case "Saídas": return "\(totalSaidas)"
        case "Fluxo (cruzamentos)", "Cruzamentos": return "\(totalEntradas + totalSaidas)"
        case "Ocupação": return "\(ocupacaoAtual)"
        case "Intrusões": return "\(totalIntrusoes)"
        case "Permanências": return "\(totalPermanencias)"
        case "Caminhões": return "\(somaUnicos(["truck"]))"
        case "Aglomeração máx.", "Pico":
            return "\(porCamera.values.map { $0.unicos["person"] ?? 0 }.max() ?? 0)"
        default: return "—"
        }
    }
}
