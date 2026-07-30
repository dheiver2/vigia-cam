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

    private init() {}

    func atualizar(_ id: String, online estaOnline: Bool, inalcancavel: Bool) {
        var novoOnline = online
        var novoInalc = inalcancaveis
        if estaOnline { novoOnline.insert(id) } else { novoOnline.remove(id) }
        if inalcancavel { novoInalc.insert(id) } else { novoInalc.remove(id) }
        guard novoOnline != online || novoInalc != inalcancaveis else { return }
        online = novoOnline
        inalcancaveis = novoInalc
    }

    /// Chamado quando o card sai de cena (troca de página do videowall): sem
    /// isso, uma câmera que parou de ser exibida continuaria contando como
    /// online para sempre.
    func remover(_ id: String) {
        online.remove(id)
        inalcancaveis.remove(id)
    }
}
