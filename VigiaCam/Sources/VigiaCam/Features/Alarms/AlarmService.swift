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

    private let storage = StorageService.shared
    private weak var eventService: EventService?
    private var categoriaPorCamera: [String: String] = [:]
    private var ultimoDisparo: [String: Date] = [:] // debounce por regra+câmera
    private let debounce: TimeInterval = 10
    private var bannerTimer: Timer?

    private init() { regras = carregar() }

    func configure(eventService: EventService, cameras: [Camera]) {
        self.eventService = eventService
        for c in cameras { categoriaPorCamera[c.nome] = c.categoria }
    }

    // MARK: - Avaliação (chamada a cada detecção)

    func avaliar(camera: String, counts: [String: Int]) {
        let categoria = categoriaPorCamera[camera] ?? ""
        let agora = Date()
        for regra in regras where regra.ativo && regra.casaCamera(nome: camera, categoria: categoria) {
            let valor = regra.classe == "qualquer"
                ? counts.values.reduce(0, +)
                : (counts[regra.classe] ?? 0)
            guard valor >= regra.limite else { continue }
            let chave = "\(regra.id)|\(camera)"
            if let ult = ultimoDisparo[chave], agora.timeIntervalSince(ult) < debounce { continue }
            ultimoDisparo[chave] = agora
            disparar(regra: regra, camera: camera, valor: valor)
        }
    }

    private func disparar(regra: AlarmRule, camera: String, valor: Int) {
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

    private func salvar() {
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
