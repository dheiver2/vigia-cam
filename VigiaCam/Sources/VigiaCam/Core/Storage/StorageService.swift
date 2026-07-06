import Foundation

/// Serviço de armazenamento local — equivalente ao servicos.py.
/// Gerencia diretórios, JSON criptografado, CSV de eventos, JSONL de auditoria.
final class StorageService {
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
        let encrypted = CryptoService.encrypt(data)
        salvarRaw(encrypted, para: filename)
    }

    func carregarJSONCriptografado<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
        guard let encrypted = carregarRaw(filename),
              let data = CryptoService.decrypt(encrypted),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
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

    func salvarCameras(_ cameras: [Camera]) {
        salvarJSONCriptografado(cameras, para: "cameras.json")
    }

    func carregarCameras() -> [Camera] {
        carregarJSONCriptografado("cameras.json", as: [Camera].self) ?? []
    }

    // MARK: - Event History (CSV)

    func registrarEvento(tipo: String, camera: String, detalhe: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let filename = "eventos-\(today).csv"
        let url = dirEventos.appendingPathComponent(filename)
        let fileExists = FileManager.default.fileExists(atPath: url.path)

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
            "tamanho_bytes": size ?? 0,
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
        let nomeZip = "evidencia-\(camera)-\(timestamp).zip"
        let zipURL = dirCapturas.appendingPathComponent(nomeZip)

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
            "tamanho_bytes": size ?? 0,
        ]

        let registro = registrarCadeia(arquivo: arquivo, tipo: "exportacao", camera: camera, usuario: usuario)

        let assinatura = """
        === VIGIA-CAM EVIDÊNCIA ===
        Arquivo: \(base)
        Câmera: \(camera)
        Data/Hora: \(formatter2.string(from: Date()))
        Usuário: \(usuario ?? "sistema")
        SHA-256: \(hash)
        Tamanho: \(size ?? 0) bytes
        ==========================
        """

        // Write ZIP contents to temp then move
        let tmpDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let file1 = tmpDir.appendingPathComponent(base)
        let file2 = tmpDir.appendingPathComponent("metadados.json")
        let file3 = tmpDir.appendingPathComponent("cadeia_custodia.json")
        let file4 = tmpDir.appendingPathComponent("assinatura.txt")

        try? fileManager.copyItem(at: URL(fileURLWithPath: arquivo), to: file1)
        if let metaData = try? JSONSerialization.data(withJSONObject: metadados, options: .prettyPrinted) {
            try? metaData.write(to: file2)
        }
        if let cadeiaData = try? JSONSerialization.data(withJSONObject: registro, options: .prettyPrinted) {
            try? cadeiaData.write(to: file3)
        }
        try? assinatura.data(using: .utf8)?.write(to: file4)

        // Create ZIP
        // Note: actual ZIP creation requires compression framework
        // For now, copy the file and metadata to a .zip-named directory
        // In production, use a ZIP library or libcompression
        let evidenceDir = dirCapturas.appendingPathComponent("evidencia-\(camera)-\(timestamp)")
        try? fileManager.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        try? fileManager.copyItem(at: URL(fileURLWithPath: arquivo), to: evidenceDir.appendingPathComponent(base))
        try? fileManager.copyItem(at: file2, to: evidenceDir.appendingPathComponent("metadados.json"))
        try? fileManager.copyItem(at: file3, to: evidenceDir.appendingPathComponent("cadeia_custodia.json"))
        try? fileManager.copyItem(at: file4, to: evidenceDir.appendingPathComponent("assinatura.txt"))

        auditar("exportar_evidencia", detalhe: "arquivo=\(base) camera=\(camera)")
        return evidenceDir
    }

    // MARK: - Retention Cleanup

    func limparRetencao(dias: Int) -> Int {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(max(1, dias)) * 86400)
        var removidos = 0

        for raiz in [dirGravacoes, dirCapturas, dirEventos] {
            guard let enumerator = fileManager.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = attrs.contentModificationDate,
                      modDate < cutoff else { continue }
                try? fileManager.removeItem(at: url)
                removidos += 1
            }
        }
        return removidos
    }

    private var fm: FileManager { FileManager.default }
}
