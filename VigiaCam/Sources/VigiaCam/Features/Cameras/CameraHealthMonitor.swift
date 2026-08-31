import Foundation
import Network
import os

/// Sonda periódica de disponibilidade das câmeras.
///
/// Existe porque o estado de saúde não pode depender de a aba "Ao Vivo" estar
/// aberta: o Dashboard e o Mapa precisam saber quem está no ar mesmo sem
/// nenhum stream sendo decodificado. A sonda é barata de propósito — só
/// verifica se o endpoint responde, sem abrir stream nem rodar detecção:
///
/// - HLS/HTTP: baixa apenas o primeiro byte da playlist (`Range: bytes=0-0`).
/// - RTSP: abre uma conexão TCP na porta do endereço (554 por padrão) e fecha.
/// - Câmera local: considerada disponível (é o hardware do próprio Mac).
///
/// Câmeras com sessão viva são puladas: quem está recebendo frames já é a
/// fonte de verdade no `CameraHealthRegistry`.
@MainActor
final class CameraHealthMonitor {
    static let shared = CameraHealthMonitor()

    private var cameras: [Camera] = []
    private var tarefa: Task<Void, Never>?
    /// Intervalo entre varreduras. Alto de propósito: é um sinal de painel,
    /// não um watchdog de stream (esse já existe no CameraService).
    private let intervalo: Duration = .seconds(30)
    private let timeout: TimeInterval = 8

    private init() {}

    /// (Re)define o conjunto monitorado. Chamado na abertura e sempre que a
    /// lista de câmeras muda, para não sondar câmera já removida.
    func configurar(cameras novas: [Camera]) {
        let idsAntigos = Set(cameras.map(\.id))
        let idsNovos = Set(novas.map(\.id))
        cameras = novas
        let removidas = idsAntigos.subtracting(idsNovos)
        if !removidas.isEmpty { CameraHealthRegistry.shared.esquecer(removidas) }
        iniciar()
    }

    private func iniciar() {
        tarefa?.cancel()
        tarefa = Task { [weak self] in
            while !Task.isCancelled {
                await self?.varrer()
                try? await Task.sleep(for: self?.intervalo ?? .seconds(30))
            }
        }
    }

    func parar() { tarefa?.cancel(); tarefa = nil }

    private func varrer() async {
        let alvos = cameras.filter { !CameraSessions.shared.temSessao($0.id) }
        await withTaskGroup(of: (String, String, Bool).self) { grupo in
            for cam in alvos {
                grupo.addTask { [timeout] in
                    (cam.id, cam.nome, await Self.alcancavel(cam, timeout: timeout))
                }
            }
            for await (id, nome, ok) in grupo {
                CameraHealthRegistry.shared.atualizarSonda(id, nome: nome, alcancavel: ok)
            }
        }
    }

    private static func alcancavel(_ camera: Camera, timeout: TimeInterval) async -> Bool {
        guard let url = camera.streamURL else { return false }
        switch camera.tipo {
        case .local:
            return true
        case .hls:
            var req = URLRequest(url: url)
            req.timeoutInterval = timeout
            // Só o primeiro byte: confirma que a playlist existe sem baixar o
            // manifesto inteiro de dezenas de câmeras a cada 30s.
            req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            // Alguns CDNs de câmera pública recusam clientes sem User-Agent.
            req.setValue("Mozilla/5.0 (Macintosh) VigiaCam", forHTTPHeaderField: "User-Agent")
            guard let (_, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        case .rtsp:
            return await conectaTCP(host: url.host ?? "", porta: UInt16(url.port ?? 554),
                                    timeout: timeout)
        }
    }

    /// Handshake TCP simples: a câmera RTSP responder no socket já basta para
    /// o painel dizer "no ar" (negociar RTSP inteiro seria caro e redundante
    /// com o ffmpeg do CameraService).
    private static func conectaTCP(host: String, porta: UInt16, timeout: TimeInterval) async -> Bool {
        guard !host.isEmpty, let porta = NWEndpoint.Port(rawValue: porta) else { return false }
        let conexao = NWConnection(host: NWEndpoint.Host(host), port: porta, using: .tcp)
        return await withCheckedContinuation { cont in
            // Guarda contra dupla-resumo: ready/failed e o timeout podem
            // chegar concorrentemente, e resumir duas vezes é crash.
            let trava = NSLock()
            var respondido = false
            func responder(_ v: Bool) {
                trava.lock()
                let primeiro = !respondido
                respondido = true
                trava.unlock()
                if primeiro { conexao.cancel(); cont.resume(returning: v) }
            }
            conexao.stateUpdateHandler = { estado in
                switch estado {
                case .ready: responder(true)
                case .failed, .cancelled: responder(false)
                default: break
                }
            }
            conexao.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { responder(false) }
        }
    }
}
