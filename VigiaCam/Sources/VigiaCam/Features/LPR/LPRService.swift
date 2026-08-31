import Foundation
import Combine
import AppKit
import Vision

/// LPR — reconhecimento de placas por OCR (Vision) sobre as caixas de veículo
/// que o YOLO já entrega. Sem modelo extra: recorta o veículo, roda
/// VNRecognizeTextRequest e filtra por formato de placa BR (Mercosul e antiga).
final class LPRService: ObservableObject {
    static let shared = LPRService()

    /// Persistido: era `= true` puro, então desligar o LPR e reabrir o app
    /// religava o serviço sozinho.
    @Published var ativo: Bool = UserDefaults.standard.object(forKey: LPRService.chaveAtivo) as? Bool ?? true {
        didSet { UserDefaults.standard.set(ativo, forKey: LPRService.chaveAtivo) }
    }
    private static let chaveAtivo = "lprAtivo"
    /// Placas lidas na sessão (para a aba Placas ao vivo).
    @Published private(set) var recentes: [EventStore.Placa] = []

    private let fila = DispatchQueue(label: "lpr", qos: .utility)
    /// Câmeras com OCR em andamento. Era um único `Bool` GLOBAL, lido na main
    /// e escrito na fila (data race), e que na prática deixava apenas UMA
    /// câmera do videowall inteiro processar por vez — com 4/9/16 tiles quase
    /// todo frame era descartado. Agora é por câmera e sob lock.
    private var ocupadas: Set<String> = []
    private let trava = NSLock()

    private func tentarOcupar(_ camera: String) -> Bool {
        trava.lock(); defer { trava.unlock() }
        return ocupadas.insert(camera).inserted
    }
    private func liberar(_ camera: String) {
        trava.lock(); ocupadas.remove(camera); trava.unlock()
    }
    private var ultimaLeitura: [String: Date] = [:]   // "placa|camera" -> debounce
    private let debounce: TimeInterval = 60
    private var eventService: EventService?

    static let classesVeiculo: Set<String> = ["car", "truck", "bus", "motorcycle"]

    // ABC1D23 (Mercosul) ou ABC1234 (antiga)
    private let padrao = try! NSRegularExpression(pattern: "\\b[A-Z]{3}[0-9][A-Z0-9][0-9]{2}\\b")

    private init() {}

    func configure(eventService: EventService) { self.eventService = eventService }

    /// Chamado pelo card com o frame atual + detecções (caixas normalizadas,
    /// origem canto inferior esquerdo — convenção Vision).
    func processar(frame: NSImage, deteccoes: [Detection], camera: String) {
        guard ativo else { return }
        let veiculos = deteccoes.filter { Self.classesVeiculo.contains($0.label) }
        guard !veiculos.isEmpty else { return }
        guard let copia = frame.copy() as? NSImage else { return }
        guard tentarOcupar(camera) else { return }
        fila.async { [weak self] in
            defer { self?.liberar(camera) }
            guard let self else { return }
            var rect = CGRect(x: 0, y: 0, width: copia.size.width, height: copia.size.height)
            guard let cg = copia.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
            for v in veiculos {
                // Caixa Vision (0–1, origem embaixo) -> pixels (origem em cima)
                let b = v.boundingBox
                let px = CGRect(
                    x: b.minX * CGFloat(cg.width),
                    y: (1 - b.maxY) * CGFloat(cg.height),
                    width: b.width * CGFloat(cg.width),
                    height: b.height * CGFloat(cg.height)
                ).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                guard px.width >= 64, px.height >= 48 else { continue }
                // A placa ocupa poucos por cento da área do veículo e fica na
                // metade de baixo. Rodar OCR na caixa inteira desperdiçava
                // resolução justamente onde os caracteres já são pequenos.
                let faixa = CGRect(x: px.minX, y: px.midY,
                                   width: px.width, height: px.height / 2)
                    .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                guard let recorte = cg.cropping(to: faixa) ?? cg.cropping(to: px) else { continue }
                self.lerPlaca(em: Self.ampliar(recorte), camera: camera)
            }
        }
    }

