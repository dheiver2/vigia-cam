import Vision
import CoreML
import AppKit
import SwiftUI

extension Notification.Name {
    /// Postada quando `ModelProvider.tipoAtivo` muda — cada `DetectorService`
    /// ativo escuta isso pra recarregar o modelo correto (ex.: trocar de
    /// nicho geral para "Canteiro de Obras" troca o `.mlpackage` inteiro,
    /// não só a lista de classes permitidas).
    static let modeloAtivoMudou = Notification.Name("modeloAtivoMudou")
}

/// Qual `.mlpackage` está ativo para todo o app. Nichos com classes fora do
/// vocabulário COCO (ex. EPI) precisam de um modelo diferente, não só de um
/// filtro de classes sobre o modelo geral.
enum TipoModelo: String, CaseIterable {
    case geral   // yolov8n.mlpackage — 80 classes COCO
    case ppe     // ppe.mlpackage — Hardhat/NO-Hardhat/Safety Vest/NO-Safety Vest/Person/...

    var arquivo: String {
        switch self {
        case .geral: return "yolov8n"
        case .ppe: return "ppe"
        }
    }
}

/// Carrega e compila o modelo YOLO ativo UMA ÚNICA vez por tipo, para todo o app.
///
/// `.mlpackage` NÃO pode ser aberto direto por `MLModel(contentsOf:)` — o
/// CoreML exige um `.mlmodelc` compilado. Aqui compilamos com
/// `MLModel.compileModel(at:)` (resultado cacheado em Application Support) e
/// reaproveitamos o mesmo `VNCoreMLModel` em todas as câmeras, em vez de pagar
/// compilação + carga N vezes (uma por card). O cache é mantido por `TipoModelo`
/// para não recompilar ao alternar entre nichos que já foram carregados antes.
enum ModelProvider {
    enum Estado { case ok(VNCoreMLModel), semArquivo, erro(String) }

    private static let lock = NSLock()
    private static var cache: [TipoModelo: Estado] = [:]

    /// Modelo ativo no app inteiro. Trocar isto dispara `.modeloAtivoMudou`
    /// para que cada `DetectorService` (um por card de câmera) recarregue.
    static var tipoAtivo: TipoModelo = .geral {
        didSet {
            guard oldValue != tipoAtivo else { return }
            NotificationCenter.default.post(name: .modeloAtivoMudou, object: nil)
        }
    }

    /// Resolução de entrada REAL do modelo, lida do próprio `.mlmodel` ao carregar
    /// (em vez de assumir 640 fixo no parsing do output — se o modelo mudar de
    /// resolução um dia, o parsing não quebra silenciosamente).
    private(set) static var inputSize: CGFloat = 640

    static func shared(tipo: TipoModelo = tipoAtivo) -> Estado {
        lock.lock(); defer { lock.unlock() }
        if let estado = cache[tipo] { return estado }
        let estado = carregar(tipo: tipo)
        cache[tipo] = estado
        return estado
    }

    private static func candidatos(tipo: TipoModelo) -> [URL] {
        var urls: [URL] = []
        let nome = tipo.arquivo
        if let u = Bundle.main.url(forResource: nome, withExtension: "mlpackage") {
            urls.append(u)
        }
        let bp = Bundle.main.bundlePath
        for p in ["/Contents/Resources/\(nome).mlpackage",
                  "/Contents/Resources/VigiaCam_VigiaCam.bundle/Contents/Resources/\(nome).mlpackage",
                  "/Contents/Resources/VigiaCam_VigiaCam.bundle/\(nome).mlpackage"] {
            urls.append(URL(fileURLWithPath: bp + p))
        }
        return urls
    }

