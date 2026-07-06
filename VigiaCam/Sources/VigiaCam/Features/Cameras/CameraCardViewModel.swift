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
    private var cancellables = Set<AnyCancellable>()
    private var detectTimer: Timer?

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
        switch camera.tipo {
        case .hls:
            cameraService.startHLSStream(url: camera.url)
        case .local:
            cameraService.startLocalCamera()
        case .rtsp:
            cameraService.startHLSStream(url: camera.url)
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
        detectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let frame = self.cameraService.currentFrame else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let _ = self.detector.detectar(frame)
            }
        }
        RunLoop.main.add(detectTimer!, forMode: .default)
    }
}
