import SwiftUI
import AVKit

/// Aba Gravações: navega clipes e capturas por câmera/dia, reproduz MP4 dentro
/// do app (antes só "abrir no Finder") e gera time lapse acelerado via ffmpeg.
struct RecordingsBrowserView: View {
    var usuario: String = "sistema"
    var podeOperar = true

    struct Item: Identifiable, Hashable {
        let id: String
        let url: URL
        let camera: String
        let dia: String
        let ehVideo: Bool
        let tamanho: Int
    }

    @State private var itens: [Item] = []
    @State private var cameraFiltro = ""
    @State private var selecionado: Item?
    @State private var player: AVPlayer?
    @State private var gerandoTimelapse = false
    @State private var msgTimelapse = ""
    @State private var fatorTimelapse = 8

    private var cameras: [String] { Array(Set(itens.map(\.camera))).sorted() }
    private var filtrados: [Item] {
        cameraFiltro.isEmpty ? itens : itens.filter { $0.camera == cameraFiltro }
    }

    var body: some View {
        HSplitView {
            lista.frame(minWidth: 320, maxWidth: 420)
            visual.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VigiaTheme.bg)
        .onAppear(perform: recarregar)
    }

    private var lista: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Câmera", selection: $cameraFiltro) {
                    Text("Todas").tag("")
                    ForEach(cameras, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Spacer()
                Button(action: recarregar) { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
            }.padding(10)
            List(filtrados, selection: Binding(get: { selecionado?.id }, set: { id in
                selecionado = filtrados.first { $0.id == id }
                abrir(selecionado)
            })) { item in
                HStack {
                    Image(systemName: item.ehVideo ? "film" : "photo")
                        .foregroundColor(item.ehVideo ? VigiaTheme.accent : VigiaTheme.accent2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                        Text("\(item.camera) • \(item.dia) • \(mb(item.tamanho))")
                            .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                    }
                }
                .tag(item.id)
                .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .background(VigiaTheme.panel)
    }

    @ViewBuilder
    private var visual: some View {
        if let sel = selecionado {
            VStack(spacing: 10) {
                if sel.ehVideo, let player {
                    VideoPlayer(player: player).frame(maxHeight: .infinity)
                } else if let img = NSImage(contentsOf: sel.url) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: .infinity)
                }
                HStack(spacing: 8) {
                    if podeOperar {
                        Button {
                            _ = StorageService.shared.exportarEvidencia(
                                arquivo: sel.url.path, camera: sel.camera, usuario: usuario)
                        } label: { Label("Exportar evidência", systemImage: "shippingbox") }
                            .buttonStyle(.bordered).tint(VigiaTheme.accent)
                    }
                    if sel.ehVideo {
                        Picker("", selection: $fatorTimelapse) {
                            Text("4×").tag(4); Text("8×").tag(8); Text("16×").tag(16); Text("32×").tag(32)
                        }.pickerStyle(.menu).frame(width: 70)
                        Button {
                            gerarTimelapse(sel)
                        } label: {
                            gerandoTimelapse
                                ? Label("Gerando…", systemImage: "hourglass")
                                : Label("Time lapse", systemImage: "forward.fill")
                        }
                        .buttonStyle(.bordered).tint(VigiaTheme.accent2)
                        .disabled(gerandoTimelapse)
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([sel.url])
                    } label: { Label("Finder", systemImage: "folder") }.buttonStyle(.bordered)
                    Spacer()
                    if !msgTimelapse.isEmpty {
                        Text(msgTimelapse).font(.system(size: 11)).foregroundColor(VigiaTheme.ok)
                    }
                }.padding(12)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "film.stack").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                Text("Selecione uma gravação ou captura").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VigiaTheme.muted)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func abrir(_ item: Item?) {
        player?.pause()
        player = nil
        msgTimelapse = ""
        guard let item, item.ehVideo else { return }
        player = AVPlayer(url: item.url)
        player?.play()
    }

    /// Time lapse via ffmpeg (mesma dependência do RTSP): descarta frames e
    /// acelera o PTS — vídeo de horas vira minutos.
    private func gerarTimelapse(_ item: Item) {
        gerandoTimelapse = true
        msgTimelapse = ""
        let fator = fatorTimelapse
        let saida = item.url.deletingPathExtension()
            .appendingPathExtension("x\(fator).mp4")
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            for caminho in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            where FileManager.default.fileExists(atPath: caminho) {
                p.executableURL = URL(fileURLWithPath: caminho); break
            }
            if p.executableURL == nil { p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = ["ffmpeg"] }
            var args = p.arguments ?? []
            args += ["-y", "-i", item.url.path,
                     "-vf", "setpts=PTS/\(fator)", "-an", saida.path]
            p.arguments = args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            do {
                try p.run(); p.waitUntilExit()
                DispatchQueue.main.async {
                    gerandoTimelapse = false
                    if p.terminationStatus == 0 {
                        msgTimelapse = "Time lapse gerado: \(saida.lastPathComponent)"
                        StorageService.shared.auditar("timelapse",
                            detalhe: "origem=\(item.url.lastPathComponent) fator=\(fator)", usuario: usuario)
                        recarregar()
                    } else {
                        msgTimelapse = "Falha no ffmpeg (instalado?)"
                    }
                }
            } catch {
                DispatchQueue.main.async { gerandoTimelapse = false; msgTimelapse = "ffmpeg não encontrado" }
            }
        }
    }

    private func recarregar() {
        let fm = FileManager.default
        var out: [Item] = []
        // gravacoes/<camera>/<dia>/<hora>.mp4
        let gravacoes = StorageService.shared.dirGravacoes
        if let e = fm.enumerator(at: gravacoes, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in e where url.pathExtension.lowercased() == "mp4" {
                let comps = url.pathComponents
                let n = comps.count
                out.append(Item(id: url.path, url: url,
                                camera: n >= 3 ? comps[n - 3] : "?",
                                dia: n >= 2 ? comps[n - 2] : "?",
                                ehVideo: true,
                                tamanho: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
        }
        // capturas/<dia>/<camera>-<hora>.png
        let capturas = StorageService.shared.dirCapturas
        if let e = fm.enumerator(at: capturas, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in e where url.pathExtension.lowercased() == "png" {
                let comps = url.pathComponents
                let n = comps.count
                let nome = url.deletingPathExtension().lastPathComponent
                let camera = nome.split(separator: "-").dropLast().joined(separator: "-")
                out.append(Item(id: url.path, url: url,
                                camera: camera.isEmpty ? "?" : camera,
                                dia: n >= 2 ? comps[n - 2] : "?",
                                ehVideo: false,
                                tamanho: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
        }
        itens = out.sorted { $0.url.path > $1.url.path }
    }

    private func mb(_ bytes: Int) -> String {
        bytes > 1_048_576 ? String(format: "%.1f MB", Double(bytes) / 1_048_576)
                          : String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