    private static func compiladoCache(para origem: URL, tipo: TipoModelo) -> URL {
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VigiaCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: sup, withIntermediateDirectories: true)
        return sup.appendingPathComponent("\(tipo.arquivo).mlmodelc", isDirectory: true)
    }

    private static func carregar(tipo: TipoModelo) -> Estado {
        guard let origem = candidatos(tipo: tipo).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            print("[Detector] modelo \(tipo.arquivo) não encontrado no bundle")
            return .semArquivo
        }
        do {
            // reaproveita o .mlmodelc já compilado se existir (compilar é caro)
            let cacheURL = compiladoCache(para: origem, tipo: tipo)
            let compiladoURL: URL
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                compiladoURL = cacheURL
            } else {
                let tmp = try MLModel.compileModel(at: origem)
                try? FileManager.default.removeItem(at: cacheURL)
                try? FileManager.default.copyItem(at: tmp, to: cacheURL)
                compiladoURL = FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : tmp
            }
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all                 // Neural Engine + GPU + CPU
            let ml = try MLModel(contentsOf: compiladoURL, configuration: cfg)
            if let imgInput = ml.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
               let constraint = imgInput.imageConstraint {
                inputSize = CGFloat(constraint.pixelsWide)
                print("[Detector] resolução de entrada do modelo: \(Int(constraint.pixelsWide))x\(Int(constraint.pixelsHigh))")
            }
            let vn = try VNCoreMLModel(for: ml)
            print("[Detector] modelo \(tipo.arquivo) compilado e carregado")
            return .ok(vn)
        } catch {
            print("[Detector] falha ao compilar/carregar: \(error.localizedDescription)")
            return .erro(error.localizedDescription)
        }
    }
}

final class DetectorService: ObservableObject {
    @Published var isLoaded = false
    @Published var indisponivel = false          // modelo não pôde ser carregado
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []

    private var vnModel: VNCoreMLModel?
    var confidenceThreshold: Float = 0.25
    /// Classes permitidas por NOME (`AppConfig.classesMonitoradas`); `nil` =
    /// todas. Era um `Set<Int>` de índices COCO, que apontava para as classes
    /// erradas assim que o modelo ativo mudava (o de EPI tem outro vocabulário).
    var allowedClasses: Set<String>?
    /// Limiares por classe (ex.: classes com mais falso-positivo podem exigir
    /// confiança maior). `nil`/ausente na classe = usa `confidenceThreshold`.
    var perClassThresholds: [String: Float] = [:]
    private let iouThreshold: Float = 0.45
    /// Threshold usado só para JUNTAR candidatos antes da NMS/fusão — mais
    /// baixo que `confidenceThreshold` para não descartar cedo demais uma
    /// detecção fraca que a fusão com vizinhos ou o tracker ainda podem
    /// confirmar. O corte "de verdade" continua sendo `confidenceThreshold`,
    /// aplicado depois da fusão.
    private var limiarColeta: Float { max(0.10, confidenceThreshold - 0.15) }
    private let queue = DispatchQueue(label: "detector")

    /// Limita quantas inferências CoreML rodam ao mesmo tempo em TODAS as câmeras.
    /// Sem isso, um videowall 4×4 dispara até 16 inferências concorrentes disputando
    /// o Neural Engine/GPU sem nenhum controle de throughput.
    private static let inferenceSemaphore = DispatchSemaphore(
        value: max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    )

    /// Vocabulário agora vive em `ClassesModelo.swift` (dado de domínio puro,
    /// testável sem CoreML). Mantido como alias pelos pontos de uso.
    static let cocoLabels = ClassesCOCO.nomes

    /// Classes do modelo de EPI (`ppe.mlpackage`), na ordem exata do índice de
    /// saída do modelo (0..9) — confirmada via `model.names` no export ultralytics.
    static let ppeLabels = ClassesEPI.nomes

    /// Labels do modelo ATUALMENTE ativo (`ModelProvider.tipoAtivo`) — não é
    /// mais sempre `cocoLabels`, porque nichos como Canteiro de Obras usam um
    /// `.mlpackage` diferente com vocabulário próprio.
    private var labels: [String] {
        ModelProvider.tipoAtivo == .ppe ? Self.ppeLabels : Self.cocoLabels
    }

