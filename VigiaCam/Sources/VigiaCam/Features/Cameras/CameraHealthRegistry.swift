import Foundation
import Combine

/// Quem está realmente disponível agora.
///
/// Duas fontes, com precedência: a **sessão** viva (quem está recebendo frames
/// de verdade) manda; quando não há sessão, vale o resultado da **sonda**
/// periódica (`CameraHealthMonitor`).
///
/// Antes só as sessões alimentavam este registro, e como as sessões só existem
/// enquanto a aba "Ao Vivo" está na tela, o Dashboard exibia "Online: 0" e os
/// pins do Mapa ficavam todos cinza — justamente nas telas onde o número
/// importa. Trocar um número sempre-errado-para-mais (total de câmeras) por
/// outro sempre-errado-para-menos não resolvia nada.
final class CameraHealthRegistry: ObservableObject {
    static let shared = CameraHealthRegistry()

    /// Ids das câmeras disponíveis (sessão recebendo frames ou sonda OK).
    @Published private(set) var online: Set<String> = []
    /// Ids das câmeras que desistiram de reconectar (só a sessão sabe disso).
    @Published private(set) var inalcancaveis: Set<String> = []

    private var porSessao: [String: Bool] = [:]
    private var porSonda: [String: Bool] = [:]
    private var nomes: [String: String] = [:]

    /// Último estado JÁ REGISTRADO no histórico, por id — evita gravar o
    /// "offline" inicial de uma câmera que ainda nem tentou conectar.
    private var ultimoRegistrado: [String: Bool] = [:]

    private init() {}

    /// Estado vindo de uma sessão viva (tem prioridade sobre a sonda).
    func atualizar(_ id: String, nome: String? = nil, online estaOnline: Bool, inalcancavel: Bool) {
        if let nome { nomes[id] = nome }
        porSessao[id] = estaOnline
        if inalcancavel { inalcancaveis.insert(id) } else { inalcancaveis.remove(id) }
        recomputar()
    }

    /// A sessão terminou (card saiu de cena, troca de aba). A câmera NÃO some
    /// do painel: passa a valer o que a sonda disser.
    func encerrarSessao(_ id: String) {
        porSessao[id] = nil
        inalcancaveis.remove(id)
        recomputar()
    }

    /// Resultado da sonda periódica, usado quando não há sessão.
    func atualizarSonda(_ id: String, nome: String, alcancavel: Bool) {
        nomes[id] = nome
        porSonda[id] = alcancavel
        recomputar()
    }

    /// Câmeras removidas do sistema saem de vez do painel.
    func esquecer(_ ids: Set<String>) {
        for id in ids {
            porSessao[id] = nil; porSonda[id] = nil
            nomes[id] = nil; ultimoRegistrado[id] = nil
            inalcancaveis.remove(id)
        }
        recomputar()
    }

    private func recomputar() {
        var novo: Set<String> = []
        for (id, viva) in porSessao where viva { novo.insert(id) }
        for (id, ok) in porSonda where ok && porSessao[id] == nil { novo.insert(id) }
        guard novo != online else { return }
        let entraram = novo.subtracting(online)
        let sairam = online.subtracting(novo)
        online = novo
        for id in entraram { registrarHistorico(id, online: true) }
        for id in sairam { registrarHistorico(id, online: false) }
    }

    /// Log persistente de transições (histórico de uptime).
    private func registrarHistorico(_ id: String, online estaOnline: Bool) {
        let rotulo = nomes[id] ?? id
        switch (ultimoRegistrado[id], estaOnline) {
        case (nil, true), (false, true):
            ultimoRegistrado[id] = true
            EventStore.shared.registrarStatus(camera: rotulo, online: true)
            EventStore.shared.registrar(tipo: "STATUS", camera: rotulo, detalhe: "câmera online")
        case (true, false):
            ultimoRegistrado[id] = false
            EventStore.shared.registrarStatus(camera: rotulo, online: false)
            EventStore.shared.registrar(tipo: "STATUS", camera: rotulo, detalhe: "câmera offline")
        default:
            break   // nunca esteve online — não registra o "offline" de nascença
        }
    }
}