    private func lerPlaca(em cg: CGImage, camera: String) {
        let req = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self, let obs = request.results as? [VNRecognizedTextObservation] else { return }
            for o in obs {
                guard let cand = o.topCandidates(1).first, cand.confidence > 0.5 else { continue }
                let texto = cand.string.uppercased()
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: " ", with: "")
                let range = NSRange(texto.startIndex..., in: texto)
                for m in self.padrao.matches(in: texto, range: range) {
                    guard let r = Range(m.range, in: texto) else { continue }
                    self.registrar(placa: String(texto[r]), camera: camera)
                }
                // Sem casar direto: tenta corrigir as confusões clássicas de
                // OCR pela posição (letra vs dígito) antes de desistir —
                // "0BC1D23" e "OBC1D23" são a mesma placa lida duas vezes.
                if let corrigida = Self.normalizar(texto) {
                    let r2 = NSRange(corrigida.startIndex..., in: corrigida)
                    for m in self.padrao.matches(in: corrigida, range: r2) {
                        guard let r = Range(m.range, in: corrigida) else { continue }
                        self.registrar(placa: String(corrigida[r]), camera: camera)
                    }
                }
            }
        }
        // `.fast` perdia quase toda placa real: com o recorte já pequeno, o
        // ganho de latência não compensava o recall.
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.minimumTextHeight = 0.05
        try? VNImageRequestHandler(cgImage: cg).perform([req])
    }

    /// Dobra a resolução do recorte: o Vision precisa de altura de caractere
    /// razoável, e a placa costuma chegar com poucos pixels em stream 720p.
    private static func ampliar(_ cg: CGImage, fator: Int = 2) -> CGImage {
        let w = cg.width * fator, h = cg.height * fator
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    /// Normaliza confusões de OCR pela posição no padrão brasileiro:
    /// 1-3 são letras; 4, 6 e 7 são dígitos; 5 aceita ambos.
    static func normalizar(_ texto: String) -> String? {
        guard texto.count >= 7 else { return nil }
        let paraLetra: [Character: Character] = ["0": "O", "1": "I", "5": "S", "8": "B", "2": "Z"]
        let paraDigito: [Character: Character] = ["O": "0", "Q": "0", "I": "1", "L": "1",
                                                  "S": "5", "B": "8", "Z": "2", "G": "6"]
        var saida = ""
        var mudou = false
        for (i, c) in texto.prefix(7).enumerated() {
            switch i {
            case 0, 1, 2:
                if let n = paraLetra[c] { saida.append(n); mudou = true } else { saida.append(c) }
            case 3, 5, 6:
                if let n = paraDigito[c] { saida.append(n); mudou = true } else { saida.append(c) }
            default:
                saida.append(c)
            }
        }
        return mudou ? saida : nil
    }

    private func registrar(placa: String, camera: String) {
        let chave = "\(placa)|\(camera)"
        let agora = Date()
        if let ult = ultimaLeitura[chave], agora.timeIntervalSince(ult) < debounce { return }
        ultimaLeitura[chave] = agora

        EventStore.shared.registrarPlaca(placa, camera: camera)
        eventService?.registrar(tipo: "PLACA", camera: camera, detalhe: placa)
        DispatchQueue.main.async {
            self.recentes.insert(EventStore.Placa(id: Int64(agora.timeIntervalSince1970 * 1000),
                                                  quando: agora, camera: camera, placa: placa), at: 0)
            if self.recentes.count > 100 { self.recentes.removeLast(self.recentes.count - 100) }
        }
        // Placa na lista de interesse -> alarme crítico imediato.
        if let desc = EventStore.shared.interesse(placa) {
            let extra = desc.isEmpty ? "" : " (\(desc))"
            AlarmService.shared.emitir(camera: camera, titulo: "Placa de interesse",
                mensagem: "Placa \(placa)\(extra) detectada — \(camera)", severidade: .critico)
        }
    }
}
