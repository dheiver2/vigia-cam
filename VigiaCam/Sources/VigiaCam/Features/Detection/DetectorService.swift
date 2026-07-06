import Vision
import CoreML
import AppKit

/// Detecção de objetos com YOLOv8n via CoreML + Vision.
final class DetectorService: ObservableObject {
    @Published var isLoaded = false
    @Published var detectionCount: [String: Int] = [:]

    private var model: VNCoreMLModel?
    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "detector.inference")

    init() { loadModel() }

    private func loadModel() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc"),
                  let mlModel = try? MLModel(contentsOf: modelURL),
                  let vnModel = try? VNCoreMLModel(for: mlModel) else {
                DispatchQueue.main.async { self.isLoaded = false }
                return
            }
            self.model = vnModel
            self.request = VNCoreMLRequest(model: vnModel) { [weak self] request, _ in
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                self?.processResults(results)
            }
            self.request?.imageCropAndScaleOption = .scaleFill
            DispatchQueue.main.async { self.isLoaded = true }
        }
    }

    func detectar(_ image: NSImage) -> [Detection] {
        guard let request, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return []
    }

    private func processResults(_ results: [VNRecognizedObjectObservation]) {
        var counts: [String: Int] = [:]
        for obs in results {
            guard let label = obs.labels.first?.identifier else { continue }
            counts[label, default: 0] += 1
        }
        DispatchQueue.main.async { self.detectionCount = counts }
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
        let hash = abs(label.hashValue)
        return NSColor(red: CGFloat((hash % 256)) / 255.0, green: CGFloat(((hash / 256) % 256)) / 255.0, blue: CGFloat(((hash / 65536) % 256)) / 255.0, alpha: 1.0)
    }
}