    private static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, .yellow, .teal, .indigo,
        .brown, .cyan, .mint
    ]

    static func color(for label: String) -> Color {
        palette[abs(label.hashValue) % palette.count]
    }

    init() {
        loadModel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(modeloMudou),
            name: .modeloAtivoMudou, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func modeloMudou() {
        vnModel = nil
        detectionCount = [:]
        lastDetections = []
        loadModel()
    }

    private func loadModel() {
        let tipo = ModelProvider.tipoAtivo
        queue.async { [weak self] in
            guard let self else { return }
            switch ModelProvider.shared(tipo: tipo) {
            case .ok(let vn):
                self.vnModel = vn
                DispatchQueue.main.async { self.isLoaded = true; self.indisponivel = false }
            case .semArquivo, .erro:
                DispatchQueue.main.async { self.isLoaded = false; self.indisponivel = true }
            }
        }
    }

    func detectar(_ image: NSImage) -> [Detection] {
        guard let vnModel, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        // Use VNCoreMLRequest — it handles imageType input automatically
        let request = VNCoreMLRequest(model: vnModel)
        // .scaleFill esticava a imagem pro quadrado do modelo (ex. 640×640),
        // distorcendo o aspect ratio de frames RTSP 16:9 — o objeto ficava
        // "achatado" e o YOLO (treinado com letterbox) perdia precisão de
        // classe e de caixa. .scaleFit + padding (letterbox) preserva a
        // proporção; a compensação do padding é refeita manualmente em
        // `parseYOLOOutput` a partir do tamanho real do frame.
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        Self.inferenceSemaphore.wait()
        defer { Self.inferenceSemaphore.signal() }
        do {
            try handler.perform([request])
        } catch {
            print("[Detector] VNImageRequestHandler error: \(error)")
            return []
        }

        // Check if we got VNRecognizedObjectObservation (model has NMS)
        if let objectResults = request.results as? [VNRecognizedObjectObservation], !objectResults.isEmpty {
            print("[Detector] Got \(objectResults.count) VNRecognizedObjectObservation")
            let dets = objectResults.compactMap { obs -> Detection? in
                guard let label = obs.labels.first?.identifier, obs.labels.first!.confidence >= confidenceThreshold else { return nil }
                if let allowed = allowedClasses, !allowed.contains(label) { return nil }
                return Detection(label: label, confidence: obs.labels.first!.confidence, boundingBox: obs.boundingBox)
            }
            updateUI(dets)
            return dets
        }

        // Raw output: look for VNCoreMLFeatureValueObservation
        guard let featureResults = request.results as? [VNCoreMLFeatureValueObservation] else {
            print("[Detector] No results. Results type: \(type(of: request.results))")
            return []
        }

        for feat in featureResults {
            if let mlArray = feat.featureValue.multiArrayValue {
                print("[Detector] Feature '\(feat.featureName)' shape: \(mlArray.shape)")
                let dets = parseYOLOOutput(mlArray, origW: CGFloat(cgImage.width), origH: CGFloat(cgImage.height))
                updateUI(dets)
                return dets
            }
        }

        print("[Detector] No multiarray found in results")
        return []
    }

    private func parseYOLOOutput(_ mlArray: MLMultiArray, origW: CGFloat, origH: CGFloat) -> [Detection] {
        let ptr = mlArray.dataPointer.bindMemory(to: Float32.self, capacity: mlArray.count)
        let count = mlArray.count
        // YOLOv8: output [1, 4+numClasses, numDetections] ou [4+numClasses, numDetections]
        // Layout: (4+numClasses) rows × numDetections cols
        // Rows 0-3: cx, cy, w, h
        // Rows 4..(4+numClasses-1): class scores
        // numClasses varia por modelo ativo (80 no geral, 10 no de EPI) — não é
        // mais fixo em 84/80, senão o parsing quebra ao trocar de `.mlpackage`.
        let numClasses = labels.count
        let numDetections = count / (4 + numClasses)
        guard numDetections > 0 else { return [] }

        // Compensação do letterbox (.scaleFit): o frame original (origW×origH,
        // geralmente 16:9) foi redimensionado preservando proporção e
        // centralizado dentro do quadrado N×N do modelo, sobrando faixas de
        // padding. Sem desfazer isso aqui, os boxes saem deslocados/menores
        // que o objeto real assim que a câmera não é quadrada.
        let n = CGFloat(ModelProvider.inputSize)
        let escala = min(n / max(origW, 1), n / max(origH, 1))
        let novaW = origW * escala, novaH = origH * escala
        let padX = (n - novaW) / 2, padY = (n - novaH) / 2

        // Coleta com limiar mais permissivo que o de exibição: a fusão de
        // caixas (WBF) e o tracker (hits consecutivos) filtram o ruído extra
        // depois, então baixar aqui só aumenta o recall de objetos fracos que
        // seriam perdidos cedo demais.
        let limiar = limiarColeta
        var candidates: [(label: String, confidence: Float, box: CGRect)] = []

        for i in 0..<numDetections {
            let cxM = CGFloat(ptr[0 * numDetections + i])
            let cyM = CGFloat(ptr[1 * numDetections + i])
            let wM  = CGFloat(ptr[2 * numDetections + i])
            let hM  = CGFloat(ptr[3 * numDetections + i])

            var bestScore: Float = 0
            var bestClass = -1
            for c in 0..<numClasses {
                let score = ptr[(4 + c) * numDetections + i]
                if score > bestScore {
                    bestScore = score
                    bestClass = c
                }
            }

            if bestClass < 0 || bestScore < limiar { continue }
            let nomeClasse = bestClass < labels.count ? labels[bestClass] : "class_\(bestClass)"
            if let allowed = allowedClasses, !allowed.contains(nomeClasse) { continue }

            // Remove o padding do letterbox e volta pro espaço de pixels do
            // frame original antes de normalizar.
            let cxOrig = (cxM - padX) / escala
            let cyOrig = (cyM - padY) / escala
            let wOrig  = wM / escala
            let hOrig  = hM / escala

            // Convenção Vision: origem no canto INFERIOR-esquerdo, normalizada
            // pelas dimensões REAIS do frame (não mais pela resolução do modelo).
            let x1 = (cxOrig - wOrig / 2) / origW
            let y1 = (origH - (cyOrig + hOrig / 2)) / origH
            let bw = wOrig / origW
            let bh = hOrig / origH

            guard bw > 0, bh > 0, bw < 1, bh < 1 else { continue }

            candidates.append((label: nomeClasse, confidence: bestScore,
                box: CGRect(x: x1, y: y1, width: bw, height: bh)))
        }

        print("[Detector] Raw candidates: \(candidates.count)")
        let result = nms(candidates)
        print("[Detector] After NMS: \(result.count)")
        return result
    }

    private func updateUI(_ detections: [Detection]) {
        var counts: [String: Int] = [:]
        for d in detections { counts[d.label, default: 0] += 1 }
        DispatchQueue.main.async {
            self.detectionCount = counts
            self.lastDetections = detections
        }
    }

    /// Limiar de IoU adaptado ao tamanho da caixa: objetos grandes (câmera
    /// perto/veículos) toleram mais sobreposição legítima entre duas detecções
    /// distintas do que objetos pequenos, onde a mesma folga já indica
    /// duplicata. Fixo em 0.45 para tudo cortava caixas boas de objetos grandes
    /// e deixava passar duplicatas de objetos pequenos.
    private func iouAdaptativo(_ a: CGRect, _ b: CGRect) -> Float {
        let area = Float(max(a.width * a.height, b.width * b.height))
        return Float(iouThreshold) + min(0.15, area * 0.3)
    }

    /// Soft-NMS + fusão ponderada de caixas (WBF-lite), no lugar da NMS "dura"
    /// original: em vez de simplesmente descartar toda detecção sobreposta à
    /// de maior confiança, (1) o score da sobreposta é atenuado por um decaimento
    /// gaussiano proporcional ao IoU — só cai fora se ficar realmente redundante —
    /// e (2) a caixa final é a MÉDIA ponderada por confiança de todas as caixas
    /// do cluster, não apenas a de maior score isolada, o que melhora a
    /// localização (menos "caixa levemente errada porque a de maior confiança
    /// não era a mais bem enquadrada").
    private func nms(_ candidates: [(label: String, confidence: Float, box: CGRect)]) -> [Detection] {
        var pool = candidates
        var resultado: [(label: String, confidence: Float, box: CGRect)] = []

        while !pool.isEmpty {
            pool.sort { $0.confidence > $1.confidence }
            let ancora = pool.removeFirst()
            var cluster: [(label: String, confidence: Float, box: CGRect)] = [ancora]
            var restante: [(label: String, confidence: Float, box: CGRect)] = []

            for cand in pool {
                guard cand.label == ancora.label else { restante.append(cand); continue }

                let ix = max(ancora.box.minX, cand.box.minX)
                let iy = max(ancora.box.minY, cand.box.minY)
                let iw = max(CGFloat(0), min(ancora.box.maxX, cand.box.maxX) - ix)
                let ih = max(CGFloat(0), min(ancora.box.maxY, cand.box.maxY) - iy)
                let inter = iw * ih
                let union = ancora.box.width * ancora.box.height + cand.box.width * cand.box.height - inter
                let iou = union > 0 ? Float(inter / union) : 0

                let limiar = iouAdaptativo(ancora.box, cand.box)
                if iou <= 0.05 {
                    restante.append(cand)
                } else if iou > limiar {
                    cluster.append(cand)   // funde: é a mesma detecção duplicada
                } else {
                    // decaimento gaussiano (soft-NMS): não descarta de graça,
                    // só reduz a confiança proporcionalmente à sobreposição.
                    let sigma: Float = 0.5
                    let atenuado = cand.confidence * exp(-(iou * iou) / sigma)
                    if atenuado >= limiarColeta {
                        restante.append((label: cand.label, confidence: atenuado, box: cand.box))
                    }
                }
            }

            let pesoTotal = cluster.reduce(Float(0)) { $0 + $1.confidence }
            let boxFundida: CGRect
            if pesoTotal > 0 {
                let x = cluster.reduce(CGFloat(0)) { $0 + $1.box.minX * CGFloat($1.confidence) } / CGFloat(pesoTotal)
                let y = cluster.reduce(CGFloat(0)) { $0 + $1.box.minY * CGFloat($1.confidence) } / CGFloat(pesoTotal)
                let w = cluster.reduce(CGFloat(0)) { $0 + $1.box.width * CGFloat($1.confidence) } / CGFloat(pesoTotal)
                let h = cluster.reduce(CGFloat(0)) { $0 + $1.box.height * CGFloat($1.confidence) } / CGFloat(pesoTotal)
                boxFundida = CGRect(x: x, y: y, width: w, height: h)
            } else {
                boxFundida = ancora.box
            }
            resultado.append((label: ancora.label, confidence: cluster.map(\.confidence).max() ?? ancora.confidence, box: boxFundida))
            pool = restante
        }

        // Corte final "de exibição": a coleta e o soft-NMS trabalharam com um
        // limiar mais baixo (`limiarColeta`) de propósito; só agora aplicamos
        // o threshold real (global ou por classe).
        return resultado
            .filter { $0.confidence >= (perClassThresholds[$0.label] ?? confidenceThreshold) }
            .map { Detection(label: $0.label, confidence: $0.confidence, boundingBox: $0.box) }
    }
}

struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}
