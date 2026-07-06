import AVFoundation
import Combine
import AppKit

/// Serviço de captura de vídeo — HLS e câmera local.
final class CameraService: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var currentFrame: NSImage?
    @Published var fps: Double = 0

    private var captureSession: AVCaptureSession?
    private var sessionQueue = DispatchQueue(label: "camera.session")
    private var frameCount = 0
    private var lastFPSTime = Date()
    private var player: AVPlayer?
    private var frameTimer: Timer?

    func startLocalCamera(position: AVCaptureDevice.Position = .back) {
        sessionQueue.async { [weak self] in
            self?.setupLocalCamera(position: position)
        }
    }

    private func setupLocalCamera(position: AVCaptureDevice.Position) {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.output"))
        if session.canAddOutput(output) { session.addOutput(output) }

        self.captureSession = session
        session.startRunning()
    }

    func stopCamera() {
        frameTimer?.invalidate()
        frameTimer = nil
        player?.pause()
        player = nil
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.currentFrame = nil
                self?.fps = 0
            }
        }
    }

    func startHLSStream(url: String) {
        guard let streamURL = URL(string: url) else { return }

        let asset = AVURLAsset(url: streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.allowsExternalPlayback = false

        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        playerItem.add(videoOutput)

        self.player = avPlayer
        avPlayer.play()

        startFrameExtraction(player: avPlayer, output: videoOutput)
    }

    private func startFrameExtraction(player: AVPlayer, output: AVPlayerItemVideoOutput) {
        frameTimer?.invalidate()
        var started = false
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let currentTime = player.currentTime()
            guard output.hasNewPixelBuffer(forItemTime: currentTime),
                  let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else { return }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            DispatchQueue.main.async {
                if !started {
                    self.isRunning = true
                    started = true
                }
                self.currentFrame = image
                self.frameCount += 1
                let now = Date()
                if now.timeIntervalSince(self.lastFPSTime) >= 1.0 {
                    self.fps = Double(self.frameCount)
                    self.frameCount = 0
                    self.lastFPSTime = now
                }
            }
        }
        RunLoop.main.add(frameTimer!, forMode: .default)
    }

    func capturarSnapshot() -> NSImage? { currentFrame }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        DispatchQueue.main.async {
            self.currentFrame = image
            self.isRunning = true
            self.frameCount += 1
            let now = Date()
            if now.timeIntervalSince(self.lastFPSTime) >= 1.0 {
                self.fps = Double(self.frameCount)
                self.frameCount = 0
                self.lastFPSTime = now
            }
        }
    }
}
