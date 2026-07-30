import Foundation
import Combine

/// Categoria selecionada em "Ao Vivo".
///
/// É um singleton (e não `@State` do `LiveWallView`) para que aplicar um nicho
/// em Negócio troque o filtro visto na aba Ao Vivo mesmo com a view recriada ao
/// navegar entre abas. Estava dentro de `Camera.swift`: um store de estado de
/// UI morando no arquivo do modelo de domínio.
final class CameraFilterStore: ObservableObject {
    static let shared = CameraFilterStore()
    @Published var categoria = "Todas"
    private init() {}
}
