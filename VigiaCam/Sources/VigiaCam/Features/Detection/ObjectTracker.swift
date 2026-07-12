import Foundation
import CoreGraphics

/// Objeto rastreado com identidade persistente e modelo de movimento.
struct TrackedObject: Identifiable {
    let id: Int
    let label: String
    var confidence: Float
    var box: CGRect            // último box suavizado (Vision: origem inferior-esq, 0–1)
    var vx: CGFloat            // velocidade do centro (unid. normalizadas por segundo)
    var vy: CGFloat
    var lastUpdate: TimeInterval
    var hits: Int
    var missed: Int

    /// Box extrapolado para o instante `t` pelo modelo de velocidade constante.
    func predictedBox(at t: TimeInterval) -> CGRect {
        let dt = CGFloat(max(0, t - lastUpdate))
        return box.offsetBy(dx: vx * dt, dy: vy * dt)
    }
}

/// Rastreador multi-objeto leve (estilo SORT): associação por IoU + predição por
/// velocidade + suavização EMA. Roda a detecção pesada (YOLO) a ~2,5 Hz, mas o
/// rastreador prediz as caixas a cada frame de exibição (~15 Hz), então os
/// rótulos acompanham os objetos em movimento SEM o delay/salto da inferência.
///
/// Bônus (paridade com concorrentes): IDs persistentes por objeto e contagem
/// de objetos ÚNICOS por classe (footfall / contagem veicular).
final class ObjectTracker {
    private(set) var tracks: [TrackedObject] = []
    private(set) var unicosPorClasse: [String: Int] = [:]
    private var proximoId = 1

    private let maxMissed = 12            // frames de predição tolerados sem detecção
    private let confirmar = 2             // hits p/ um track ser exibido
    private let emaPos: CGFloat = 0.6     // suavização do box (0=lento, 1=cru)
    private let emaVel: CGFloat = 0.4     // suavização da velocidade

    /// Atualiza os tracks com as detecções de UM frame.
    ///
    /// Associação por DISTÂNCIA DE CENTROIDE com "gate" proporcional ao tamanho
    /// do objeto — mais robusta que IoU puro quando a inferência é lenta (2,5 Hz)
    /// e o objeto anda mais que o próprio tamanho entre frames. Usa o box PREDITO
    /// (posição extrapolada) para casar, então o modelo de velocidade melhora a
    /// associação a cada acerto.
    func update(_ dets: [Detection], now: TimeInterval) {
        var usados = Set<Int>()

        // Agrupa os índices por label ANTES do laço de associação: cada track só
        // precisa varrer as detecções da SUA classe, em vez de todas (antes era
        // O(tracks × total_detecções); com cenas multi-classe — pessoa+carro+
        // caminhão no mesmo frame — a maior parte da varredura era descartada
        // pelo `label != label` logo de cara).
        var porLabel: [String: [Int]] = [:]
        for j in dets.indices { porLabel[dets[j].label, default: []].append(j) }

        for i in tracks.indices {
            var melhor = -1
            var menorDist = CGFloat.greatestFiniteMagnitude
            let pred = tracks[i].predictedBox(at: now)
            let cPred = Self.centro(pred)
            for j in porLabel[tracks[i].label] ?? [] where !usados.contains(j) {
                let cDet = Self.centro(dets[j].boundingBox)
                let dist = hypot(cPred.x - cDet.x, cPred.y - cDet.y)
                // gate ~ soma dos "raios" dos boxes + margem, com bônus se há IoU
                let gate = 0.6 * (max(pred.width, pred.height) + max(dets[j].boundingBox.width, dets[j].boundingBox.height)) + 0.04
                let temIoU = Self.iou(pred, dets[j].boundingBox) > 0.05
                if (dist < gate || temIoU) && dist < menorDist {
                    menorDist = dist; melhor = j
                }
            }
            if melhor >= 0 {
                usados.insert(melhor)
                let d = dets[melhor]
                let dt = max(0.001, now - tracks[i].lastUpdate)
                let c0 = Self.centro(tracks[i].box)
                let c1 = Self.centro(d.boundingBox)
                let ivx = (c1.x - c0.x) / CGFloat(dt)
                let ivy = (c1.y - c0.y) / CGFloat(dt)
                tracks[i].vx = tracks[i].vx * (1 - emaVel) + ivx * emaVel
                tracks[i].vy = tracks[i].vy * (1 - emaVel) + ivy * emaVel
                tracks[i].box = Self.lerp(tracks[i].box, d.boundingBox, emaPos)
                tracks[i].confidence = d.confidence
                tracks[i].lastUpdate = now
                tracks[i].hits += 1
                tracks[i].missed = 0
            } else {
                tracks[i].missed += 1
            }
        }

        // detecções não associadas -> novos tracks (com novo ID único)
        for j in dets.indices where !usados.contains(j) {
            let d = dets[j]
            tracks.append(TrackedObject(id: proximoId, label: d.label, confidence: d.confidence,
                                        box: d.boundingBox, vx: 0, vy: 0,
                                        lastUpdate: now, hits: 1, missed: 0))
            unicosPorClasse[d.label, default: 0] += 1
            proximoId += 1
        }

        tracks.removeAll { $0.missed > maxMissed }
    }

    /// Tracks confirmados com o box já extrapolado para `t` (taxa de display).
    func predicted(at t: TimeInterval) -> [TrackedObject] {
        tracks.compactMap { tr in
            guard tr.hits >= confirmar else { return nil }
            var c = tr
            c.box = Self.clamp(tr.predictedBox(at: t))
            return c
        }
    }

    func resetContagem() { unicosPorClasse.removeAll() }

    // MARK: - Geometria
    private static func centro(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ix = max(a.minX, b.minX), iy = max(a.minY, b.minY)
        let ax = min(a.maxX, b.maxX), ay = min(a.maxY, b.maxY)
        let iw = max(0, ax - ix), ih = max(0, ay - iy)
        let inter = iw * ih
        let uni = a.width * a.height + b.width * b.height - inter
        return uni > 0 ? inter / uni : 0
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }

    private static func clamp(_ r: CGRect) -> CGRect {
        let x = min(max(0, r.minX), 1), y = min(max(0, r.minY), 1)
        return CGRect(x: x, y: y, width: min(r.width, 1 - x), height: min(r.height, 1 - y))
    }
}
