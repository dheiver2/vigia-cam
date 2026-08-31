import Foundation
import SQLite3

/// Banco local de eventos, status de câmeras e placas (SQLite, sem dependências).
///
/// Substitui o histórico em CSV plano como fonte de consulta: o CSV continua
/// sendo escrito (compatibilidade com quem lê a pasta `eventos/` por fora),
/// mas busca, filtros, tratativa e séries históricas saem daqui.
final class EventStore {
    static let shared = EventStore()

    private var db: OpaquePointer?
    private let fila = DispatchQueue(label: "eventstore", qos: .utility)
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    struct Registro: Identifiable, Hashable {
        let id: Int64
        let quando: Date
        let tipo: String
        let camera: String
        let detalhe: String
        let severidade: String
        var status: String        // "aberto" | "tratado"
        var checadoPor: String
        let snapshot: String      // caminho da evidência, se houver
    }

    struct TransicaoStatus: Identifiable, Hashable {
        let id: Int64
        let quando: Date
        let camera: String
        let online: Bool
    }

    struct Placa: Identifiable, Hashable {
        let id: Int64
        let quando: Date
        let camera: String
        let placa: String
    }

    private init() {
        let url = StorageService.shared.dirEventos.appendingPathComponent("vigia.sqlite3")
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("[EventStore] falha ao abrir \(url.path)")
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("""
        CREATE TABLE IF NOT EXISTS eventos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            tipo TEXT NOT NULL,
            camera TEXT NOT NULL,
            detalhe TEXT NOT NULL DEFAULT '',
            severidade TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'aberto',
            checado_por TEXT NOT NULL DEFAULT '',
            snapshot TEXT NOT NULL DEFAULT ''
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_eventos_ts ON eventos(ts)")
        exec("CREATE INDEX IF NOT EXISTS idx_eventos_camera ON eventos(camera)")
        exec("""
        CREATE TABLE IF NOT EXISTS status_camera(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            camera TEXT NOT NULL,
            online INTEGER NOT NULL
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS placas(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            camera TEXT NOT NULL,
            placa TEXT NOT NULL
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_placas_placa ON placas(placa)")
        exec("""
        CREATE TABLE IF NOT EXISTS placas_interesse(
            placa TEXT PRIMARY KEY,
            descricao TEXT NOT NULL DEFAULT ''
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS metricas(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            camera TEXT NOT NULL,
            entradas INTEGER, saidas INTEGER, ocupacao INTEGER,
            intrusoes INTEGER, permanencias INTEGER
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_metricas_camera_ts ON metricas(camera, ts)")
        // Colunas adicionadas depois do schema original. `ADD COLUMN` erra se a
        // coluna já existir (banco que já tinha a tabela) — nesse caso é
        // esperado, então usa a variante muda em vez de `exec` (que loga erro).
        execMudo("ALTER TABLE metricas ADD COLUMN pessoas_unicas INTEGER NOT NULL DEFAULT 0")
        execMudo("ALTER TABLE metricas ADD COLUMN veiculos_unicas INTEGER NOT NULL DEFAULT 0")
        exec("""
        CREATE TABLE IF NOT EXISTS heatmap(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            camera TEXT NOT NULL,
            colunas INTEGER NOT NULL,
            linhas INTEGER NOT NULL,
            grade TEXT NOT NULL
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_heatmap_camera_ts ON heatmap(camera, ts)")
    }

    /// Como `exec`, mas sem imprimir erro — para migrações idempotentes onde
    /// "já existe" é o resultado esperado na maioria das execuções.
    private func execMudo(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            print("[EventStore] SQL: \(err.map { String(cString: $0) } ?? "?")")
            sqlite3_free(err)
        }
    }

    // MARK: - Eventos

    func registrar(tipo: String, camera: String, detalhe: String,
                   severidade: String = "", snapshot: String = "") {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO eventos(ts,tipo,camera,detalhe,severidade,snapshot) VALUES(?,?,?,?,?,?)",
                -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, tipo, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 3, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 4, detalhe, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 5, severidade, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 6, snapshot, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    /// Busca com filtros combináveis. `texto` casa tipo/câmera/detalhe.
    /// Quantos eventos desde um instante (usado no KPI "Eventos Hoje", que
    /// precisa contar a partir da meia-noite e não numa janela móvel de 24h).
    func contarDesde(_ inicio: Date) -> Int {
        fila.sync { [self] in
            guard db != nil else { return 0 }
            var stmt: OpaquePointer?
            var total = 0
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM eventos WHERE ts >= ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, inicio.timeIntervalSince1970)
                if sqlite3_step(stmt) == SQLITE_ROW { total = Int(sqlite3_column_int(stmt, 0)) }
            }
            sqlite3_finalize(stmt)
            return total
        }
    }

    /// Todas as câmeras que já geraram evento na janela — a aba Eventos
    /// montava o filtro a partir dos resultados JÁ filtrados, então escolher
    /// uma câmera eliminava as demais opções do seletor.
    func camerasDistintas(dias: Int = 7) -> [String] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            let desde = Date().addingTimeInterval(-Double(max(1, dias)) * 86400).timeIntervalSince1970
            var stmt: OpaquePointer?
            var nomes: [String] = []
            let sql = "SELECT DISTINCT camera FROM eventos WHERE ts >= ? ORDER BY camera"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, desde)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let c = sqlite3_column_text(stmt, 0) { nomes.append(String(cString: c)) }
                }
            }
            sqlite3_finalize(stmt)
            return nomes
        }
    }

    func buscar(texto: String = "", camera: String = "", tipo: String = "",
                somenteAbertos: Bool = false, dias: Int = 7, limite: Int = 1000) -> [Registro] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            var sql = "SELECT id,ts,tipo,camera,detalhe,severidade,status,checado_por,snapshot FROM eventos WHERE ts >= ?"
            var binds: [String] = []
            if !texto.isEmpty {
                sql += " AND (tipo LIKE ? OR camera LIKE ? OR detalhe LIKE ?)"
                let like = "%\(texto)%"; binds += [like, like, like]
            }
            if !camera.isEmpty { sql += " AND camera = ?"; binds.append(camera) }
            if !tipo.isEmpty { sql += " AND tipo LIKE ?"; binds.append("%\(tipo)%") }
            if somenteAbertos { sql += " AND status = 'aberto'" }
            sql += " ORDER BY ts DESC LIMIT \(max(1, limite))"

            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, Date().addingTimeInterval(-Double(dias) * 86400).timeIntervalSince1970)
            for (i, b) in binds.enumerated() {
                sqlite3_bind_text(st, Int32(i + 2), b, -1, SQLITE_TRANSIENT)
            }
            var out: [Registro] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Registro(
                    id: sqlite3_column_int64(st, 0),
                    quando: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
                    tipo: coluna(st, 2), camera: coluna(st, 3), detalhe: coluna(st, 4),
                    severidade: coluna(st, 5), status: coluna(st, 6),
                    checadoPor: coluna(st, 7), snapshot: coluna(st, 8)))
            }
            return out
        }
    }

    /// Marca a ocorrência como tratada, registrando quem checou.
    func tratar(id: Int64, usuario: String) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "UPDATE eventos SET status='tratado', checado_por=? WHERE id=?", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(st, 1, usuario, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, id)
            sqlite3_step(st); sqlite3_finalize(st)
        }
        StorageService.shared.auditar("evento_tratado", detalhe: "id=\(id)", usuario: usuario)
    }

    /// Contadores por tipo (Painel de Métricas de ocorrências).
    func contagemPorTipo(dias: Int = 7) -> [(String, Int)] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT tipo, COUNT(*) FROM eventos WHERE ts >= ? GROUP BY tipo ORDER BY 2 DESC",
                -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, Date().addingTimeInterval(-Double(dias) * 86400).timeIntervalSince1970)
            var out: [(String, Int)] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append((coluna(st, 0), Int(sqlite3_column_int64(st, 1))))
            }
            return out
        }
    }

    // MARK: - Status de câmera (online/offline)

    /// Grava só transições (o registro de saúde chama a cada mudança real).
    func registrarStatus(camera: String, online: Bool) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO status_camera(ts,camera,online) VALUES(?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 3, online ? 1 : 0)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    func historicoStatus(dias: Int = 7, limite: Int = 300) -> [TransicaoStatus] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT id,ts,camera,online FROM status_camera WHERE ts >= ? ORDER BY ts DESC LIMIT \(max(1, limite))",
                -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, Date().addingTimeInterval(-Double(dias) * 86400).timeIntervalSince1970)
            var out: [TransicaoStatus] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(TransicaoStatus(
                    id: sqlite3_column_int64(st, 0),
                    quando: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
                    camera: coluna(st, 2),
                    online: sqlite3_column_int(st, 3) == 1))
            }
            return out
        }
    }

    // MARK: - Placas (LPR)

    func registrarPlaca(_ placa: String, camera: String) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO placas(ts,camera,placa) VALUES(?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 3, placa, -1, SQLITE_TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    func buscarPlacas(texto: String = "", dias: Int = 7, limite: Int = 500) -> [Placa] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            var sql = "SELECT id,ts,camera,placa FROM placas WHERE ts >= ?"
            if !texto.isEmpty { sql += " AND placa LIKE ?" }
            sql += " ORDER BY ts DESC LIMIT \(max(1, limite))"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, Date().addingTimeInterval(-Double(dias) * 86400).timeIntervalSince1970)
            if !texto.isEmpty { sqlite3_bind_text(st, 2, "%\(texto)%", -1, SQLITE_TRANSIENT) }
            var out: [Placa] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Placa(id: sqlite3_column_int64(st, 0),
                                 quando: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
                                 camera: coluna(st, 2), placa: coluna(st, 3)))
            }
            return out
        }
    }

    /// Placas de interesse (lista de alerta). Retorna descrição se a placa consta.
    func interesse(_ placa: String) -> String? {
        fila.sync { [self] in
            guard db != nil else { return nil }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT descricao FROM placas_interesse WHERE placa=?", -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, placa, -1, SQLITE_TRANSIENT)
            return sqlite3_step(st) == SQLITE_ROW ? coluna(st, 0) : nil
        }
    }

    func listarInteresse() -> [(String, String)] {
        fila.sync { [self] in
            guard db != nil else { return [] }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT placa,descricao FROM placas_interesse ORDER BY placa", -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [(String, String)] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append((coluna(st, 0), coluna(st, 1))) }
            return out
        }
    }

    func adicionarInteresse(_ placa: String, descricao: String) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT OR REPLACE INTO placas_interesse(placa,descricao) VALUES(?,?)", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(st, 1, placa, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, descricao, -1, SQLITE_TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    func removerInteresse(_ placa: String) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "DELETE FROM placas_interesse WHERE placa=?", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(st, 1, placa, -1, SQLITE_TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    // MARK: - Métricas de negócio (série temporal)

    func registrarMetrica(camera: String, entradas: Int, saidas: Int, ocupacao: Int,
                          intrusoes: Int, permanencias: Int,
                          pessoasUnicas: Int = 0, veiculosUnicas: Int = 0) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                """
                INSERT INTO metricas(ts,camera,entradas,saidas,ocupacao,intrusoes,permanencias,pessoas_unicas,veiculos_unicas)
                VALUES(?,?,?,?,?,?,?,?,?)
                """, -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 3, Int64(entradas)); sqlite3_bind_int64(st, 4, Int64(saidas))
            sqlite3_bind_int64(st, 5, Int64(ocupacao)); sqlite3_bind_int64(st, 6, Int64(intrusoes))
            sqlite3_bind_int64(st, 7, Int64(permanencias))
            sqlite3_bind_int64(st, 8, Int64(pessoasUnicas)); sqlite3_bind_int64(st, 9, Int64(veiculosUnicas))
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    /// Amostra mais recente de uma câmera com `ts <= limite` — usada para
    /// "quanto valia o contador bem antes/no fim da janela".
    private struct AmostraMetrica {
        var entradas = 0, saidas = 0, ocupacao = 0, intrusoes = 0, permanencias = 0
        var pessoasUnicas = 0, veiculosUnicas = 0
    }

    private func amostraEm(camera: String, ateOuAntes limite: Date) -> AmostraMetrica? {
        guard db != nil else { return nil }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            """
            SELECT entradas,saidas,ocupacao,intrusoes,permanencias,pessoas_unicas,veiculos_unicas
            FROM metricas WHERE camera=? AND ts <= ? ORDER BY ts DESC LIMIT 1
            """, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, camera, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(st, 2, limite.timeIntervalSince1970)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return AmostraMetrica(
            entradas: Int(sqlite3_column_int64(st, 0)), saidas: Int(sqlite3_column_int64(st, 1)),
            ocupacao: Int(sqlite3_column_int64(st, 2)), intrusoes: Int(sqlite3_column_int64(st, 3)),
            permanencias: Int(sqlite3_column_int64(st, 4)), pessoasUnicas: Int(sqlite3_column_int64(st, 5)),
            veiculosUnicas: Int(sqlite3_column_int64(st, 6)))
    }

    private func camerasComDado(ate: Date) -> [String] {
        guard db != nil else { return [] }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT camera FROM metricas WHERE ts <= ?", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, ate.timeIntervalSince1970)
        var out: [String] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(coluna(st, 0)) }
        return out
    }

    /// Soma, no intervalo `[desde, ate]`, o quanto os contadores (entradas,
    /// saídas, intrusões, permanências, únicos) CRESCERAM em cada câmera —
    /// eles são cumulativos desde que a sessão de captura daquela câmera
    /// começou (ver `CameraCardViewModel`), não uma amostra pontual.
    ///
    /// Delta = última amostra ATÉ o fim menos a amostra mais próxima ANTES do
    /// início. Se o contador aparenta ter voltado a zero no meio (a view da
    /// câmera foi fechada/reaberta, ou o app reiniciou), assume-se reset e o
    /// valor final inteiro conta como crescimento dentro da janela — mesma
    /// técnica usada para lidar com reset de contador em séries monotônicas
    /// (ex.: `rate()` do Prometheus). `ocupacao` é um GAUGE, não um contador:
    /// aqui vira a média das amostras da janela, não uma diferença.
    func somarPeriodo(desde: Date, ate: Date) -> BusinessMetricsService.Metrica {
        fila.sync { [self] in
            var m = BusinessMetricsService.Metrica()
            var somaOcupacao = 0, amostrasOcupacao = 0
            for camera in camerasComDado(ate: ate) {
                let fim = amostraEm(camera: camera, ateOuAntes: ate)
                guard let fim else { continue }
                let inicio = amostraEm(camera: camera, ateOuAntes: desde)
                func delta(_ f: (AmostraMetrica) -> Int) -> Int {
                    let vFim = f(fim)
                    guard let inicio else { return vFim }   // nada antes da janela: tudo é ganho da janela
                    let vInicio = f(inicio)
                    return vFim >= vInicio ? vFim - vInicio : vFim   // vFim < vInicio => reset no meio
                }
                m.entradas += delta { $0.entradas }
                m.saidas += delta { $0.saidas }
                m.intrusoes += delta { $0.intrusoes }
                m.permanencias += delta { $0.permanencias }
                m.unicos["person", default: 0] += delta { $0.pessoasUnicas }
                m.unicos["car", default: 0] += delta { $0.veiculosUnicas }
                somaOcupacao += fim.ocupacao; amostrasOcupacao += 1
            }
            m.ocupacao = amostrasOcupacao > 0 ? somaOcupacao / amostrasOcupacao : 0
            return m
        }
    }

    private func coluna(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    // MARK: - Mapa de calor (grade acumulada de posição de detecções)

    /// Grava um "bucket" — a grade acumulada desde a última chamada a
    /// `HeatmapService.drenar(camera:)`, não uma cumulativa desde o início da
    /// sessão. Somar buckets de um período é só somar célula-a-célula.
    func registrarHeatmap(camera: String, colunas: Int, linhas: Int, grade: [Int]) {
        guard let json = try? JSONEncoder().encode(grade), let texto = String(data: json, encoding: .utf8) else { return }
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO heatmap(ts,camera,colunas,linhas,grade) VALUES(?,?,?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 3, Int64(colunas)); sqlite3_bind_int64(st, 4, Int64(linhas))
            sqlite3_bind_text(st, 5, texto, -1, SQLITE_TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    /// Soma célula-a-célula todos os buckets da câmera no período. Buckets
    /// com dimensão diferente da grade atual (`HeatmapService.colunas/linhas`
    /// mudou entre versões) são ignorados — não dá pra somar grades de
    /// tamanhos diferentes célula-a-célula.
    func heatmapAcumulado(camera: String, desde: Date, ate: Date) -> (colunas: Int, linhas: Int, grade: [Int])? {
        fila.sync { [self] in
            guard db != nil else { return nil }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT colunas,linhas,grade FROM heatmap WHERE camera=? AND ts BETWEEN ? AND ?",
                -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 2, desde.timeIntervalSince1970)
            sqlite3_bind_double(st, 3, ate.timeIntervalSince1970)

            let colunasRef = HeatmapService.colunas, linhasRef = HeatmapService.linhas
            var soma = Array(repeating: 0, count: colunasRef * linhasRef)
            var encontrouAlgo = false
            while sqlite3_step(st) == SQLITE_ROW {
                guard Int(sqlite3_column_int64(st, 0)) == colunasRef, Int(sqlite3_column_int64(st, 1)) == linhasRef,
                      let grade = try? JSONDecoder().decode([Int].self, from: Data(coluna(st, 2).utf8)),
                      grade.count == soma.count else { continue }
                for i in 0..<soma.count { soma[i] += grade[i] }
                encontrouAlgo = true
            }
            return encontrouAlgo ? (colunasRef, linhasRef, soma) : nil
        }
    }

    // MARK: - Exportação CSV (para BI/Excel externo)

    enum TabelaExport: String, CaseIterable, Identifiable {
        case eventos, metricas, placas
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .eventos: return "Eventos"
            case .metricas: return "Métricas (série temporal)"
            case .placas: return "Placas (LPR)"
            }
        }
    }

    /// Exporta a tabela pedida, filtrada por `[desde, ate]`, pra um `.csv` em
    /// `StorageService.dirEventos`. Formato simples (vírgula, aspas quando o
    /// campo contém vírgula/aspas/quebra de linha) — o bastante pra abrir
    /// direto no Excel/Numbers ou puxar num BI (Power Query, Metabase etc.).
    func exportarCSV(tabela: TabelaExport, desde: Date, ate: Date) -> URL? {
        fila.sync { [self] in
            guard db != nil else { return nil }
            let linhas: [[String]]
            let cabecalho: [String]
            switch tabela {
            case .eventos:
                cabecalho = ["data_hora", "tipo", "camera", "detalhe", "severidade", "status", "checado_por"]
                linhas = consultarCSV(
                    "SELECT ts,tipo,camera,detalhe,severidade,status,checado_por FROM eventos WHERE ts BETWEEN ? AND ? ORDER BY ts",
                    desde: desde, ate: ate, colunas: 7)
            case .metricas:
                cabecalho = ["data_hora", "camera", "entradas", "saidas", "ocupacao", "intrusoes", "permanencias", "pessoas_unicas", "veiculos_unicas"]
                linhas = consultarCSV(
                    """
                    SELECT ts,camera,entradas,saidas,ocupacao,intrusoes,permanencias,pessoas_unicas,veiculos_unicas
                    FROM metricas WHERE ts BETWEEN ? AND ? ORDER BY ts
                    """, desde: desde, ate: ate, colunas: 9)
            case .placas:
                cabecalho = ["data_hora", "camera", "placa"]
                linhas = consultarCSV(
                    "SELECT ts,camera,placa FROM placas WHERE ts BETWEEN ? AND ? ORDER BY ts",
                    desde: desde, ate: ate, colunas: 3)
            }

            let formatador = ISO8601DateFormatter()
            var csv = cabecalho.map(Self.csvEscapar).joined(separator: ",") + "\n"
            for linha in linhas {
                var campos = linha
                if let ts = Double(campos[0]) {
                    campos[0] = formatador.string(from: Date(timeIntervalSince1970: ts))
                }
                csv += campos.map(Self.csvEscapar).joined(separator: ",") + "\n"
            }

            let nomeArquivo = "export-\(tabela.rawValue)-\(Int(Date().timeIntervalSince1970)).csv"
            let url = StorageService.shared.dirEventos.appendingPathComponent(nomeArquivo)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                print("[EventStore] falha ao gravar CSV: \(error)")
                return nil
            }
        }
    }

    /// Roda `sql` (que espera `ts BETWEEN ? AND ?` como únicos parâmetros) e
    /// devolve cada linha como `[String]`, na ordem das colunas do SELECT.
    private func consultarCSV(_ sql: String, desde: Date, ate: Date, colunas: Int32) -> [[String]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, desde.timeIntervalSince1970)
        sqlite3_bind_double(st, 2, ate.timeIntervalSince1970)
        var out: [[String]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append((0..<colunas).map { coluna(st, $0) })
        }
        return out
    }

    /// Escape CSV correto (RFC 4180). Era privado, e por isso a aba Eventos
    /// tinha a própria versão trocando vírgula por ";" — que corrompia colunas
    /// em qualquer detalhe com aspas ou quebra de linha.
    static func csvEscapar(_ campo: String) -> String {
        guard campo.contains(",") || campo.contains("\"") || campo.contains("\n") else { return campo }
        return "\"" + campo.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
