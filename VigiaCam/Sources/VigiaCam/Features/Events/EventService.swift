import Foundation
import Combine

/// Serviço de eventos — gerencia log de detecções e exportação.
/// Equivalente à EventosSection do Python.
final class EventService: ObservableObject {
    @Published var eventos: [Evento] = []

    private let storage: StorageService

    struct Evento: Identifiable {
        let id = UUID()
        let data: String
        let hora: String
        let tipo: String
        let camera: String
        let detalhe: String
    }

    init(storage: StorageService = .shared) {
        self.storage = storage
    }

    func registrar(tipo: String, camera: String, detalhe: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let data = formatter.string(from: Date())
        formatter.dateFormat = "HH:mm:ss"
        let hora = formatter.string(from: Date())

        let evento = Evento(data: data, hora: hora, tipo: tipo, camera: camera, detalhe: detalhe)

        DispatchQueue.main.async {
            self.eventos.insert(evento, at: 0)
            if self.eventos.count > 1000 {
                self.eventos = Array(self.eventos.prefix(500))
            }
        }

        storage.registrarEvento(tipo: tipo, camera: camera, detalhe: detalhe)
    }

    func carregarEventos(dias: Int = 1) {
        let raw = storage.lerEventos(dias: dias)
        let mapped = raw.compactMap { dict -> Evento? in
            guard let data = dict["data"],
                  let hora = dict["hora"],
                  let tipo = dict["tipo"],
                  let camera = dict["camera"] else { return nil }
            return Evento(data: data, hora: hora, tipo: tipo, camera: camera, detalhe: dict["detalhe"] ?? "")
        }
        DispatchQueue.main.async {
            self.eventos = mapped
        }
    }

    func exportarCSV() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let filename = "eventos-\(today).csv"
        let url = storage.dirEventos.appendingPathComponent(filename)

        var csv = "data,hora,tipo,camera,detalhe\n"
        for e in eventos {
            csv += "\(e.data),\(e.hora),\(e.tipo),\(e.camera),\(e.detalhe)\n"
        }

        try? csv.data(using: .utf8)?.write(to: url)
        return url
    }
}
