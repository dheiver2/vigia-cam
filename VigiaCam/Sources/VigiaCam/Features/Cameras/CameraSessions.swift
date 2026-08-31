import Combine
import Foundation

/// Dono único do `CameraCardViewModel` de cada câmera.
///
/// Antes cada view criava o seu: o card do videowall tinha um, e abrir o
/// `CameraDetailView` da MESMA câmera criava um segundo. Isso significava dois
/// processos ffmpeg e dois detectores para o mesmo stream — e, pior, ao fechar
/// o detalhe o `stop()` daquele segundo VM derrubava recursos do primeiro:
/// parava a gravação iniciada no card, removia o provedor de snapshot de
/// evidência do AlarmService e marcava a câmera como offline no Dashboard,
/// tudo com o card ainda rodando.
///
/// Agora a sessão é compartilhada e contada por referência. Quem exibe a câmera
/// chama `adquirir`; ao sair, `liberar`. O stream só cai quando o último
/// interessado some — e mesmo aí espera um período de carência, porque
/// paginação do videowall e ronda automática (padrão 10s) reexibem a mesma
/// câmera segundos depois: sem a carência, cada volta da ronda derrubava e
/// reabria o ffmpeg, deixando o tile preto por alguns segundos.
@MainActor
final class CameraSessions {
    static let shared = CameraSessions()

    /// Sessões vivas por id de câmera.
    private var sessoes: [String: CameraCardViewModel] = [:]
    /// Quantas views estão exibindo cada câmera agora.
    private var referencias: [String: Int] = [:]
    /// Sessões sem nenhuma view, aguardando a carência antes de desligar.
    /// Guarda a tarefa de desligamento para poder cancelá-la se a câmera
    /// voltar à tela nesse meio-tempo.
    private var ociosas: [String: Task<Void, Never>] = [:]
    /// Ordem de liberação, para descartar as mais antigas quando o limite
    /// de sessões ociosas estoura.
    private var ordemOciosas: [String] = []

    /// Tempo que uma sessão sem view continua viva. Cobre a troca de página e
    /// um ciclo de ronda sem reiniciar o stream.
    private let carencia: Duration = .seconds(15)
    /// Teto de sessões ociosas retidas. Sem isso, uma ronda sobre 30 câmeras
    /// deixaria 30 ffmpeg vivos ao mesmo tempo.
    private let maxOciosas = 8

    private init() {}

    /// VM da câmera, criando e iniciando o stream se ainda não existir.
    func adquirir(_ camera: Camera) -> CameraCardViewModel {
        ociosas[camera.id]?.cancel()
        ociosas[camera.id] = nil
        ordemOciosas.removeAll { $0 == camera.id }

        let vm: CameraCardViewModel
        if let existente = sessoes[camera.id] {
            vm = existente
        } else {
            vm = CameraCardViewModel(camera: camera)
            sessoes[camera.id] = vm
        }
        referencias[camera.id, default: 0] += 1
        vm.start()          // idempotente: `start()` sai cedo se já está rodando
        return vm
    }

    /// Uma view parou de exibir a câmera. Só desliga de fato se era a última,
    /// e ainda assim depois da carência.
    func liberar(_ camera: Camera) {
        let restantes = (referencias[camera.id] ?? 1) - 1
        guard restantes <= 0 else {
            referencias[camera.id] = restantes
            return
        }
        referencias[camera.id] = nil
        agendarDesligamento(camera.id)
        aparar()
    }

    private func agendarDesligamento(_ id: String) {
        ordemOciosas.append(id)
        ociosas[id] = Task { [weak self] in
            try? await Task.sleep(for: self?.carencia ?? .seconds(15))
            guard !Task.isCancelled else { return }
            self?.desligar(id)
        }
    }

    /// Descarta as sessões ociosas mais antigas acima do teto.
    private func aparar() {
        while ordemOciosas.count > maxOciosas {
            let id = ordemOciosas.removeFirst()
            ociosas[id]?.cancel()
            ociosas[id] = nil
            desligar(id, jaRemovidoDaOrdem: true)
        }
    }

    private func desligar(_ id: String, jaRemovidoDaOrdem: Bool = false) {
        guard referencias[id] == nil else { return }   // voltou à tela: mantém
        sessoes[id]?.stop()
        sessoes[id] = nil
        ociosas[id] = nil
        if !jaRemovidoDaOrdem { ordemOciosas.removeAll { $0 == id } }
    }

    /// Há stream vivo para esta câmera? A sonda de saúde usa isto para não
    /// gastar rede sondando quem já está entregando frames.
    func temSessao(_ id: String) -> Bool { sessoes[id] != nil }

    /// Encerra tudo (usado ao sair do app e ao trocar de usuário).
    func encerrarTudo() {
        for (_, t) in ociosas { t.cancel() }
        ociosas.removeAll(); ordemOciosas.removeAll(); referencias.removeAll()
        for (_, vm) in sessoes { vm.stop() }
        sessoes.removeAll()
    }
}

/// Cola entre o ciclo de vida do SwiftUI e o refcount de `CameraSessions`.
///
/// Usado como `@StateObject`: o `wrappedValue` é avaliado uma única vez por
/// identidade de view (não a cada reconstrução do struct), e o `deinit` só roda
/// quando a view sai de cena de vez — exatamente o par adquirir/liberar que a
/// sessão espera. Reencaminha o `objectWillChange` do VM para que as views
/// continuem redesenhando como faziam com o `@StateObject` próprio.
final class CameraSessionHolder: ObservableObject {
    let vm: CameraCardViewModel
    private let camera: Camera
    private var bag: AnyCancellable?

    init(camera: Camera) {
        self.camera = camera
        // Construção de View acontece na main thread; `assumeIsolated` evita
        // tornar o init assíncrono só para satisfazer o @MainActor da sessão.
        self.vm = MainActor.assumeIsolated { CameraSessions.shared.adquirir(camera) }
        bag = vm.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    deinit {
        let c = camera
        Task { @MainActor in CameraSessions.shared.liberar(c) }
    }
}
