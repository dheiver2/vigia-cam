import SwiftUI
import AppKit

/// Videowall estilo VMS: mosaicos selecionáveis, paginação, ronda automática
/// (rodízio de páginas) e tela cheia.
struct LiveWallView: View {
    @ObservedObject var storage: StorageService
    @State private var cameras: [Camera] = []
    @State private var categoria = "Todas"
    @State private var layout = 4                 // tiles por página (1,4,9,16)
    @State private var pagina = 0
    @State private var ronda = false
    @State private var rondaSeg = 10
    @State private var buscando = ""
    @State private var osd = true                 // legenda sempre visível (nome+hora)
    @State private var salvos: [VistaSalva] = []

    struct VistaSalva: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var nome: String; var categoria: String; var layout: Int
    }

    private let layouts = [(1, "1×1"), (4, "2×2"), (9, "3×3"), (16, "4×4")]
    private let rondaTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var tickRonda = 0

    private var categorias: [String] { ["Todas"] + Set(cameras.map { $0.categoria }).sorted() }
    private var filtradas: [Camera] {
        cameras.filter { c in
            (categoria == "Todas" || c.categoria == categoria) &&
            (buscando.isEmpty || c.nome.localizedCaseInsensitiveContains(buscando))
        }
    }
    private var totalPaginas: Int { max(1, Int(ceil(Double(filtradas.count) / Double(layout)))) }
    private var paginaCameras: [Camera] {
        let ini = pagina * layout
        guard ini < filtradas.count else { return [] }
        return Array(filtradas[ini..<min(ini + layout, filtradas.count)])
    }

    var body: some View {
        VStack(spacing: 0) {
            barra
            AlarmBanner()
            GeometryReader { geo in
                grade(in: geo.size)
            }
            .background(Color.black)
        }
        .background(VigiaTheme.bg)
        .background(atalhosTeclado)
        .onAppear { cameras = storage.carregarCameras(); salvos = carregarSalvos() }
        .onReceive(rondaTimer) { _ in avancarRonda() }
    }

    /// Atalhos de teclado (VMS): 1–4 mosaicos, ←→ páginas, F tela cheia, O OSD.
    private var atalhosTeclado: some View {
        ZStack {
            Button("") { trocarLayout(1) }.keyboardShortcut("1", modifiers: [])
            Button("") { trocarLayout(4) }.keyboardShortcut("2", modifiers: [])
            Button("") { trocarLayout(9) }.keyboardShortcut("3", modifiers: [])
            Button("") { trocarLayout(16) }.keyboardShortcut("4", modifiers: [])
            Button("") { irPara(pagina - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { irPara(pagina + 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [])
            Button("") { osd.toggle() }.keyboardShortcut("o", modifiers: [])
            Button("") { ronda.toggle() }.keyboardShortcut(.space, modifiers: [])
        }.opacity(0).allowsHitTesting(false)
    }

    private func carregarSalvos() -> [VistaSalva] {
        guard let d = storage.carregarRaw("vistas_salvas.json"),
              let v = try? JSONDecoder().decode([VistaSalva].self, from: d) else { return [] }
        return v
    }
    private func salvarVista() {
        let v = VistaSalva(nome: (categoria == "Todas" ? "Geral" : categoria) + " \(layoutNome())",
                           categoria: categoria, layout: layout)
        salvos.append(v)
        if let d = try? JSONEncoder().encode(salvos) { storage.salvarRaw(d, para: "vistas_salvas.json") }
    }
    private func aplicarVista(_ v: VistaSalva) {
        categoria = v.categoria; layout = v.layout; pagina = 0
    }
    private func removerVista(_ v: VistaSalva) {
        salvos.removeAll { $0.id == v.id }
        if let d = try? JSONEncoder().encode(salvos) { storage.salvarRaw(d, para: "vistas_salvas.json") }
    }
    private func layoutNome() -> String { layouts.first { $0.0 == layout }?.1 ?? "2×2" }

    // MARK: - Barra de controles

    private var barra: some View {
        HStack(spacing: 10) {
            // seletor de mosaico
            HStack(spacing: 2) {
                ForEach(layouts, id: \.0) { tiles, nome in
                    Button(nome) { trocarLayout(tiles) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(layout == tiles ? .black : VigiaTheme.muted)
                        .frame(width: 34, height: 24)
                        .background(layout == tiles ? AnyView(VigiaTheme.accentGradient) : AnyView(VigiaTheme.card))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            Divider().frame(height: 20)

            // categoria
            Picker("", selection: $categoria) {
                ForEach(categorias, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 180)
            .onChange(of: categoria) { _ in pagina = 0 }

            TextField("Buscar…", text: $buscando)
                .textFieldStyle(.plain).frame(width: 120)
                .padding(6).background(VigiaTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(VigiaTheme.border))
                .onChange(of: buscando) { _ in pagina = 0 }

            Spacer()

            // paginação
            Button { irPara(pagina - 1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundColor(VigiaTheme.text).disabled(pagina == 0)
            Text("Página \(pagina + 1)/\(totalPaginas)")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                .frame(width: 96)
            Button { irPara(pagina + 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundColor(VigiaTheme.text).disabled(pagina >= totalPaginas - 1)

            Divider().frame(height: 20)

            // ronda
            Button {
                ronda.toggle(); tickRonda = 0
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: ronda ? "pause.circle.fill" : "play.circle")
                    Text(ronda ? "Ronda \(rondaSeg)s" : "Ronda")
                }.font(.system(size: 11, weight: .bold))
                .foregroundColor(ronda ? .black : VigiaTheme.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ronda ? AnyView(VigiaTheme.accentGradient) : AnyView(VigiaTheme.card))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
            Stepper("", value: $rondaSeg, in: 3...60, step: 1).labelsHidden().frame(width: 20)

            // OSD (legenda sempre visível)
            Button { osd.toggle() } label: {
                Image(systemName: osd ? "textformat.size" : "textformat.size.smaller")
            }.buttonStyle(.plain).foregroundColor(osd ? VigiaTheme.accent : VigiaTheme.muted)
                .help("Legenda sobreposta (OSD) — tecla O")

            // vistas salvas
            Menu {
                Button("Salvar vista atual", action: salvarVista)
                if !salvos.isEmpty { Divider() }
                ForEach(salvos) { v in
                    Button("\(v.nome)") { aplicarVista(v) }
                }
                if !salvos.isEmpty {
                    Divider()
                    ForEach(salvos) { v in
                        Button("Remover: \(v.nome)", role: .destructive) { removerVista(v) }
                    }
                }
            } label: {
                Image(systemName: "square.grid.2x2")
            }.menuStyle(.borderlessButton).frame(width: 28).help("Vistas salvas")

            // tela cheia
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }.buttonStyle(.plain).foregroundColor(VigiaTheme.text)
                .help("Tela cheia — tecla F")

            Text("\(filtradas.count) câmeras").font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(VigiaTheme.panel)
    }

    // MARK: - Grade de vídeo

    private func grade(in size: CGSize) -> some View {
        let cols = max(1, Int(Double(layout).squareRoot().rounded()))
        let rows = Int(ceil(Double(layout) / Double(cols)))
        let espaco: CGFloat = 3
        let cellW = (size.width - espaco * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (size.height - espaco * CGFloat(rows + 1)) / CGFloat(rows)
        let cams = paginaCameras
        return VStack(spacing: espaco) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: espaco) {
                    ForEach(0..<cols, id: \.self) { c in
                        let idx = r * cols + c
                        if idx < cams.count {
                            CameraCardView(camera: cams[idx], videoHeight: nil, compacto: true, osd: osd)
                                .frame(width: cellW, height: cellH)
                                .id("\(cams[idx].url)#\(pagina)#\(layout)")
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(VigiaTheme.card.opacity(0.4))
                                .frame(width: cellW, height: cellH)
                                .overlay(Image(systemName: "video.slash")
                                    .foregroundColor(VigiaTheme.border))
                        }
                    }
                }
            }
        }
        .padding(espaco)
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Ações

    private func trocarLayout(_ tiles: Int) {
        layout = tiles; pagina = 0
    }
    private func irPara(_ p: Int) {
        pagina = max(0, min(p, totalPaginas - 1)); tickRonda = 0
    }
    private func avancarRonda() {
        guard ronda, totalPaginas > 1 else { return }
        tickRonda += 1
        if tickRonda >= rondaSeg {
            tickRonda = 0
            pagina = (pagina + 1) % totalPaginas
        }
    }
}

/// Banner de alarme ao vivo (aparece no topo do videowall quando dispara).
struct AlarmBanner: View {
    @ObservedObject private var alarms = AlarmService.shared
    var body: some View {
        if let a = alarms.banner {
            HStack(spacing: 10) {
                Image(systemName: a.severidade == .critico ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(a.mensagem).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text(a.severidade.label.uppercased())
                    .font(.system(size: 10, weight: .black)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.black.opacity(0.25)).clipShape(Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(a.severidade == .info ? VigiaTheme.accent2 : VigiaTheme.danger)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
