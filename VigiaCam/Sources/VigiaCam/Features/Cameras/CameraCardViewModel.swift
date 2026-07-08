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
    private let lineCounter = LineCounter()
    private let zoneMonitor = ZoneMonitor()
    private var linhaAtiva = false
    private var detectTimer: Timer?
    private var displayTimer: Timer?                  // extrapola caixas a ~15 Hz
    private var frameCount = 0
    private var displayTick = 0
    private var intrusoesTotal = 0
    private var permanenciasTotal = 0
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
        carregarAnalitico()
        startDetection()
        startDisplayLoop()
    }

    /// Reconstrói linha/zonas a partir da configuração persistida da câmera.
    private func carregarAnalitico() {
        let cfg = AnalyticsConfigService.shared.config(camera.url)
        linhaAtiva = cfg.linhaAtiva
        lineCounter.a = CGPoint(x: cfg.ax, y: cfg.ay)
        lineCounter.b = CGPoint(x: cfg.bx, y: cfg.by)
        zoneMonitor.zonas = cfg.zonas
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
            let agora = CACurrentMediaTime()
            let objs = self.tracker.predicted(at: agora)
            self.tracked = objs
            self.rodarAnalitico(objs, now: agora)
        }
        RunLoop.main.add(displayTimer!, forMode: .common)   // .common: não pausa no scroll
    }

    /// Roda linha virtual + zonas sobre os objetos rastreados e reporta métricas
    /// de negócio. Centro convertido p/ convenção topo-esq (igual à config/desenho).
    private func rodarAnalitico(_ objs: [TrackedObject], now: TimeInterval) {
        let alvos = objs.map {
            Alvo(id: $0.id, classe: $0.label,
                 centro: CGPoint(x: $0.box.midX, y: 1 - $0.box.midY))
        }
        if linhaAtiva { lineCounter.update(alvos) }
        let eventos = zoneMonitor.update(alvos, now: now)
        for e in eventos {
            if e.tipo == .intrusao {
                intrusoesTotal += 1
                AlarmService.shared.emitir(camera: camera.nome, titulo: "Intrusão em zona",
                    mensagem: "Intrusão (\(e.classe)) em zona restrita — \(camera.nome)", severidade: .critico)
            } else if e.tipo == .permanencia {
                permanenciasTotal += 1
                AlarmService.shared.emitir(camera: camera.nome, titulo: "Permanência suspeita",
                    mensagem: "Permanência prolongada (\(e.classe)) — \(camera.nome)", severidade: .aviso)
            }
        }
        displayTick += 1
        if displayTick % 15 == 0 {                 // reporta ~1×/s p/ o painel
            var m = BusinessMetricsService.Metrica()
            m.unicos = tracker.unicosPorClasse
            m.entradas = lineCounter.totalEntradas
            m.saidas = lineCounter.totalSaidas
            m.ocupacao = zoneMonitor.ocupacao.values.reduce(0, +)
            m.intrusoes = intrusoesTotal
            m.permanencias = permanenciasTotal
            BusinessMetricsService.shared.reportar(camera: camera.nome, metrica: m)
        }
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
