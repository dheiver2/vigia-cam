import Foundation
import Combine
import AppKit
import Vision

/// LPR — reconhecimento de placas por OCR (Vision) sobre as caixas de veículo
/// que o YOLO já entrega. Sem modelo extra: recorta o veículo, roda
/// VNRecognizeTextRequest e filtra por formato de placa BR (Mercosul e antiga).
final class LPRService: ObservableObject {
    static let shared = LPRService()

    @Published var ativo = true
    /// Placas lidas na sessão (para a aba Placas ao vivo).
    @Published private(set) var recentes: [EventStore.Placa] = []

    private let fila = DispatchQueue(label: "lpr", qos: .utility)
    private var ocupado = false
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
        guard ativo, !ocupado else { return }
        let veiculos = deteccoes.filter { Self.classesVeiculo.contains($0.label) }
        guard !veiculos.isEmpty else { return }
        guard let copia = frame.copy() as? NSImage else { return }
        ocupado = true
        fila.async { [weak self] in
            defer { self?.ocupado = false }
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
                guard px.width >= 64, px.height >= 48, let recorte = cg.cropping(to: px) else { continue }
                self.lerPlaca(em: recorte, camera: camera)
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
            }
        }
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([req])
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
