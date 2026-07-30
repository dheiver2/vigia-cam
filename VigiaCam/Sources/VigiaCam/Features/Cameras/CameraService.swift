import AVFoundation
import Combine
import AppKit

/// Serviço de captura de vídeo — HLS e câmera local.
final class CameraService: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var currentFrame: NSImage?
    @Published var fps: Double = 0
    @Published var totalReconexoes = 0     // saúde: quantas vezes o stream caiu
    /// Depois de `tentativasAteDesistir` quedas seguidas sem UM frame sequer, o
    /// stream é dado como inalcançável. A UI mostrava "Reconectando…" para
    /// sempre, mesmo com o host fora do ar — não dava para distinguir uma queda
    /// momentânea de uma câmera que simplesmente não existe mais.
    @Published var inalcancavel = false

    /// Taxa de extração de frames (Hz). Vinha fixa em 10 e ignorava o "FPS
    /// Máximo" das Configurações.
    var fpsExtracao: Double = 10

    private var reconectando = false
    private let tentativasAteDesistir = 5

    private var captureSession: AVCaptureSession?
    private var sessionQueue = DispatchQueue(label: "camera.session")
    private var frameCount = 0
    private var lastFPSTime = Date()
    private var player: AVPlayer?
    private var frameTimer: Timer?
    /// Caminho RTSP (via `ffmpeg`, ver `FFmpegRTSPSource`) — `AVPlayer` não
    /// suporta esse esquema, então URLs `rtsp://`/`rtsps://` nunca passam
    /// pelo `player` acima.
    private var ffmpegSource: FFmpegRTSPSource?

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
        ffmpegSource?.stop()
        ffmpegSource = nil
    }

    private static func ehRTSP(_ url: String) -> Bool {
        let esquema = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return esquema.hasPrefix("rtsp://") || esquema.hasPrefix("rtsps://")
    }

    func startHLSStream(url: String) {
        streamURL = url
        isStopped = false
        reconnectAttempts = 0
        if Self.ehRTSP(url) {
            conectarRTSP()
        } else {
            conectar()
        }
    }

    /// Caminho RTSP via `ffmpeg` (ver `FFmpegRTSPSource`) — o `AVPlayer` usado
    /// em `conectar()` só entende HLS/HTTP progressivo.
    private func conectarRTSP() {
        guard !isStopped, let urlStr = streamURL else { return }
        teardownStream()

        let source = FFmpegRTSPSource()
        ffmpegSource = source
        lastFrameDate = Date()

        source.onFrame = { [weak self] image in
            guard let self, !self.isStopped else { return }
            self.lastFrameDate = Date()
            self.reconnectAttempts = 0
            self.inalcancavel = false
            if !self.isRunning { self.isRunning = true }
            self.currentFrame = image
            self.frameCount += 1
            let now = Date()
            if now.timeIntervalSince(self.lastFPSTime) >= 1.0 {
                self.fps = Double(self.frameCount)
                self.frameCount = 0
                self.lastFPSTime = now
            }
        }
        source.onEnded = { [weak self] in self?.agendarReconexao() }
        source.start(url: urlStr, fps: fpsExtracao)
        iniciarWatchdog()
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
        RunLoop.main.add(watchdog!, forMode: .common)
    }

    private func agendarReconexao() {
        // O watchdog e o observer de status disparam de forma independente e
        // costumam detectar a MESMA queda: sem esta guarda, cada queda
        // empilhava várias reconexões, cada uma criando seu próprio AVPlayer.
        guard !isStopped, !reconectando else { return }
        reconectando = true
        teardownStream()
        let desistiu = reconnectAttempts + 1 >= tentativasAteDesistir
        DispatchQueue.main.async {
            self.isRunning = false; self.fps = 0; self.totalReconexoes += 1
            self.inalcancavel = desistiu
        }
        // backoff progressivo: 2, 4, 8… até 30s, p/ não martelar o servidor.
        let atraso = min(2.0 * pow(2.0, Double(min(reconnectAttempts, 4))), 30.0)
        reconnectAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + atraso) { [weak self] in
            guard let self else { return }
            self.reconectando = false
            if let url = self.streamURL, Self.ehRTSP(url) {
                self.conectarRTSP()
            } else {
                self.conectar()
            }
        }
    }

    private func startFrameExtraction(player: AVPlayer, output: AVPlayerItemVideoOutput) {
        frameTimer?.invalidate()
        var started = false
        let intervalo = 1.0 / max(1.0, min(fpsExtracao, 60.0))
        frameTimer = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
            guard let self else { return }
            let currentTime = player.currentTime()
            guard output.hasNewPixelBuffer(forItemTime: currentTime),
                  let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else { return }

            // Um único CIImage por frame — antes eram dois (um só para ler o
            // `.extent`), dobrando o custo de wrap do pixel buffer.
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            DispatchQueue.main.async {
                self.lastFrameDate = Date()
                self.reconnectAttempts = 0          // fluxo saudável zera o backoff
                self.inalcancavel = false
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
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    func capturarSnapshot() -> NSImage? { currentFrame }

    /// Timers agendados na RunLoop principal são retidos por ela: sem
    /// invalidá-los aqui, um card de câmera descartado continuava puxando
    /// frames e tentando reconectar para sempre.
    deinit {
        isStopped = true
        watchdog?.invalidate()
        frameTimer?.invalidate()
        statusObserver?.invalidate()
        player?.pause()
        ffmpegSource?.stop()
        captureSession?.stopRunning()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Reusa o `ciContext` da instância: criar um `CIContext()` por frame
        // reconstrói a pipeline de render a cada quadro — era o passo mais caro
        // do caminho da câmera local.
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
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
