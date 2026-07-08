import Foundation
import Combine
import AppKit

/// Motor de alarmes: avalia cada detecção contra as regras ativas e dispara
/// ocorrências (banner ao vivo, som, registro em Eventos + auditoria).
///
/// Singleton (como StorageService) para ser alcançável por todos os cards sem
/// precisar injetar em cada ViewModel.
final class AlarmService: ObservableObject {
    static let shared = AlarmService()

    @Published var regras: [AlarmRule] = []
    @Published var recentes: [AlarmEvent] = []      // histórico da sessão (cap 200)
    @Published var banner: AlarmEvent?              // alarme em destaque (auto-some)
    @Published var somAtivo = true
    @Published var autoSnapshot = true              // captura evidência ao disparar
    @Published var webhookURL = ""                  // POST JSON em cada alarme (opcional)
    /// Classes monitoradas (vazio = todas). Ex.: só ["person","car"].
    @Published var classesMonitoradas: Set<String> = []

    private let storage = StorageService.shared
    private weak var eventService: EventService?
    private var categoriaPorCamera: [String: String] = [:]
    private var ultimoDisparo: [String: Date] = [:] // debounce por regra+câmera
    private let debounce: TimeInterval = 10
    private var bannerTimer: Timer?

    private init() { regras = carregar() }

    func monitora(_ classe: String) -> Bool {
        classesMonitoradas.isEmpty || classesMonitoradas.contains(classe)
    }

    func configure(eventService: EventService, cameras: [Camera]) {
        self.eventService = eventService
        for c in cameras { categoriaPorCamera[c.nome] = c.categoria }
    }

    // MARK: - Avaliação (chamada a cada detecção)

    /// Avalia as regras e retorna os alarmes disparados (o chamador usa isso para,
    /// por exemplo, capturar um snapshot de evidência com o frame atual).
    @discardableResult
    func avaliar(camera: String, counts: [String: Int]) -> [AlarmEvent] {
        let categoria = categoriaPorCamera[camera] ?? ""
        let agora = Date()
        var disparados: [AlarmEvent] = []
        for regra in regras where regra.ativo && regra.casaCamera(nome: camera, categoria: categoria) {
            if regra.classe != "qualquer" && !monitora(regra.classe) { continue }
            let valor = regra.classe == "qualquer"
                ? counts.filter { monitora($0.key) }.values.reduce(0, +)
                : (counts[regra.classe] ?? 0)
            guard valor >= regra.limite else { continue }
            let chave = "\(regra.id)|\(camera)"
            if let ult = ultimoDisparo[chave], agora.timeIntervalSince(ult) < debounce { continue }
            ultimoDisparo[chave] = agora
            disparados.append(disparar(regra: regra, camera: camera, valor: valor))
        }
        return disparados
    }

    /// Emite um alarme a partir de um analítico externo (zona/linha), com o
    /// mesmo caminho de banner/evento/webhook/som. Debounce por título+câmera.
    func emitir(camera: String, titulo: String, mensagem: String, severidade: Severidade) {
        let chave = "ext|\(titulo)|\(camera)"
        let agora = Date()
        if let ult = ultimoDisparo[chave], agora.timeIntervalSince(ult) < debounce { return }
        ultimoDisparo[chave] = agora
        let ev = AlarmEvent(quando: agora, regra: titulo, camera: camera,
                            mensagem: mensagem, severidade: severidade)
        DispatchQueue.main.async {
            self.recentes.insert(ev, at: 0)
            if self.recentes.count > 200 { self.recentes.removeLast(self.recentes.count - 200) }
            self.banner = ev
            self.bannerTimer?.invalidate()
            self.bannerTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                self?.banner = nil
            }
            if self.somAtivo && severidade != .info { NSSound.beep() }
        }
        eventService?.registrar(tipo: "ALARME/\(severidade.rawValue)", camera: camera, detalhe: mensagem)
        storage.auditar("alarme", detalhe: mensagem)
        enviarWebhook(ev)
    }

    @discardableResult
    private func disparar(regra: AlarmRule, camera: String, valor: Int) -> AlarmEvent {
        let alvo = regra.classe == "qualquer" ? "objetos" : regra.classe
        let msg = "\(regra.nome) — \(valor) \(alvo) em \(camera)"
        let ev = AlarmEvent(quando: Date(), regra: regra.nome, camera: camera,
                            mensagem: msg, severidade: regra.severidade)
        DispatchQueue.main.async {
            self.recentes.insert(ev, at: 0)
            if self.recentes.count > 200 { self.recentes.removeLast(self.recentes.count - 200) }
            self.banner = ev
            self.bannerTimer?.invalidate()
            self.bannerTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                self?.banner = nil
            }
            if self.somAtivo && regra.severidade != .info { NSSound.beep() }
        }
        eventService?.registrar(tipo: "ALARME/\(regra.severidade.rawValue)", camera: camera, detalhe: msg)
        storage.auditar("alarme", detalhe: msg)
        enviarWebhook(ev)
        return ev
    }

    /// Notificação de integração: POST JSON para um endpoint externo (SIEM,
    /// central de monitoramento, automação). Falha silenciosa, nunca bloqueia.
    private func enviarWebhook(_ ev: AlarmEvent) {
        let s = webhookURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: s), s.hasPrefix("http") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["evento": "alarme", "regra": ev.regra, "camera": ev.camera,
                                   "severidade": ev.severidade.rawValue, "mensagem": ev.mensagem,
                                   "quando": ISO8601DateFormatter().string(from: ev.quando)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - CRUD de regras (persistido em regras_alarme.json)

    func adicionar(_ regra: AlarmRule) { regras.append(regra); salvar() }
    func remover(_ regra: AlarmRule) { regras.removeAll { $0.id == regra.id }; salvar() }
    func atualizar(_ regra: AlarmRule) {
        if let i = regras.firstIndex(where: { $0.id == regra.id }) { regras[i] = regra; salvar() }
    }
    func alternarAtivo(_ regra: AlarmRule) {
        var r = regra; r.ativo.toggle(); atualizar(r)
    }

    private func salvar() { persistirRegras() }

    /// Persiste as regras atuais (usado ao aplicar um pacote de nicho).
    func persistirRegras() {
        if let data = try? JSONEncoder().encode(regras) {
            storage.salvarRaw(data, para: "regras_alarme.json")
        }
    }

    private func carregar() -> [AlarmRule] {
        guard let data = storage.carregarRaw("regras_alarme.json"),
              let r = try? JSONDecoder().decode([AlarmRule].self, from: data) else {
            return AlarmRule.exemplos
        }
        return r
    }
}
