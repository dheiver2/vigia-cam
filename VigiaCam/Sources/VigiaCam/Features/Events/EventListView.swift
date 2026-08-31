import SwiftUI
import AppKit

/// Busca de eventos sobre o SQLite: texto + câmera + tipo + só abertos,
/// com tratativa (checado por) e link para a evidência.
struct EventListView: View {
    @ObservedObject var eventService: EventService
    var usuario: String = "sistema"
    /// Tratar evento é ação de operador — antes esta tela não recebia papel
    /// nenhum e um visualizador podia dar baixa em alarme.
    var podeOperar: Bool = true

    @State private var registros: [EventStore.Registro] = []
    @State private var searchText = ""
    @State private var dias = 7
    @State private var cameraFiltro = ""
    @State private var tipoFiltro = ""
    @State private var somenteAbertos = false
    /// Câmeras vindas do banco (não dos resultados já filtrados).
    @State private var cameras: [String] = []
    /// Resultado bateu no teto de `buscar` — o rodapé precisa dizer isso em vez
    /// de exibir "1000 eventos" como se fosse o total.
    @State private var truncado = false
    @State private var aviso: String?
    @State private var buscaPendente: Task<Void, Never>?

    private static let limiteBusca = 1000

    var body: some View {
        VStack(spacing: 0) {
            filtros
            if let aviso {
                HStack(spacing: 6) {
                    Image(systemName: aviso.hasPrefix("Falha") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(aviso).font(.system(size: 11))
                    Spacer()
                    Button("OK") { self.aviso = nil }.buttonStyle(.plain).font(.system(size: 11))
                }
                .foregroundColor(aviso.hasPrefix("Falha") ? VigiaTheme.danger : VigiaTheme.ok)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(VigiaTheme.card)
            }
            if registros.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                    Text("Nenhum evento encontrado").font(.system(size: 14, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(registros) { linha($0) }
                    .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(VigiaTheme.bg)
        .onAppear(perform: recarregar)
    }

    private var filtros: some View {
        VStack(spacing: 8) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(VigiaTheme.muted)
                    TextField("Buscar eventos...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit(recarregar)
                }.padding(8).background(VigiaTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(VigiaTheme.border, lineWidth: 1))
                Picker("Dias", selection: $dias) {
                    Text("1 dia").tag(1); Text("7 dias").tag(7); Text("30 dias").tag(30); Text("90 dias").tag(90)
                }.pickerStyle(.menu).frame(width: 92)
                Button(action: recarregar) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }.buttonStyle(.bordered)
                Button(action: exportarCSV) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                }.buttonStyle(.bordered).tint(VigiaTheme.accent)
            }
            HStack {
                Picker("Câmera", selection: $cameraFiltro) {
                    Text("Todas as câmeras").tag("")
                    ForEach(cameras, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Picker("Tipo", selection: $tipoFiltro) {
                    Text("Todos os tipos").tag("")
                    Text("Alarmes").tag("ALARME")
                    Text("Detecções").tag("deteccao")
                    Text("Placas").tag("PLACA")
                    Text("Câmera on/off").tag("STATUS")
                }.pickerStyle(.menu)
                Toggle("Só abertos", isOn: $somenteAbertos).toggleStyle(.checkbox)
                    .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                Spacer()
                Text(truncado ? "\(registros.count)+ eventos (limite da busca)"
                              : "\(registros.count) eventos")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(truncado ? VigiaTheme.warning : VigiaTheme.muted)
                    .help(truncado ? "Refine o filtro: a consulta devolve no máximo \(Self.limiteBusca) eventos."
                                   : "")
            }
        }
        .padding(12)
        .onChange(of: dias) { recarregar() }
        .onChange(of: cameraFiltro) { recarregar() }
        .onChange(of: tipoFiltro) { recarregar() }
        .onChange(of: somenteAbertos) { recarregar() }
        .onChange(of: searchText) { recarregarComAtraso() }
    }

    private func linha(_ r: EventStore.Registro) -> some View {
        HStack(spacing: 10) {
            Circle().fill(cor(r)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.tipo).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text(r.camera).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                if !r.detalhe.isEmpty {
                    Text(r.detalhe).font(.system(size: 10)).foregroundColor(VigiaTheme.muted).lineLimit(2)
                }
            }
            Spacer()
            if r.status == "tratado" {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Tratado", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(VigiaTheme.ok)
                    if !r.checadoPor.isEmpty {
                        Text("por \(r.checadoPor)").font(.system(size: 9)).foregroundColor(VigiaTheme.muted)
                    }
                }
            } else if podeOperar {
                // Antes só ALARME era tratável, mas o filtro "Só abertos"
                // incluía os demais tipos — eles ficavam abertos para sempre,
                // sem nenhuma ação possível.
                Button("Tratar") {
                    EventStore.shared.tratar(id: r.id, usuario: usuario)
                    recarregar()
                }.buttonStyle(.bordered).controlSize(.small).tint(VigiaTheme.accent)
            }
            if !r.snapshot.isEmpty && FileManager.default.fileExists(atPath: r.snapshot) {
                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: r.snapshot)) }) {
                    Image(systemName: "photo").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundColor(VigiaTheme.accent2)
                    .help("Abrir evidência")
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(hora(r.quando)).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                Text(data(r.quando)).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
            }
        }
        .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
    }

    private func cor(_ r: EventStore.Registro) -> Color {
        if r.tipo.contains("critico") { return VigiaTheme.danger }
        if r.tipo.hasPrefix("ALARME") { return VigiaTheme.warning }
        if r.tipo.hasPrefix("STATUS") { return r.detalhe.contains("online") ? VigiaTheme.ok : VigiaTheme.danger }
        return VigiaTheme.accent2
    }

    private func recarregar() {
        let achados = EventStore.shared.buscar(texto: searchText, camera: cameraFiltro,
                                               tipo: tipoFiltro, somenteAbertos: somenteAbertos,
                                               dias: dias, limite: Self.limiteBusca)
        registros = achados
        truncado = achados.count >= Self.limiteBusca
        cameras = EventStore.shared.camerasDistintas(dias: dias)
    }

    /// Busca com atraso: `recarregar()` faz consulta SQLite síncrona, e
    /// dispará-la a cada tecla travava a digitação em bancos grandes.
    private func recarregarComAtraso() {
        buscaPendente?.cancel()
        buscaPendente = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            recarregar()
        }
    }

    private func exportarCSV() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let cabecalho = ["quando", "tipo", "camera", "detalhe", "status", "checado_por"]
        var csv = cabecalho.joined(separator: ",") + "\n"
        for r in registros {
            // Escape RFC 4180 de verdade (o antigo trocava "," por ";" só no
            // detalhe, e qualquer aspas/quebra de linha desalinhava as colunas).
            let campos = [f.string(from: r.quando), r.tipo, r.camera, r.detalhe, r.status, r.checadoPor]
            csv += campos.map(EventStore.csvEscapar).joined(separator: ",") + "\n"
        }
        // Nome com timestamp: o fixo "busca-eventos.csv" sobrescrevia a
        // exportação anterior sem avisar.
        let carimbo = DateFormatter(); carimbo.dateFormat = "yyyyMMdd-HHmmss"
        let nome = "busca-eventos-\(carimbo.string(from: Date())).csv"
        let url = StorageService.shared.dirEventos.appendingPathComponent(nome)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            // Só revela no Finder DEPOIS de escrever: antes o Finder abria
            // mesmo com a escrita falhando, e o usuário jurava ter exportado.
            NSWorkspace.shared.activateFileViewerSelecting([url])
            aviso = "Exportado: \(nome)"
        } catch {
            aviso = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    private func hora(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d) }
    private func data(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: d) }
}
