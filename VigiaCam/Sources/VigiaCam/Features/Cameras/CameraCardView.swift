import SwiftUI

struct CameraCardView: View {
    let camera: Camera
    /// nil = altura fixa (lista); >0 preenche a célula (videowall).
    var videoHeight: CGFloat? = 140
    var compacto: Bool = false
    var osd: Bool = false                 // legenda sobreposta (nome + hora)
    @StateObject private var vm: CameraCardViewModel
    @ObservedObject private var rec = RecordingService.shared
    @State private var isHovered = false
    @State private var showingDetail = false
    @State private var flashSnapshot = false

    init(camera: Camera, videoHeight: CGFloat? = 140, compacto: Bool = false, osd: Bool = false) {
        self.camera = camera
        self.videoHeight = videoHeight
        self.compacto = compacto
        self.osd = osd
        _vm = StateObject(wrappedValue: CameraCardViewModel(camera: camera))
    }

    private var gravando: Bool { rec.estaGravando(camera.nome) }
    static let horaFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"; return f }()

    var body: some View {
        // VStack + onTapGesture (não Button) para os botões internos (snapshot/
        // gravar) capturarem o próprio clique sem também abrir o detalhe.
        VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = vm.frameImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: videoHeight, alignment: .center)
                                .frame(maxHeight: videoHeight == nil ? .infinity : nil)
                                .clipped()
                                .overlay(
                                    DetectionOverlay(objetos: vm.tracked,
                                                     imageSize: img.size,
                                                     contentMode: .fill,
                                                     mostrarID: !compacto)
                                )
                                .overlay(
                                    PrivacyMaskOverlay(cameraURL: camera.url,
                                                       imageSize: img.size,
                                                       contentMode: .fill)
                                )
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color(VigiaTheme.bg))
                                .frame(height: videoHeight)
                                .frame(maxWidth: .infinity, maxHeight: videoHeight == nil ? .infinity : nil)
                                .overlay(
                                    VStack(spacing: 8) {
                                        ProgressView().tint(VigiaTheme.accent)
                                        Text(vm.isOnline ? "Conectando..." : "Reconectando...")
                                            .font(.system(size: 11))
                                            .foregroundColor(VigiaTheme.muted)
                                    }
                                )
                        }
                    }
                    .overlay(flashSnapshot ? Color.white.opacity(0.7) : Color.clear)
                    // barra inferior de controles (aparece no hover)
                    .overlay(alignment: .bottomTrailing) {
                        if isHovered && vm.frameImage != nil {
                            HStack(spacing: 6) {
                                controle(icon: "camera.fill", cor: VigiaTheme.accent2) { fazerSnapshot() }
                                controle(icon: gravando ? "stop.fill" : "record.circle",
                                         cor: gravando ? VigiaTheme.danger : .white) { vm.alternarGravacao() }
                            }.padding(8)
                        }
                    }

                    HStack(spacing: 6) {
                        if vm.isOnline { LiveBadge() } else { OfflineBadge() }
                        if gravando { RecBadge() }
                        Spacer()
                        if osd {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(Self.horaFmt.string(from: ctx.date))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white).shadow(color: .black, radius: 2)
                            }
                        }
                        FPSCaption(fps: vm.fps)
                    }.padding(8)

                    // No videowall (compacto) o nome fica sobreposto embaixo.
                    if compacto {
                        VStack { Spacer()
                            HStack {
                                Text(camera.nome).font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white).lineLimit(1)
                                    .shadow(color: .black, radius: 2)
                                Spacer()
                                if !vm.detectionCount.isEmpty {
                                    Text(vm.detectionCount.map { "\($0.key) \($0.value)" }
                                        .sorted().joined(separator: "  "))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(VigiaTheme.accent2)
                                        .shadow(color: .black, radius: 2)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                                       startPoint: .top, endPoint: .bottom))
                        }
                    }
                }
                if !compacto {
                    if !vm.detectionCount.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(vm.detectionCount.prefix(5).sorted(by: { $0.key < $1.key })), id: \.key) { label, count in
                                HStack(spacing: 3) {
                                    Circle().fill(DetectorService.color(for: label)).frame(width: 6, height: 6)
                                    Text("\(label) ×\(count)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }.padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(camera.nome).font(.system(size: 12, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text(camera.tipo.label)
                                .font(.system(size: 9, weight: .bold)).foregroundColor(VigiaTheme.accent2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(VigiaTheme.accent2Glow).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(camera.categoria).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                    }.padding(10)
                }
            }
            .background(VigiaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: compacto ? 6 : 12))
            .overlay(RoundedRectangle(cornerRadius: compacto ? 6 : 12).stroke(isHovered ? VigiaTheme.accent : VigiaTheme.border, lineWidth: isHovered ? 1.5 : 1))
            .shadow(color: isHovered ? VigiaTheme.accentGlow : .clear, radius: 8)
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering } }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showingDetail) {
            CameraDetailView(camera: camera)
        }
    }

    private func controle(icon: String, cor: Color, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .foregroundColor(cor).frame(width: 26, height: 26)
                .background(Color.black.opacity(0.55)).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func fazerSnapshot() {
        guard vm.capturarSnapshot() != nil else { return }
        withAnimation(.easeOut(duration: 0.05)) { flashSnapshot = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.2)) { flashSnapshot = false }
        }
    }
}

