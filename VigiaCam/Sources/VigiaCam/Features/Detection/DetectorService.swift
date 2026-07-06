import Vision
import CoreML
import AppKit
import SwiftUI

final class DetectorService: ObservableObject {
    @Published var isLoaded = false
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []

    private var vnModel: VNCoreMLModel?
    private let confidenceThreshold: Float = 0.25
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

            let paths = [
                Bundle.main.bundlePath + "/Contents/Resources/yolov8n.mlpackage",
                Bundle.main.bundlePath + "/Contents/Resources/VigiaCam_VigiaCam.bundle/yolov8n.mlpackage"
            ]
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    print("[Detector] Trying \(path)")
                    if let ml = try? MLModel(contentsOf: url),
                       let vn = try? VNCoreMLModel(for: ml) {
                        self.vnModel = vn
                        DispatchQueue.main.async { self.isLoaded = true }
                        print("[Detector] YOLOv8n loaded!")
                        return
                    }
                }
            }

            if let url = Bundle.main.url(forResource: "yolov8n", withExtension: "mlpackage") {
                if let ml = try? MLModel(contentsOf: url), let vn = try? VNCoreMLModel(for: ml) {
                    self.vnModel = vn
                    DispatchQueue.main.async { self.isLoaded = true }
                    print("[Detector] YOLOv8n loaded via Bundle.main")
                    return
                }
            }

            print("[Detector] Model NOT found!")
            DispatchQueue.main.async { self.isLoaded = true }
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

            let x1 = (cx - w / 2) / 640.0
            let y1 = (cy - h / 2) / 640.0
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
