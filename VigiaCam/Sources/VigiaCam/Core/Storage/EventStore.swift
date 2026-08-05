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
                          intrusoes: Int, permanencias: Int) {
        fila.async { [self] in
            guard db != nil else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO metricas(ts,camera,entradas,saidas,ocupacao,intrusoes,permanencias) VALUES(?,?,?,?,?,?,?)",
                -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(st, 2, camera, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 3, Int64(entradas)); sqlite3_bind_int64(st, 4, Int64(saidas))
            sqlite3_bind_int64(st, 5, Int64(ocupacao)); sqlite3_bind_int64(st, 6, Int64(intrusoes))
            sqlite3_bind_int64(st, 7, Int64(permanencias))
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    private func coluna(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }
}
