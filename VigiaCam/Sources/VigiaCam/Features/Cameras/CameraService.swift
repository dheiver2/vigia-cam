import AVFoundation
import Combine
import AppKit

/// Serviço de captura de vídeo — HLS e câmera local.
final class CameraService: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var currentFrame: NSImage?
    @Published var fps: Double = 0
    @Published var totalReconexoes = 0     // saúde: quantas vezes o stream caiu

    private var captureSession: AVCaptureSession?
    private var sessionQueue = DispatchQueue(label: "camera.session")
    private var frameCount = 0
    private var lastFPSTime = Date()
    private var player: AVPlayer?
    private var frameTimer: Timer?

    // Reconexão / detecção de stream travado (streams públicos caem sozinhos).
    private var streamURL: String?
    private var isStopped = false
    private var reconnectAttempts = 0
    private var lastFrameDate = Date()
    private var watchdog: Timer?
    private var statusObserver: NSKeyValueObservation?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let stallTimeout: TimeInterval = 10   // sem frame por 10s => reconectar

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
        isStopped = true
        teardownStream()
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.captureSession = nil
                self?.isRunning = false
                self?.currentFrame = nil
                self?.fps = 0
            }
        }
    }

    /// Derruba player/timers do HLS sem mexer no estado de "parado" — usado
    /// tanto no stop definitivo quanto entre tentativas de reconexão.
    private func teardownStream() {
        watchdog?.invalidate(); watchdog = nil
        frameTimer?.invalidate(); frameTimer = nil
        statusObserver?.invalidate(); statusObserver = nil
        player?.pause()
        player = nil
    }

    func startHLSStream(url: String) {
        streamURL = url
        isStopped = false
        reconnectAttempts = 0
        conectar()
    }

    private func conectar() {
        guard !isStopped, let urlStr = streamURL, let streamURL = URL(string: urlStr) else { return }
        teardownStream()

        let asset = AVURLAsset(url: streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.allowsExternalPlayback = false

        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        playerItem.add(videoOutput)

        // Falha explícita do item (host fora do ar, 404, etc.) => reconecta já.
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                DispatchQueue.main.async { self?.agendarReconexao() }
            }
        }

        self.player = avPlayer
        self.lastFrameDate = Date()
        avPlayer.play()

        startFrameExtraction(player: avPlayer, output: videoOutput)
        iniciarWatchdog()
    }

    /// Vigia o fluxo de frames; se travar por `stallTimeout`, reconecta.
    private func iniciarWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.isStopped else { return }
            if Date().timeIntervalSince(self.lastFrameDate) > self.stallTimeout {
                self.agendarReconexao()
            }
        }
        RunLoop.main.add(watchdog!, forMode: .default)
    }

    private func agendarReconexao() {
        guard !isStopped else { return }
        teardownStream()
        DispatchQueue.main.async { self.isRunning = false; self.fps = 0; self.totalReconexoes += 1 }
        // backoff progressivo: 2, 4, 8… até 30s, p/ não martelar o servidor.
        let atraso = min(2.0 * pow(2.0, Double(min(reconnectAttempts, 4))), 30.0)
        reconnectAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + atraso) { [weak self] in
            self?.conectar()
        }
    }

    private func startFrameExtraction(player: AVPlayer, output: AVPlayerItemVideoOutput) {
        frameTimer?.invalidate()
        var started = false
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let currentTime = player.currentTime()
            guard output.hasNewPixelBuffer(forItemTime: currentTime),
                  let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else { return }

            guard let cgImage = self.ciContext.createCGImage(
                CIImage(cvPixelBuffer: pixelBuffer),
                from: CIImage(cvPixelBuffer: pixelBuffer).extent) else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            DispatchQueue.main.async {
                self.lastFrameDate = Date()
                self.reconnectAttempts = 0          // fluxo saudável zera o backoff
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
