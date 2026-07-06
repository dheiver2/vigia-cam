import Vision
import CoreML
import AppKit
import SwiftUI

/// Detecção de objetos via CoreML (YOLOv8n) ou Vision fallback.
final class DetectorService: ObservableObject {
    @Published var isLoaded = false
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []

    private var model: VNCoreMLModel?
    private var yoloRequest: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "detector.inference")

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

    private static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, .yellow, .teal, .indigo, .brown,
        .cyan, .mint, .red.opacity(0.7), .blue.opacity(0.7), .green.opacity(0.7)
    ]

    static func color(for label: String) -> Color {
        let idx = abs(label.hashValue) % palette.count
        return palette[idx]
    }

    init() { loadModel() }

    private func loadModel() {
        queue.async { [weak self] in
            guard let self else { return }
            if let url = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc"),
               let ml = try? MLModel(contentsOf: url),
               let vn = try? VNCoreMLModel(for: ml) {
                self.model = vn
                self.yoloRequest = VNCoreMLRequest(model: vn) { [weak self] req, _ in
                    guard let results = req.results as? [VNRecognizedObjectObservation] else { return }
                    self?.handleYOLOResults(results)
                }
                self.yoloRequest?.imageCropAndScaleOption = .scaleFill
                DispatchQueue.main.async { self.isLoaded = true }
                print("[Detector] YOLOv8n loaded")
                return
            }
            print("[Detector] No model — using Vision fallback")
            DispatchQueue.main.async { self.isLoaded = true }
        }
    }

    func detectar(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        if let request = yoloRequest {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return
        }

        // Vision fallback — 1 request only (scene classification)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let classifyReq = VNClassifyImageRequest()
        try? handler.perform([classifyReq])

        var detections: [Detection] = []
        if let results = classifyReq.results {
            for obs in results where obs.confidence > 0.25 {
                detections.append(Detection(
                    label: obs.identifier,
                    confidence: obs.confidence,
                    boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
                ))
            }
        }

        // Animals
        let animalReq = VNRecognizeAnimalsRequest()
        try? handler.perform([animalReq])
        if let results = animalReq.results {
            for obs in results {
                let label = obs.labels.first?.identifier ?? "animal"
                let conf = obs.labels.first?.confidence ?? 0
                detections.append(Detection(label: label, confidence: conf, boundingBox: obs.boundingBox))
            }
        }

        processDetections(detections)
    }

    private func handleYOLOResults(_ results: [VNRecognizedObjectObservation]) {
        var counts: [String: Int] = [:]
        var dets: [Detection] = []
        for obs in results {
            guard let top = obs.labels.first else { continue }
            counts[top.identifier, default: 0] += 1
            dets.append(Detection(label: top.identifier, confidence: top.confidence, boundingBox: obs.boundingBox))
        }
        DispatchQueue.main.async {
            self.detectionCount = counts
            self.lastDetections = dets
        }
    }

    private func processDetections(_ detections: [Detection]) {
        var counts: [String: Int] = [:]
        for d in detections { counts[d.label, default: 0] += 1 }
        DispatchQueue.main.async {
            self.detectionCount = counts
            self.lastDetections = detections
        }
    }
}

struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}
