import Foundation
import Combine
import AppKit

class CameraCardViewModel: ObservableObject {
    @Published var frameImage: NSImage?
    @Published var fps: Double = 0
    @Published var isOnline = false
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []

    let camera: Camera
    private let cameraService = CameraService()
    private let detector = DetectorService()
    private var detectTimer: Timer?
    private var frameCount = 0

    init(camera: Camera) {
        self.camera = camera
        cameraService.$currentFrame.assign(to: &$frameImage)
        cameraService.$fps.assign(to: &$fps)
        cameraService.$isRunning.assign(to: &$isOnline)
        detector.$detectionCount.assign(to: &$detectionCount)
        detector.$lastDetections.assign(to: &$lastDetections)
    }

    func start() {
        guard !cameraService.isRunning else { return }
        print("[CardVM] Starting \(camera.nome)")
        switch camera.tipo {
        case .hls, .rtsp:
            cameraService.startHLSStream(url: camera.url)
        case .local:
            cameraService.startLocalCamera()
        }
        startDetection()
    }

    func stop() {
        detectTimer?.invalidate()
        detectTimer = nil
        cameraService.stopCamera()
    }

    private func startDetection() {
        detectTimer?.invalidate()
        detectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let frame = self.cameraService.currentFrame else {
                print("[CardVM] No frame yet for \(self.camera.nome)")
                return
            }
            self.frameCount += 1
            if self.frameCount % 5 == 0 {
                print("[CardVM] Detecting frame #\(self.frameCount) for \(self.camera.nome)")
            }
            guard let copy = frame.copy() as? NSImage else { return }
            DispatchQueue.global(qos: .utility).async {
                let _ = self.detector.detectar(copy)
            }
        }
        RunLoop.main.add(detectTimer!, forMode: .default)
    }
}
