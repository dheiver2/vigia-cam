import Vision
import CoreML
import AppKit
import SwiftUI

/// Carrega e compila o modelo YOLOv8n UMA ÚNICA vez para todo o app.
///
/// `.mlpackage` NÃO pode ser aberto direto por `MLModel(contentsOf:)` — o
/// CoreML exige um `.mlmodelc` compilado. Aqui compilamos com
/// `MLModel.compileModel(at:)` (resultado cacheado em Application Support) e
/// reaproveitamos o mesmo `VNCoreMLModel` em todas as câmeras, em vez de pagar
/// compilação + carga N vezes (uma por card).
enum ModelProvider {
    enum Estado { case ok(VNCoreMLModel), semArquivo, erro(String) }

    private static let lock = NSLock()
    private static var cache: Estado?

    static func shared() -> Estado {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let estado = carregar()
        cache = estado
        return estado
    }

    private static func candidatos() -> [URL] {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "yolov8n", withExtension: "mlpackage") {
            urls.append(u)
        }
        let bp = Bundle.main.bundlePath
        for p in ["/Contents/Resources/yolov8n.mlpackage",
                  "/Contents/Resources/VigiaCam_VigiaCam.bundle/Contents/Resources/yolov8n.mlpackage",
                  "/Contents/Resources/VigiaCam_VigiaCam.bundle/yolov8n.mlpackage"] {
            urls.append(URL(fileURLWithPath: bp + p))
        }
        return urls
    }

    private static func compiladoCache(para origem: URL) -> URL {
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VigiaCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: sup, withIntermediateDirectories: true)
        return sup.appendingPathComponent("yolov8n.mlmodelc", isDirectory: true)
    }

    private static func carregar() -> Estado {
        guard let origem = candidatos().first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            print("[Detector] modelo não encontrado no bundle")
            return .semArquivo
        }
        do {
            // reaproveita o .mlmodelc já compilado se existir (compilar é caro)
            let cacheURL = compiladoCache(para: origem)
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
            let vn = try VNCoreMLModel(for: ml)
            print("[Detector] YOLOv8n compilado e carregado")
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
    private let iouThreshold: Float = 0.45
    private let queue = DispatchQueue(label: "detector")

    static let cocoLabels = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck",
        "boat","traffic light","fire hydrant","stop sign","parking meter","bench",
        "bird","cat","dog","horse","sheep","cow","elephant","bear","zebra",
        "giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee",
        "skis","snowboard","sports ball","kite","baseball bat","baseball glove",
        "skateboard","surfboard","tennis racket","bottle","wine glass","cup",
        "fork","knife","spoon","bowl","banana","apple","sandwich","orange",
        "broccoli","carrot","hot dog","pizza","donut","cake","chair","couch",
        "potted plant","bed","dining table","toilet","tv","laptop","mouse",
        "remote","keyboard","cell phone","microwave","oven","toaster","sink",
        "refrigerator","book","clock","vase","scissors","teddy bear",
        "hair drier","toothbrush"
    ]

    private static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, .yellow, .teal, .indigo,
        .brown, .cyan, .mint
    ]

    static func color(for label: String) -> Color {
        palette[abs(label.hashValue) % palette.count]
    }

    init() { loadModel() }

    private func loadModel() {
        queue.async { [weak self] in
            guard let self else { return }
            switch ModelProvider.shared() {
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
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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
                let dets = parseYOLOOutput(mlArray)
                updateUI(dets)
                return dets
            }
        }

        print("[Detector] No multiarray found in results")
        return []
    }

    private func parseYOLOOutput(_ mlArray: MLMultiArray) -> [Detection] {
        let ptr = mlArray.dataPointer.bindMemory(to: Float32.self, capacity: mlArray.count)
        let count = mlArray.count
        // YOLOv8: output [1, 84, 8400] or [84, 8400]
        // Layout: 84 rows × 8400 cols
        // Rows 0-3: cx, cy, w, h
        // Rows 4-83: class scores
        let numDetections = count / 84
        guard numDetections > 0 else { return [] }

        var candidates: [(label: String, confidence: Float, box: CGRect)] = []

        for i in 0..<numDetections {
            let cx = ptr[0 * numDetections + i]
            let cy = ptr[1 * numDetections + i]
            let w  = ptr[2 * numDetections + i]
            let h  = ptr[3 * numDetections + i]

            var bestScore: Float = 0
            var bestClass = -1
            for c in 0..<80 {
                let score = ptr[(4 + c) * numDetections + i]
                if score > bestScore {
                    bestScore = score
                    bestClass = c
                }
            }

            if bestScore < confidenceThreshold || bestClass < 0 { continue }

            // Convenção Vision: origem no canto INFERIOR-esquerdo, normalizada.
            // O YOLO devolve cx,cy do canto superior-esquerdo (0..640), então o
            // Y precisa ser espelhado (640 - baixo) para casar com o overlay.
            let x1 = (cx - w / 2) / 640.0
            let y1 = (640.0 - (cy + h / 2)) / 640.0
            let bw = w / 640.0
            let bh = h / 640.0

            guard bw > 0, bh > 0, bw < 1, bh < 1 else { continue }

            let label = bestClass < Self.cocoLabels.count ? Self.cocoLabels[bestClass] : "class_\(bestClass)"
            candidates.append((label: label, confidence: bestScore,
                box: CGRect(x: CGFloat(x1), y: CGFloat(y1), width: CGFloat(bw), height: CGFloat(bh))))
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

    private func nms(_ candidates: [(label: String, confidence: Float, box: CGRect)]) -> [Detection] {
        let sorted = candidates.sorted { $0.confidence > $1.confidence }
        var keep: [Detection] = []
        var suppressed = [Bool](repeating: false, count: sorted.count)

        for i in 0..<sorted.count {
            if suppressed[i] { continue }
            let a = sorted[i]
            keep.append(Detection(label: a.label, confidence: a.confidence, boundingBox: a.box))

            for j in (i+1)..<sorted.count {
                if suppressed[j] { continue }
                let b = sorted[j]
                guard a.label == b.label else { continue }

                let ix = max(a.box.minX, b.box.minX)
                let iy = max(a.box.minY, b.box.minY)
                let iw = max(CGFloat(0), min(a.box.maxX, b.box.maxX) - ix)
                let ih = max(CGFloat(0), min(a.box.maxY, b.box.maxY) - iy)
                let inter = iw * ih
                let union = a.box.width * a.box.height + b.box.width * b.box.height - inter

                if union > 0 && inter / union > CGFloat(iouThreshold) {
                    suppressed[j] = true
                }
            }
        }
        return keep
    }
}

struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}
