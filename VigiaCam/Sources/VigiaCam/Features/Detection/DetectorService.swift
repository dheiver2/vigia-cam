import Vision
import CoreML
import AppKit

/// Detecção de objetos com YOLOv8n via CoreML + Vision.
/// Fallback: VNRecognizeAnimalsRequest + VNClassifyImageRequest quando modelo não disponível.
final class DetectorService: ObservableObject {
    @Published var isLoaded = false
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []

    private var model: VNCoreMLModel?
    private var yoloRequest: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "detector.inference")

    /// Todas as 80 classes COCO
    static let cocoLabels: [String] = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
        "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
        "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
        "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
        "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
        "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
        "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
        "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
        "hair drier", "toothbrush"
    ]

    static let labelColors: [String: NSColor] = {
        var colors: [String: NSColor] = [:]
        let palette: [NSColor] = [
            .systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple,
            .systemPink, .systemYellow, .systemTeal, .systemIndigo, .systemBrown,
            .cyan, .magenta
        ]
        for (i, label) in cocoLabels.enumerated() {
            colors[label] = palette[i % palette.count]
        }
        return colors
    }()

    init() { loadModel() }

    private func loadModel() {
        queue.async { [weak self] in
            guard let self else { return }

            // Tentar carregar YOLOv8n CoreML
            if let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc"),
               let mlModel = try? MLModel(contentsOf: modelURL),
               let vnModel = try? VNCoreMLModel(for: mlModel) {
                self.model = vnModel
                self.yoloRequest = VNCoreMLRequest(model: vnModel) { [weak self] request, _ in
                    guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                    self?.processYOLOResults(results)
                }
                self.yoloRequest?.imageCropAndScaleOption = .scaleFill
                DispatchQueue.main.async { self.isLoaded = true }
                print("[DetectorService] YOLOv8n CoreML model loaded")
                return
            }

            // Tentar carregar .mlpackage via Bundle
            if let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlpackage"),
               let mlModel = try? MLModel(contentsOf: modelURL),
               let vnModel = try? VNCoreMLModel(for: mlModel) {
                self.model = vnModel
                self.yoloRequest = VNCoreMLRequest(model: vnModel) { [weak self] request, _ in
                    guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                    self?.processYOLOResults(results)
                }
                self.yoloRequest?.imageCropAndScaleOption = .scaleFill
                DispatchQueue.main.async { self.isLoaded = true }
                print("[DetectorService] YOLOv8n mlpackage model loaded")
                return
            }

            print("[DetectorService] No CoreML model found, using Vision built-in requests")
            DispatchQueue.main.async { self.isLoaded = true }
        }
    }

    func detectar(_ image: NSImage) -> [Detection] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        // Usar YOLO se disponível
        if let request = yoloRequest {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return []
        }

        // Fallback: Vision built-in requests
        return detectarVisionBuiltIn(cgImage: cgImage)
    }

    private func detectarVisionBuiltIn(cgImage: CGImage) -> [Detection] {
        var detections: [Detection] = []
        let group = DispatchGroup()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 1. Detectar animais (cats, dogs)
        let animalReq = VNRecognizeAnimalsRequest()
        group.enter()
        DispatchQueue.global().async {
            try? handler.perform([animalReq])
            if let results = animalReq.results {
                for obs in results {
                    let label = obs.labels.first?.identifier ?? "animal"
                    let conf = obs.labels.first?.confidence ?? 0
                    detections.append(Detection(
                        label: label,
                        confidence: conf,
                        boundingBox: obs.boundingBox
                    ))
                }
            }
            group.leave()
        }

        // 2. Classificar cena
        let classifyReq = VNClassifyImageRequest()
        group.enter()
        DispatchQueue.global().async {
            try? handler.perform([classifyReq])
            if let results = classifyReq.results {
                for obs in results where obs.confidence > 0.3 {
                    detections.append(Detection(
                        label: obs.identifier,
                        confidence: obs.confidence,
                        boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                    ))
                }
            }
            group.leave()
        }

        group.wait()
        processDetections(detections)
        return detections
    }

    private func processYOLOResults(_ results: [VNRecognizedObjectObservation]) {
        var counts: [String: Int] = [:]
        var detections: [Detection] = []
        for obs in results {
            guard let topLabel = obs.labels.first else { continue }
            let label = topLabel.identifier
            let conf = topLabel.confidence
            counts[label, default: 0] += 1
            detections.append(Detection(
                label: label,
                confidence: conf,
                boundingBox: obs.boundingBox
            ))
        }
        DispatchQueue.main.async {
            self.detectionCount = counts
            self.lastDetections = detections
        }
    }

    private func processDetections(_ detections: [Detection]) {
        var counts: [String: Int] = [:]
        for d in detections {
            counts[d.label, default: 0] += 1
        }
        DispatchQueue.main.async {
            self.detectionCount = counts
            self.lastDetections = detections
        }
    }

    static func aplicarPrivacyMask(_ image: NSImage, zonas: [[CGPoint]]) -> NSImage {
        guard !zonas.isEmpty else { return image }
        let size = image.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return image
        }
        for zona in zonas {
            guard zona.count >= 3 else { continue }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.beginPath()
            ctx.move(to: zona[0])
            for point in zona.dropFirst() { ctx.addLine(to: point) }
            ctx.closePath()
            ctx.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: rep.cgImage!, size: size)
    }
}

struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

extension Detection {
    static func color(for label: String) -> NSColor {
        if let c = DetectorService.labelColors[label] { return c }
        let hash = abs(label.hashValue)
        return NSColor(red: CGFloat((hash % 256)) / 255.0, green: CGFloat(((hash / 256) % 256)) / 255.0, blue: CGFloat(((hash / 65536) % 256)) / 255.0, alpha: 1.0)
    }
}
