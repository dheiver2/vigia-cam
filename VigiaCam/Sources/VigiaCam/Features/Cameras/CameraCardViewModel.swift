import Foundation
import Combine
import AppKit
import QuartzCore

class CameraCardViewModel: ObservableObject {
    @Published var frameImage: NSImage?
    @Published var fps: Double = 0
    @Published var isOnline = false
    @Published var detectionCount: [String: Int] = [:]
    @Published var lastDetections: [Detection] = []
    @Published var tracked: [TrackedObject] = []      // caixas rastreadas/preditas
    @Published var unicos: [String: Int] = [:]        // contagem de objetos únicos
    @Published var reconexoes = 0                      // saúde do stream

    let camera: Camera
    private let cameraService = CameraService()
    private let detector = DetectorService()
    private let tracker = ObjectTracker()
    private var detectTimer: Timer?
    private var displayTimer: Timer?                  // extrapola caixas a ~15 Hz
    private var frameCount = 0
    private var isDetecting = false
    private var bag = Set<AnyCancellable>()

    init(camera: Camera) {
        self.camera = camera
        cameraService.$currentFrame.assign(to: &$frameImage)
        cameraService.$fps.assign(to: &$fps)
        cameraService.$isRunning.assign(to: &$isOnline)
        detector.$detectionCount.assign(to: &$detectionCount)
        detector.$lastDetections.assign(to: &$lastDetections)
        cameraService.$totalReconexoes.assign(to: &$reconexoes)

        // detecção -> motor de alarmes (+ auto-snapshot de evidência ao disparar)
        detector.$detectionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] counts in
                guard let self, !counts.isEmpty else { return }
                let disparados = AlarmService.shared.avaliar(camera: self.camera.nome, counts: counts)
                if !disparados.isEmpty && AlarmService.shared.autoSnapshot {
                    self.capturarSnapshot()   // congela a cena que gerou o alarme
                }
            }
            .store(in: &bag)

        // detecção -> rastreador (associa/atualiza tracks a cada inferência)
        detector.$lastDetections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dets in
                guard let self else { return }
                self.tracker.update(dets, now: CACurrentMediaTime())
                self.unicos = self.tracker.unicosPorClasse
            }
            .store(in: &bag)

        // frame -> gravação (quando a câmera está gravando)
        cameraService.$currentFrame
            .compactMap { $0 }
            .sink { [weak self] img in
                guard let self, RecordingService.shared.estaGravando(self.camera.nome) else { return }
                RecordingService.shared.alimentar(self.camera.nome, image: img)
            }
            .store(in: &bag)
    }

    /// Snapshot do frame atual como evidência (PNG + cadeia de custódia).
    @discardableResult
    func capturarSnapshot() -> URL? {
        guard let img = frameImage else { return nil }
        return RecordingService.shared.snapshot(img, camera: camera.nome)
    }

    /// Liga/desliga a gravação manual de clipe.
    func alternarGravacao() {
        let tamanho = frameImage?.size ?? CGSize(width: 1280, height: 720)
        RecordingService.shared.alternarGravacao(camera.nome, tamanho: tamanho,
                                                 fps: 10)
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
        startDisplayLoop()
    }

    func stop() {
        detectTimer?.invalidate(); detectTimer = nil
        displayTimer?.invalidate(); displayTimer = nil
        // finaliza gravação órfã (ex.: trocou de página do videowall gravando),
        // senão o MP4 fica sem trailer (corrompido) e o indicador REC trava.
        if RecordingService.shared.estaGravando(camera.nome) {
            RecordingService.shared.pararGravacao(camera.nome)
        }
        cameraService.stopCamera()
    }

    /// Extrapola as caixas rastreadas a ~15 Hz (independente da taxa de inferência),
    /// fazendo os rótulos acompanharem o objeto em tempo real — sem o delay/salto.
    private func startDisplayLoop() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tracked = self.tracker.predicted(at: CACurrentMediaTime())
        }
        RunLoop.main.add(displayTimer!, forMode: .common)   // .common: não pausa no scroll
    }

    private func startDetection() {
        detectTimer?.invalidate()
        // ~2,5 Hz: acompanha objetos em movimento sem empilhar inferências.
        // O YOLOv8n roda no Neural Engine em poucos ms, então o custo é baixo.
        detectTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            // pula se a inferência anterior ainda não terminou — evita fila de
            // frames velhos, que é justamente o que causa caixas "atrasadas".
            guard !self.isDetecting, let frame = self.cameraService.currentFrame else { return }
            self.isDetecting = true
            guard let copy = frame.copy() as? NSImage else { self.isDetecting = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                _ = self.detector.detectar(copy)
                self.isDetecting = false
            }
        }
        RunLoop.main.add(detectTimer!, forMode: .default)
    }
}