/// Máscara de privacidade (LGPD): tampa retângulos sensíveis sobre o vídeo.
struct PrivacyMaskOverlay: View {
    let cameraURL: String
    var imageSize: CGSize = .zero
    var contentMode: ContentMode = .fill
    @ObservedObject private var privacy = PrivacyService.shared

    var body: some View {
        GeometryReader { geo in
            let zonas = privacy.zonasDe(cameraURL)
            let rect = fittedRect(container: geo.size, image: imageSize, mode: contentMode)
            ForEach(zonas) { z in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(Color.black.opacity(0.55)))
                    .overlay(
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.8)))
                    .frame(width: z.w * rect.width, height: z.h * rect.height)
                    .position(x: rect.minX + (z.x + z.w / 2) * rect.width,
                              y: rect.minY + (z.y + z.h / 2) * rect.height)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Retângulo ocupado pela imagem no container (compartilhado por overlays).
func fittedRect(container: CGSize, image: CGSize, mode: ContentMode) -> CGRect {
    guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = mode == .fill
        ? max(container.width / image.width, container.height / image.height)
        : min(container.width / image.width, container.height / image.height)
    let size = CGSize(width: image.width * scale, height: image.height * scale)
    return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                  width: size.width, height: size.height)
}

struct DetectionOverlay: View {
    /// Objetos rastreados (box já predito/suavizado, com ID persistente).
    let objetos: [TrackedObject]
    var imageSize: CGSize = .zero
    /// Deve espelhar o `contentMode` da Image (.fill corta, .fit deixa barras).
    var contentMode: ContentMode = .fill
    var mostrarID = true

    var body: some View {
        GeometryReader { geo in
            let rect = imageRect(in: geo.size)
            ForEach(objetos) { obj in
                let box = obj.box
                // Vision usa origem inferior-esquerda; convertemos para topo.
                let x = rect.minX + box.origin.x * rect.width
                let y = rect.minY + (1.0 - box.origin.y - box.size.height) * rect.height
                let w = box.size.width * rect.width
                let h = box.size.height * rect.height
                let color = DetectorService.color(for: obj.label)
                let etiqueta = mostrarID
                    ? "\(obj.label) #\(obj.id) · \(Int(obj.confidence * 100))%"
                    : "\(obj.label) \(Int(obj.confidence * 100))%"

                RoundedRectangle(cornerRadius: 2)
                    .stroke(color, lineWidth: 2)
                    .frame(width: max(w, 8), height: max(h, 8))
                    .position(x: x + w / 2, y: y + h / 2)
                    .overlay(
                        Text(etiqueta)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(color)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .fixedSize()
                            .position(x: x + w / 2, y: max(y - 6, rect.minY + 6)),
                        alignment: .top
                    )
                    // interpola entre as atualizações do tracker -> movimento fluido
                    .animation(.linear(duration: 1.0 / 15.0), value: box)
            }
        }
        .clipped()
    }

    /// Retângulo (em pontos do container) realmente ocupado pela imagem, dado
    /// o aspecto da fonte e o modo de exibição. Sem isso as caixas ficam
    /// deslocadas no eixo cortado (.fill) ou nas barras (.fit).
    private func imageRect(in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = contentMode == .fill
            ? max(container.width / imageSize.width, container.height / imageSize.height)
            : min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
