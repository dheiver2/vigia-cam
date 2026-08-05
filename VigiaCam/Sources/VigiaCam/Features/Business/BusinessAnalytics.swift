import Foundation
import CoreGraphics

/// Alvo rastreado reduzido ao essencial para os analíticos (id + classe + centro
/// normalizado 0–1). Desacopla o motor do rastreador para permitir testes puros.
struct Alvo {
    let id: Int
    let classe: String
    let centro: CGPoint
}

/// Contagem por LINHA VIRTUAL (tripwire) — analítico mais pedido em CFTV:
/// varejo (entrada/saída de pessoas), trânsito (fluxo por faixa), logística
/// (veículos no pátio). Conta cruzamentos DIRECIONAIS de objetos rastreados.
final class LineCounter {
    /// Linha definida por dois pontos normalizados.
    var a: CGPoint
    var b: CGPoint
    private(set) var entradas: [String: Int] = [:]   // lado negativo -> positivo
    private(set) var saidas: [String: Int] = [:]      // positivo -> negativo
    private var ladoAnterior: [Int: Int] = [:]        // id -> sinal do lado

    init(a: CGPoint = CGPoint(x: 0.5, y: 0), b: CGPoint = CGPoint(x: 0.5, y: 1)) {
        self.a = a; self.b = b
    }

    var totalEntradas: Int { entradas.values.reduce(0, +) }
    var totalSaidas: Int { saidas.values.reduce(0, +) }

    private func lado(_ p: CGPoint) -> Int {
        let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        if cross > 0.0001 { return 1 }
        if cross < -0.0001 { return -1 }
        return 0
    }

    /// Atualiza com os alvos do frame; conta quando o objeto troca de lado.
    func update(_ alvos: [Alvo]) {
        let vivos = Set(alvos.map { $0.id })
        for alvo in alvos {
            let atual = lado(alvo.centro)
            if atual == 0 { continue }
            if let ant = ladoAnterior[alvo.id], ant != 0, ant != atual {
                if ant < 0 { entradas[alvo.classe, default: 0] += 1 }
                else { saidas[alvo.classe, default: 0] += 1 }
            }
            ladoAnterior[alvo.id] = atual
        }
        ladoAnterior = ladoAnterior.filter { vivos.contains($0.key) }
    }

    func resetar() { entradas.removeAll(); saidas.removeAll(); ladoAnterior.removeAll() }
}

/// Zona de análise: retângulo normalizado + tipo de vigilância.
enum TipoZona: String, Codable, CaseIterable, Identifiable {
    case intrusao, ocupacao, permanencia, evasao, ausencia
    var id: String { rawValue }
    var label: String {
        switch self {
        case .intrusao: return "Intrusão (área restrita)"
        case .ocupacao: return "Ocupação (contagem)"
        case .permanencia: return "Permanência (loitering)"
        case .evasao: return "Evasão (saída da zona)"
        case .ausencia: return "Ausência (zona vazia)"
        }
    }
}

struct ZonaAnalise: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var x: Double, y: Double, w: Double, h: Double
    var tipo: TipoZona
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// Monitor de ZONAS — perímetro (intrusão), estacionamento/varejo (ocupação),
/// segurança (permanência/loitering). Mantém estado por objeto para medir dwell.
final class ZoneMonitor {
    var zonas: [ZonaAnalise] = []
    var limiarPermanenciaSeg: TimeInterval = 8
    /// Tempo de zona vazia antes de disparar AUSÊNCIA (ex.: posto de vigia
    /// abandonado, vaga de viatura desocupada).
    var limiarAusenciaSeg: TimeInterval = 30
    private(set) var ocupacao: [String: Int] = [:]     // zonaID -> nº de alvos dentro
    private var entrouEm: [String: TimeInterval] = [:]  // "zonaID|objId" -> instante
    private var vaziaDesde: [String: TimeInterval] = [:] // zonaID -> desde quando está vazia
    private var jaTeveOcupacao: Set<String> = []         // ausência só arma depois da 1ª presença

    struct Evento { let zonaID: String; let tipo: TipoZona; let classe: String; let objId: Int }

    /// Atualiza ocupação e devolve eventos (intrusão / permanência) do frame.
    func update(_ alvos: [Alvo], now: TimeInterval) -> [Evento] {
        var eventos: [Evento] = []
        var ocup: [String: Int] = [:]
        var presentes = Set<String>()
        for zona in zonas {
            let r = zona.rect
            for alvo in alvos where r.contains(alvo.centro) {
                ocup[zona.id, default: 0] += 1
                let chave = "\(zona.id)|\(alvo.id)"
                presentes.insert(chave)
                switch zona.tipo {
                case .intrusao:
                    if entrouEm[chave] == nil {          // só no momento da entrada
                        eventos.append(Evento(zonaID: zona.id, tipo: .intrusao, classe: alvo.classe, objId: alvo.id))
                    }
                    entrouEm[chave] = now
                case .permanencia:
                    let t0 = entrouEm[chave] ?? now
                    if entrouEm[chave] == nil { entrouEm[chave] = now }
                    if now - t0 >= limiarPermanenciaSeg {
                        eventos.append(Evento(zonaID: zona.id, tipo: .permanencia, classe: alvo.classe, objId: alvo.id))
                        entrouEm[chave] = now            // re-arma p/ não spammar
                    }
                case .ocupacao, .evasao, .ausencia:
                    entrouEm[chave] = now
                }
            }
        }
        // EVASÃO: alvo que estava dentro e não está mais -> saiu da zona.
        for (chave, _) in entrouEm where !presentes.contains(chave) {
            let partes = chave.split(separator: "|")
            guard partes.count == 2, let objId = Int(partes[1]) else { continue }
            let zonaID = String(partes[0])
            if let zona = zonas.first(where: { $0.id == zonaID }), zona.tipo == .evasao {
                eventos.append(Evento(zonaID: zonaID, tipo: .evasao, classe: "", objId: objId))
            }
        }
        entrouEm = entrouEm.filter { presentes.contains($0.key) }   // saiu da zona -> esquece

        // AUSÊNCIA: zona que deveria ter presença está vazia há tempo demais.
        for zona in zonas where zona.tipo == .ausencia {
            let vazia = (ocup[zona.id] ?? 0) == 0
            if !vazia {
                jaTeveOcupacao.insert(zona.id)
                vaziaDesde[zona.id] = nil
            } else if jaTeveOcupacao.contains(zona.id) {
                let desde = vaziaDesde[zona.id] ?? now
                if vaziaDesde[zona.id] == nil { vaziaDesde[zona.id] = now }
                if now - desde >= limiarAusenciaSeg {
                    eventos.append(Evento(zonaID: zona.id, tipo: .ausencia, classe: "", objId: -1))
                    vaziaDesde[zona.id] = now      // re-arma p/ não spammar
                }
            }
        }
        ocupacao = ocup
        return eventos
    }
}
