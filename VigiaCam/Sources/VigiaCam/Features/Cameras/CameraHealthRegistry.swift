import Foundation
import Combine

/// Quem está realmente recebendo frames agora.
///
/// O Dashboard mostrava `Online = total de câmeras` — um número fixo que nunca
/// refletia a realidade (com todos os streams caídos, ainda dizia "29 online").
/// Cada `CameraCardViewModel` publica aqui o estado do seu stream, e o painel lê
/// a contagem de verdade.
final class CameraHealthRegistry: ObservableObject {
    static let shared = CameraHealthRegistry()

    /// Ids (URL) das câmeras com stream vivo.
    @Published private(set) var online: Set<String> = []
    /// Ids das câmeras que já desistiram de reconectar.
    @Published private(set) var inalcancaveis: Set<String> = []

    /// Último estado JÁ REGISTRADO no histórico, por id — evita gravar o
    /// "offline" inicial de um card que acabou de nascer e ainda nem conectou.
    private var ultimoRegistrado: [String: Bool] = [:]

    private init() {}

    func atualizar(_ id: String, nome: String? = nil, online estaOnline: Bool, inalcancavel: Bool) {
        var novoOnline = online
        var novoInalc = inalcancaveis
        if estaOnline { novoOnline.insert(id) } else { novoOnline.remove(id) }
        if inalcancavel { novoInalc.insert(id) } else { novoInalc.remove(id) }
        guard novoOnline != online || novoInalc != inalcancaveis else { return }
        online = novoOnline
        inalcancaveis = novoInalc

        // Log persistente de transições online/offline (histórico de uptime).
        let rotulo = nome ?? id
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

    /// Chamado quando o card sai de cena (troca de página do videowall): sem
    /// isso, uma câmera que parou de ser exibida continuaria contando como
    /// online para sempre.
    func remover(_ id: String) {
        online.remove(id)
        inalcancaveis.remove(id)
    }
}
