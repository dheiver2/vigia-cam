import SwiftUI

struct CameraDetailView: View {
    let camera: Camera
    @StateObject private var vm: CameraCardViewModel
    @ObservedObject private var rec = RecordingService.shared
    @ObservedObject private var privacy = PrivacyService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editandoPrivacidade = false
    @State private var arrasto: CGRect?
    // PTZ digital
    @State private var ptzZoom: CGFloat = 1
    @State private var ptzBase: CGFloat = 1
    @State private var ptzPan: CGSize = .zero
    @State private var ptzPanBase: CGSize = .zero

    init(camera: Camera) {
        self.camera = camera
        _vm = StateObject(wrappedValue: CameraCardViewModel(camera: camera))
    }

    private var gravando: Bool { rec.estaGravando(camera.nome) }

    var body: some View {
        ZStack {
            VigiaTheme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundColor(VigiaTheme.accent)
                    }
                    Spacer()
                    Text(camera.nome).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 8) {
                        if gravando { RecBadge() }
                        if vm.isOnline { LiveBadge() } else { OfflineBadge() }
                        FPSCaption(fps: vm.fps)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12).background(VigiaTheme.headerGradient)

                ZStack {
                    if let img = vm.frameImage {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                DetectionOverlay(objetos: vm.tracked,
                                                 imageSize: img.size,
                                                 contentMode: .fit),
                                alignment: .center
                            )
                            .overlay(
                                PrivacyMaskOverlay(cameraURL: camera.url,
                                                   imageSize: img.size, contentMode: .fit))
                            .overlay(editorPrivacidade(imageSize: img.size))
                            // PTZ digital: zoom (scroll/±) + pan (arraste) quando ampliado
                            .scaleEffect(ptzZoom)
                            .offset(ptzPan)
                            // desabilita PTZ enquanto edita zona de privacidade
                            .gesture(ptzGesture, including: editandoPrivacidade ? .subviews : .all)
                            .clipped()
                            .overlay(alignment: .bottomLeading) { if ptzZoom > 1.01 { ptzControles } }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(VigiaTheme.accent)
                            Text("Carregando stream...").font(.system(size: 14)).foregroundColor(VigiaTheme.muted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.background(Color.black)

                // Barra de ações (evidência + privacidade LGPD)
                HStack(spacing: 8) {
                    acao("camera.fill", "Snapshot", VigiaTheme.accent2) { vm.capturarSnapshot() }
                    acao(gravando ? "stop.fill" : "record.circle",
                         gravando ? "Parar" : "Gravar",
                         gravando ? VigiaTheme.danger : VigiaTheme.text) { vm.alternarGravacao() }
                    Divider().frame(height: 20)
                    acao(editandoPrivacidade ? "checkmark.circle.fill" : "eye.slash",
                         editandoPrivacidade ? "Concluir zona" : "Zona LGPD",
                         editandoPrivacidade ? VigiaTheme.ok : VigiaTheme.text) {
                        editandoPrivacidade.toggle()
                    }
                    if !privacy.zonasDe(camera.url).isEmpty {
                        acao("arrow.uturn.backward", "Desfazer", VigiaTheme.muted) { privacy.removerUltima(camera.url) }
                        acao("trash", "Limpar zonas", VigiaTheme.danger) { privacy.limpar(camera.url) }
                    }
                    Spacer()
                    if editandoPrivacidade {
                        Text("Arraste sobre o vídeo para tampar uma área")
                            .font(.system(size: 11)).foregroundColor(VigiaTheme.warning)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8).background(VigiaTheme.panel)

                if !vm.detectionCount.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(vm.detectionCount.sorted(by: { $0.key < $1.key })), id: \.key) { label, count in
                                HStack(spacing: 4) {
                                    Circle().fill(DetectorService.color(for: label)).frame(width: 8, height: 8)
                                    Text("\(label)")
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                    Text("×\(count)")
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(VigiaTheme.accent)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }

                // Analítico: contagem de objetos ÚNICOS (footfall / veicular) rastreados
                if !vm.unicos.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.wave.2").foregroundColor(VigiaTheme.accent2)
                        Text("Únicos rastreados:").font(.system(size: 11, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                        ForEach(Array(vm.unicos.sorted(by: { $0.key < $1.key })), id: \.key) { label, n in
                            Text("\(label): \(n)").font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(DetectorService.color(for: label).opacity(0.25))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }.padding(.horizontal, 12).padding(.vertical, 6).background(VigiaTheme.card)
                }

                HStack {
                    Label(camera.tipo.label, systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label(camera.categoria, systemImage: "folder").font(.system(size: 12, weight: .medium))
                    Spacer()
                    // saúde do stream
                    Label("\(vm.reconexoes) reconexão\(vm.reconexoes == 1 ? "" : "ões")",
                          systemImage: vm.reconexoes == 0 ? "checkmark.seal" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(vm.reconexoes == 0 ? VigiaTheme.ok : VigiaTheme.warning)
                    let total = vm.detectionCount.values.reduce(0, +)
                    if total > 0 {
                        Spacer()
                        Label("\(total) no quadro", systemImage: "viewfinder.rectangular")
                            .font(.system(size: 12, weight: .medium))
                    }
                }.foregroundColor(VigiaTheme.muted).padding(12).background(VigiaTheme.panel)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // PTZ digital: pinça p/ zoom + arraste p/ pan (combinados).
    private var ptzGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in ptzZoom = min(max(1, ptzBase * v), 6) }
                .onEnded { _ in ptzBase = ptzZoom; if ptzZoom <= 1.01 { ptzPan = .zero; ptzPanBase = .zero } },
            DragGesture()
                .onChanged { v in
                    guard ptzZoom > 1.01 else { return }
                    ptzPan = CGSize(width: ptzPanBase.width + v.translation.width,
                                    height: ptzPanBase.height + v.translation.height)
                }
                .onEnded { _ in ptzPanBase = ptzPan }
        )
    }

    private var ptzControles: some View {
        HStack(spacing: 6) {
            Button { ajustarZoom(-0.5) } label: { Image(systemName: "minus.magnifyingglass") }
            Text(String(format: "%.1f×", ptzZoom)).font(.system(size: 11, weight: .bold, design: .monospaced))
            Button { ajustarZoom(0.5) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { ptzZoom = 1; ptzBase = 1; ptzPan = .zero; ptzPanBase = .zero } label: { Image(systemName: "arrow.counterclockwise") }
        }
        .buttonStyle(.plain).foregroundColor(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.6)).clipShape(Capsule())
        .padding(12)
    }
    private func ajustarZoom(_ d: CGFloat) {
        ptzZoom = min(max(1, ptzZoom + d), 6); ptzBase = ptzZoom
        if ptzZoom <= 1.01 { ptzPan = .zero; ptzPanBase = .zero }
    }

    private func acao(_ icon: String, _ titulo: String, _ cor: Color, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            HStack(spacing: 5) {
                Image(systemName: icon); Text(titulo)
            }.font(.system(size: 12, weight: .semibold)).foregroundColor(cor)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    /// Camada de desenho de zona de privacidade (arrasto normaliza p/ 0–1).
    @ViewBuilder
    private func editorPrivacidade(imageSize: CGSize) -> some View {
        if editandoPrivacidade {
            GeometryReader { geo in
                let rect = fittedRect(container: geo.size, image: imageSize, mode: .fit)
                ZStack {
                    Color.white.opacity(0.001)   // captura o gesto
                    if let a = arrasto {
                        Rectangle().stroke(VigiaTheme.warning, lineWidth: 2)
                            .background(Color.warningFill)
                            .frame(width: a.width, height: a.height)
                            .position(x: a.midX, y: a.midY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in
                            arrasto = CGRect(x: min(v.startLocation.x, v.location.x),
                                             y: min(v.startLocation.y, v.location.y),
                                             width: abs(v.location.x - v.startLocation.x),
                                             height: abs(v.location.y - v.startLocation.y))
                        }
                        .onEnded { _ in
                            if let a = arrasto, a.width > 6, a.height > 6, rect.width > 0 {
                                let norm = CGRect(x: (a.minX - rect.minX) / rect.width,
                                                  y: (a.minY - rect.minY) / rect.height,
                                                  width: a.width / rect.width,
                                                  height: a.height / rect.height)
                                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                                if norm.width > 0.01, norm.height > 0.01 {
                                    privacy.adicionar(camera.url, rect: norm)
                                }
                            }
                            arrasto = nil
                        }
                )
            }
        }
    }
}

extension Color {
    static let warningFill = VigiaTheme.warning.opacity(0.2)
}
