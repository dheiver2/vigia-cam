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
    @Published var inalcancavel = false                // desistiu de reconectar

    let camera: Camera
    /// Modelo fixado nesta câmera (`nil` = segue o global). Publicado para o
    /// seletor do CameraDetailView refletir a escolha.
    @Published var modeloFixo: TipoModelo?
    private let cameraService = CameraService()
    private let detector: DetectorService
    private let tracker = ObjectTracker()
    private let lineCounter = LineCounter()
    private let zoneMonitor = ZoneMonitor()
    private let sceneChange = SceneChangeDetector()
    private var linhaAtiva = false
    private var detectTimer: Timer?
    private var displayTimer: Timer?                  // extrapola caixas a ~15 Hz
    private var frameCount = 0
    private var displayTick = 0
    private var intrusoesTotal = 0
    private var permanenciasTotal = 0
    private var isDetecting = false
    private var bag = Set<AnyCancellable>()
    /// Carregada uma vez ao iniciar a câmera — antes a UI de Configurações (FPS
    /// Máximo, Confiança Mínima, Classes) existia mas não tinha efeito nenhum no
    /// motor de detecção real; agora `detector`/`startDetection()` a usam de fato.
    private var appConfig: AppConfig = StorageService.shared.carregarConfig()

    init(camera: Camera) {
        self.camera = camera
        let fixo = camera.modeloDeteccao.flatMap(TipoModelo.init(rawValue:))
        self.modeloFixo = fixo
        self.detector = DetectorService(tipo: fixo)
        detector.confidenceThreshold = appConfig.confianca
        detector.allowedClasses = appConfig.classesMonitoradas
        cameraService.$currentFrame.assign(to: &$frameImage)
        cameraService.$fps.assign(to: &$fps)
        cameraService.$isRunning.assign(to: &$isOnline)
        detector.$detectionCount.assign(to: &$detectionCount)
        detector.$lastDetections.assign(to: &$lastDetections)
        cameraService.$totalReconexoes.assign(to: &$reconexoes)
        cameraService.$inalcancavel.assign(to: &$inalcancavel)

        // Publica a saúde do stream para o Dashboard contar "Online" de verdade.
        cameraService.$isRunning
            .combineLatest(cameraService.$inalcancavel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rodando, inalc in
                guard let self else { return }
                CameraHealthRegistry.shared.atualizar(self.camera.id, nome: self.camera.nome,
                                                      online: rodando, inalcancavel: inalc)
            }
            .store(in: &bag)

        // detecção -> motor de alarmes (a evidência agora é capturada pelo
        // próprio motor, via snapshot provider, e fica ligada ao evento)
        detector.$detectionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] counts in
                guard let self, !counts.isEmpty else { return }
                AlarmService.shared.avaliar(camera: self.camera.nome, counts: counts)
            }
            .store(in: &bag)

        // detecção -> LPR (OCR de placas nas caixas de veículo)
        detector.$lastDetections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dets in
                guard let self, let frame = self.frameImage else { return }
                LPRService.shared.processar(frame: frame, deteccoes: dets, camera: self.camera.nome)
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

        // detecção -> mapa de calor (onde no quadro os objetos aparecem)
        detector.$lastDetections
            .sink { [weak self] dets in
                guard let self else { return }
                HeatmapService.shared.registrar(camera: self.camera.nome, deteccoes: dets)
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

    /// Fixa (ou libera, com `nil`) o modelo de detecção desta câmera e
    /// persiste a escolha em cameras.json. O detector recarrega na hora.
    func definirModelo(_ tipo: TipoModelo?) {
        modeloFixo = tipo
        detector.fixarTipo(tipo)
        var lista = StorageService.shared.carregarCameras()
        if let i = lista.firstIndex(where: { $0.id == camera.id }) {
            lista[i].modeloDeteccao = tipo?.rawValue
            StorageService.shared.salvarCameras(lista)
        }
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
        // A extração de frames passa a seguir o "FPS Máximo" das Configurações;
        // antes era fixa em 10 Hz e o ajuste não surtia efeito nenhum.
        cameraService.fpsExtracao = Double(appConfig.fpsMax)
        switch camera.tipo {
        case .hls, .rtsp:
            cameraService.startHLSStream(url: camera.url)
        case .local:
            cameraService.startLocalCamera()
        }
        carregarAnalitico()
        startDetection()
        startDisplayLoop()
        AlarmService.shared.registrarSnapshotProvider(camera: camera.nome) { [weak self] in
            self?.capturarSnapshot()
        }
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
        AlarmService.shared.removerSnapshotProvider(camera: camera.nome)
        CameraHealthRegistry.shared.remover(camera.id)
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
        // Mudança de cena: amostra o frame a cada ~5 s (75 ticks de 1/15 s).
        if displayTick % 75 == 0, let frame = frameImage, isOnline {
            if sceneChange.amostrar(frame) {
                AlarmService.shared.emitir(camera: camera.nome, titulo: "Mudança de cena",
                    mensagem: "Cena mudou bruscamente (câmera tampada/movida?) — \(camera.nome)",
                    severidade: .aviso)
            }
        }
        let eventos = zoneMonitor.update(alvos, now: now)
        for e in eventos {
            if e.tipo == .evasao {
                AlarmService.shared.emitir(camera: camera.nome, titulo: "Evasão de zona",
                    mensagem: "Alvo saiu da zona monitorada — \(camera.nome)", severidade: .aviso)
            } else if e.tipo == .ausencia {
                AlarmService.shared.emitir(camera: camera.nome, titulo: "Ausência em zona",
                    mensagem: "Zona vigiada vazia além do tolerado — \(camera.nome)", severidade: .aviso)
            } else if e.tipo == .intrusao {
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
        // Série temporal persistida (1 amostra/min por câmera) — destrava
        // relatório histórico; antes as métricas morriam com a sessão.
        if displayTick % 900 == 0 {
            let unicos = tracker.unicosPorClasse
            EventStore.shared.registrarMetrica(
                camera: camera.nome,
                entradas: lineCounter.totalEntradas, saidas: lineCounter.totalSaidas,
                ocupacao: zoneMonitor.ocupacao.values.reduce(0, +),
                intrusoes: intrusoesTotal, permanencias: permanenciasTotal,
                pessoasUnicas: (unicos["person"] ?? 0) + (unicos["Person"] ?? 0),
                veiculosUnicas: ["car", "truck", "bus", "motorcycle", "bicycle"].reduce(0) { $0 + (unicos[$1] ?? 0) })
            if let grade = HeatmapService.shared.drenar(camera: camera.nome) {
                EventStore.shared.registrarHeatmap(camera: camera.nome, colunas: HeatmapService.colunas,
                                                    linhas: HeatmapService.linhas, grade: grade)
            }
        }
    }

    private func startDetection() {
        detectTimer?.invalidate()
        // Intervalo derivado de AppConfig.fpsMax (config "FPS Máximo" da tela de
        // Configurações — antes ignorada, sempre rodava a 0.4s/2,5Hz fixo). O guard
        // `!self.isDetecting` abaixo + o semáforo global do DetectorService seguram
        // a taxa real ao que o hardware aguenta, mesmo se o usuário pedir um valor alto.
        let intervalo = 1.0 / Double(max(1, appConfig.fpsMax))
        detectTimer = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
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
        RunLoop.main.add(detectTimer!, forMode: .common)
    }
}
