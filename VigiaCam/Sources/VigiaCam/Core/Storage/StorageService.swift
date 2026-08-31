import Foundation
import Combine

/// Serviço de armazenamento local — equivalente ao servicos.py.
final class StorageService: ObservableObject {
    static let shared = StorageService()

    // MARK: - Paths (~/VigiaCam on device = Documents/VigiaCam)

    private let base: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("VigiaCam", isDirectory: true)
    }()

    var dirGravacoes: URL { base.appendingPathComponent("gravacoes", isDirectory: true) }
    var dirCapturas: URL { base.appendingPathComponent("capturas", isDirectory: true) }
    var dirEventos: URL { base.appendingPathComponent("eventos", isDirectory: true) }
    var arquivoAuditoria: URL { base.appendingPathComponent("auditoria.jsonl") }
    var arquivoCadeia: URL { base.appendingPathComponent("cadeia_custodia.jsonl") }
    var arquivoConfig: URL { base.appendingPathComponent("config.json") }
    var arquivoCameras: URL { base.appendingPathComponent("cameras.json") }

    init() {
        prepararDiretorios()
    }

    func prepararDiretorios() {
        let fm = FileManager.default
        for dir in [base, dirGravacoes, dirCapturas, dirEventos] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Caminhos de evidência (organizados por câmera/dia)

    private func slug(_ nome: String) -> String {
        let permitido = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let s = String(nome.unicodeScalars.map { permitido.contains($0) ? Character($0) : "-" })
        let limpo = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return limpo.isEmpty ? "camera" : limpo
    }

    func caminhoGravacao(camera: String) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let dia = f.string(from: Date())
        let dir = dirGravacoes.appendingPathComponent(slug(camera)).appendingPathComponent(dia)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        f.dateFormat = "HHmmss"
        return dir.appendingPathComponent("\(f.string(from: Date())).mp4")
    }

    func caminhoCaptura(camera: String) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let dir = dirCapturas.appendingPathComponent(f.string(from: Date()))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        f.dateFormat = "HHmmss"
        return dir.appendingPathComponent("\(slug(camera))-\(f.string(from: Date())).png")
    }

    // MARK: - Raw File I/O

    func salvarRaw(_ data: Data, para filename: String) {
        let url = base.appendingPathComponent(filename)
        let tmp = base.appendingPathComponent(filename + ".tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tmp, to: url)
        } catch {
            print("[StorageService] erro ao salvar \(filename): \(error)")
        }
    }

    func carregarRaw(_ filename: String) -> Data? {
        let url = base.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    // MARK: - JSON (encrypted at rest)

    func salvarJSONCriptografado<T: Encodable>(_ dados: T, para filename: String) {
        guard let data = try? JSONEncoder().encode(dados) else { return }
        // Se cifrar falhar, NÃO grava: escrever vazio por cima apagaria o
        // arquivo bom que já estava lá.
        guard let encrypted = CryptoService.encryptOrNil(data) else { return }
        salvarRaw(encrypted, para: filename)
    }

    func carregarJSONCriptografado<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
        guard let encrypted = carregarRaw(filename) else { return nil }
        guard let data = CryptoService.decrypt(encrypted),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            // O arquivo existe mas não abre. Quem chama trata `nil` como "vazio"
            // e regrava o padrão por cima — então guarda uma cópia antes, senão
            // o dado do usuário some sem deixar rastro.
            let backup = base.appendingPathComponent(filename + ".ilegivel")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: base.appendingPathComponent(filename), to: backup)
            print("[StorageService] \(filename) ilegível — cópia salva em \(backup.lastPathComponent)")
            return nil
        }
        return decoded
    }

    // MARK: - Config

    func salvarConfig(_ config: AppConfig) {
        salvarJSONCriptografado(config, para: "config.json")
    }

    func carregarConfig() -> AppConfig {
        carregarJSONCriptografado("config.json", as: AppConfig.self) ?? .default
    }

    // MARK: - Cameras

    /// Incrementado a cada gravação de `cameras.json`. As telas que mantêm a
    /// lista em `@State` (carregada só no `.onAppear`) observam isto para
    /// recarregar — senão adicionar/remover uma câmera em Configurações só
    /// aparecia no Ao Vivo/Dashboard depois de reiniciar o app.
    @Published private(set) var camerasVersao = 0

    func salvarCameras(_ cameras: [Camera]) {
        salvarJSONCriptografado(cameras, para: "cameras.json")
        if Thread.isMainThread { camerasVersao &+= 1 }
        else { DispatchQueue.main.async { self.camerasVersao &+= 1 } }
    }

    func carregarCameras() -> [Camera] {
        var loaded = carregarJSONCriptografado("cameras.json", as: [Camera].self) ?? []
        // Expurga câmeras de seeds antigos cujos servidores morreram (ex. o
        // lote SDOT de Seattle) — senão instalações antigas ficam presas a
        // dezenas de tiles OFFLINE para sempre.
        let semMortas = loaded.filter { cam in
            !CamerasSeed.hostsMortos.contains { cam.url.contains($0) }
        }
        if semMortas.count != loaded.count {
            loaded = semMortas
            salvarCameras(loaded)
        }
        if loaded.isEmpty {
            let defaults = CamerasSeed.publicas
            salvarCameras(defaults)
            return defaults
        }
        // Mescla câmeras padrão novas (adicionadas em versões depois do 1º uso,
        // ex. o lote de demonstração "Trânsito / Demo") que ainda não estão no
        // arquivo persistido — por id (url), sem sobrescrever nada já salvo.
        let idsExistentes = Set(loaded.map { $0.id })
        let novas = CamerasSeed.publicas.filter { !idsExistentes.contains($0.id) }
        guard !novas.isEmpty else { return loaded }
        let mesclado = loaded + novas
        salvarCameras(mesclado)
        return mesclado
    }

    // MARK: - Event History (CSV)

    func registrarEvento(tipo: String, camera: String, detalhe: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let filename = "eventos-\(today).csv"
        let url = dirEventos.appendingPathComponent(filename)

        let formatter2 = DateFormatter()
        formatter2.dateFormat = "HH:mm:ss"
        let hora = formatter2.string(from: Date())

        let linha = "\(today),\(hora),\(tipo),\(camera),\(detalhe)\n"

        if let fh = FileHandle(forWritingAtPath: url.path) {
            fh.seekToEndOfFile()
            fh.write(linha.data(using: .utf8)!)
            fh.closeFile()
        } else {
            let header = "data,hora,tipo,camera,detalhe\n"
            try? (header + linha).data(using: .utf8)!.write(to: url)
        }
    }

    func lerEventos(dias: Int = 1) -> [[String: String]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var eventos: [[String: String]] = []

        for i in 0..<dias {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let today = formatter.string(from: date)
            let url = dirEventos.appendingPathComponent("eventos-\(today).csv")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count > 1 else { continue }
            let headers = lines[0].components(separatedBy: ",")
            for line in lines.dropFirst() {
                let values = line.components(separatedBy: ",")
                var dict: [String: String] = [:]
                for (i, h) in headers.enumerated() {
                    dict[h] = i < values.count ? values[i] : ""
                }
                eventos.append(dict)
            }
        }
        return Array(eventos.prefix(500))
    }

    // MARK: - Audit Trail (JSONL)

    func auditar(_ acao: String, detalhe: String = "", usuario: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let reg: [String: String] = [
            "quando": formatter.string(from: Date()),
            "usuario": usuario ?? "sistema",
            "acao": acao,
            "detalhe": detalhe,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: reg),
              let line = String(data: data, encoding: .utf8) else { return }
        let entry = line + "\n"

        if let fh = FileHandle(forWritingAtPath: arquivoAuditoria.path) {
            fh.seekToEndOfFile()
            fh.write(entry.data(using: .utf8)!)
            fh.closeFile()
        } else {
            try? entry.data(using: .utf8)!.write(to: arquivoAuditoria)
        }
    }

    func lerAuditoria(maxLinhas: Int = 300) -> [[String: Any]] {
        guard let content = try? String(contentsOf: arquivoAuditoria, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let recent = Array(lines.suffix(maxLinhas))
        return recent.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj
        }
    }

    // MARK: - Chain of Custody (JSONL)

    func registrarCadeia(arquivo: String, tipo: String, camera: String, usuario: String? = nil) -> [String: Any] {
        let hash = CryptoService.sha256File(at: URL(fileURLWithPath: arquivo))
        let size = (try? FileManager.default.attributesOfItem(atPath: arquivo)[.size] as? Int) ?? 0

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let registro: [String: Any] = [
            "timestamp": formatter.string(from: Date()),
            "arquivo": (arquivo as NSString).lastPathComponent,
            "caminho_completo": arquivo,
            "tipo": tipo,
            "camera": camera,
            "usuario": usuario ?? "sistema",
            "hash_sha256": hash ?? "",
            "tamanho_bytes": size,
            "integridade": "verificado",
        ]

        if let data = try? JSONSerialization.data(withJSONObject: registro),
           let line = String(data: data, encoding: .utf8) {
            let entry = line + "\n"
            if let fh = FileHandle(forWritingAtPath: arquivoCadeia.path) {
                fh.seekToEndOfFile()
                fh.write(entry.data(using: .utf8)!)
                fh.closeFile()
            } else {
                try? entry.data(using: .utf8)!.write(to: arquivoCadeia)
            }
        }

        return registro
    }

    func lerCadeia(maxLinhas: Int = 500) -> [[String: Any]] {
        guard let content = try? String(contentsOf: arquivoCadeia, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let recent = Array(lines.suffix(maxLinhas))
        return recent.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj
        }
    }

    func verificarIntegridade(caminho: String, hashEsperado: String) -> Bool {
        CryptoService.sha256File(at: URL(fileURLWithPath: caminho)) == hashEsperado
    }

    // MARK: - Evidence Export (ZIP)

    func exportarEvidencia(arquivo: String, camera: String, descricao: String = "", usuario: String? = nil) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: arquivo) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let base = (arquivo as NSString).lastPathComponent
        guard let hash = CryptoService.sha256File(at: URL(fileURLWithPath: arquivo)) else { return nil }
        let size = (try? fileManager.attributesOfItem(atPath: arquivo)[.size] as? Int) ?? 0

        let formatter2 = DateFormatter()
        formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let metadados: [String: Any] = [
            "versao": "1.0",
            "timestamp_exportacao": formatter2.string(from: Date()),
            "usuario": usuario ?? "sistema",
            "camera": camera,
            "descricao": descricao,
            "arquivo_original": base,
            "hash_sha256": hash,
            "tamanho_bytes": size,
        ]

        let registro = registrarCadeia(arquivo: arquivo, tipo: "exportacao", camera: camera, usuario: usuario)

        let assinatura = """
        === VIGIA-CAM EVIDÊNCIA ===
        Arquivo: \(base)
        Câmera: \(camera)
        Data/Hora: \(formatter2.string(from: Date()))
        Usuário: \(usuario ?? "sistema")
        SHA-256: \(hash)
        Tamanho: \(size) bytes
        ==========================
        """

        // Monta o pacote num diretório temporário e o compacta com `ditto`,
        // o mesmo utilitário que o build.sh usa para gerar o zip de release.
        // Antes esta função criava um DIRETÓRIO chamado "evidencia-…" e o
        // chamava de ZIP (o comentário original admitia isso), e todas as
        // cópias usavam `try?`: falha nenhuma chegava a quem exportou.
        let tmpDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pacote = tmpDir.appendingPathComponent("evidencia-\(slug(camera))-\(timestamp)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tmpDir) }   // não deixa lixo no /tmp

        let destino = dirCapturas.appendingPathComponent("evidencia-\(slug(camera))-\(timestamp).zip")
        do {
            try fileManager.createDirectory(at: pacote, withIntermediateDirectories: true)
            try fileManager.copyItem(at: URL(fileURLWithPath: arquivo), to: pacote.appendingPathComponent(base))
            let metaData = try JSONSerialization.data(withJSONObject: metadados, options: .prettyPrinted)
            try metaData.write(to: pacote.appendingPathComponent("metadados.json"))
            let cadeiaData = try JSONSerialization.data(withJSONObject: registro, options: .prettyPrinted)
            try cadeiaData.write(to: pacote.appendingPathComponent("cadeia_custodia.json"))
            try assinatura.data(using: .utf8)?.write(to: pacote.appendingPathComponent("assinatura.txt"))

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--keepParent", pacote.path, destino.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                auditar("exportar_evidencia_falha", detalhe: "arquivo=\(base) ditto=\(p.terminationStatus)")
                return nil
            }
        } catch {
            auditar("exportar_evidencia_falha", detalhe: "arquivo=\(base) erro=\(error.localizedDescription)")
            return nil
        }

        auditar("exportar_evidencia", detalhe: "arquivo=\(base) camera=\(camera) zip=\(destino.lastPathComponent)")
        return destino
    }

    // MARK: - Retention Cleanup

    @discardableResult
    func limparRetencao(dias: Int) -> Int {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(max(1, dias)) * 86400)
        var removidos = 0

        // NUNCA apagar o banco de eventos nem seus arquivos auxiliares do WAL:
        // eles vivem em `dirEventos` e, se o app ficasse parado mais dias que a
        // retenção, a varredura levaria o histórico inteiro junto com os CSVs.
        let protegidos: Set<String> = ["vigia.sqlite3", "vigia.sqlite3-wal", "vigia.sqlite3-shm"]

        for raiz in [dirGravacoes, dirCapturas, dirEventos] {
            guard let enumerator = fileManager.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if protegidos.contains(url.lastPathComponent) { continue }
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = attrs.contentModificationDate,
                      modDate < cutoff else { continue }
                try? fileManager.removeItem(at: url)
                removidos += 1
            }
        }
        if removidos > 0 {
            auditar("retencao", detalhe: "removidos \(removidos) arquivo(s) com mais de \(dias) dia(s)")
        }
        return removidos
    }

    private var fm: FileManager { FileManager.default }
}
