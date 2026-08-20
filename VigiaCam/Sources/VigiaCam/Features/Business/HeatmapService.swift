import Foundation
import SwiftUI

/// Acumula onde os objetos detectados aparecem no quadro, por câmera, numa
/// grade normalizada — a base de um mapa de calor de movimento.
///
/// Não precisa de nenhum modelo novo: reaproveita o `boundingBox` que o
/// `DetectorService` já produz (convenção Vision: origem no canto
/// inferior-esquerdo, normalizado 0–1) — só soma "quantas vezes um objeto
/// caiu nesta célula", célula por célula.
final class HeatmapService: ObservableObject {
    static let shared = HeatmapService()

    /// Resolução da grade — fina o bastante pra mostrar padrão de circulação,
    /// grossa o bastante pra não gerar milhares de células vazias em câmeras
    /// paradas na maior parte do tempo.
    static let colunas = 24
    static let linhas = 14

    /// Grade "ao vivo" desde o último drenar — usada tanto pro overlay em
    /// tempo real (`CameraDetailView`) quanto pro que vai ser persistido no
    /// próximo ciclo (`CameraCardViewModel`, mesma cadência de `registrarMetrica`).
    @Published private(set) var grades: [String: [Int]] = [:]   // câmera -> grade linear (linhas×colunas), row-major

    private let fila = DispatchQueue(label: "heatmap")
    private init() {}

    func registrar(camera: String, deteccoes: [Detection]) {
        guard !deteccoes.isEmpty else { return }
        fila.async { [self] in
            var grade = grades[camera] ?? Array(repeating: 0, count: Self.colunas * Self.linhas)
            for d in deteccoes {
                let cx = d.boundingBox.midX, cy = d.boundingBox.midY
                guard cx.isFinite, cy.isFinite else { continue }
                let col = min(Self.colunas - 1, max(0, Int(cx * CGFloat(Self.colunas))))
                // Vision: y=0 é a base do quadro. Linha 0 da grade = topo, como
                // a tela desenha — inverte pra não sair de cabeça pra baixo.
                let linha = min(Self.linhas - 1, max(0, Int((1 - cy) * CGFloat(Self.linhas))))
                grade[linha * Self.colunas + col] += 1
            }
            DispatchQueue.main.async { self.grades[camera] = grade }
        }
    }

    /// Devolve a grade acumulada da câmera e zera o acumulador — chamado na
    /// mesma cadência que `EventStore.registrarMetrica` (≈1×/min) pra
    /// persistir um "bucket" de tempo por vez, sem preservar estado cumulativo
    /// (some da complexidade de detectar reset que `metricas` precisa ter).
    func drenar(camera: String) -> [Int]? {
        fila.sync {
            guard let grade = grades[camera], grade.contains(where: { $0 > 0 }) else {
                DispatchQueue.main.async { self.grades[camera] = nil }
                return nil
            }
            DispatchQueue.main.async { self.grades[camera] = nil }
            return grade
        }
    }

    /// Cor para uma célula, dado seu valor e o máximo da grade (0 = transparente).
    static func cor(valor: Int, maximo: Int) -> Color {
        guard valor > 0, maximo > 0 else { return .clear }
        let intensidade = min(1, Double(valor) / Double(maximo))
        // frio (azul) -> quente (vermelho), como qualquer heatmap de calor.
        return Color(hue: (1 - intensidade) * 0.6, saturation: 0.85, brightness: 0.95)
            .opacity(0.15 + intensidade * 0.55)
    }
}
