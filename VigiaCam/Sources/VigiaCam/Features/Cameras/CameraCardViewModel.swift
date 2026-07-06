import Foundation
import Combine
import AppKit

class CameraCardViewModel: ObservableObject {
    @Published var frameImage: NSImage?
    @Published var fps: Double = 0
    @Published var isOnline = false

    let camera: Camera
    private let service = CameraService()
    private var cancellables = Set<AnyCancellable>()

    init(camera: Camera) {
        self.camera = camera
        service.$currentFrame.assign(to: &$frameImage)
        service.$fps.assign(to: &$fps)
        service.$isRunning.assign(to: &$isOnline)
    }

    func start() {
        guard !service.isRunning else { return }
        switch camera.tipo {
        case .hls:
            service.startHLSStream(url: camera.url)
        case .local:
            service.startLocalCamera()
        case .rtsp:
            service.startHLSStream(url: camera.url)
        }
    }

    func stop() {
        service.stopCamera()
    }
}
