import SwiftUI

struct CameraDetailView: View {
    let camera: Camera
    @StateObject private var vm: CameraCardViewModel
    @Environment(\.dismiss) private var dismiss

    init(camera: Camera) {
        self.camera = camera
        _vm = StateObject(wrappedValue: CameraCardViewModel(camera: camera))
    }

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
                    HStack(spacing: 8) { LiveBadge(); FPSCaption(fps: vm.fps) }
                }.padding(.horizontal, 16).padding(.vertical, 12).background(VigiaTheme.headerGradient)

                ZStack {
                    if let img = vm.frameImage {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                DetectionOverlay(detections: vm.lastDetections),
                                alignment: .center
                            )
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(VigiaTheme.accent)
                            Text("Carregando stream...").font(.system(size: 14)).foregroundColor(VigiaTheme.muted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.background(Color.black)

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

                HStack {
                    Label(camera.tipo.label, systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label(camera.categoria, systemImage: "folder").font(.system(size: 12, weight: .medium))
                    let total = vm.detectionCount.values.reduce(0, +)
                    if total > 0 {
                        Spacer()
                        Label("\(total) detectado\(total == 1 ? "" : "s")", systemImage: "viewfinder.rectangular")
                            .font(.system(size: 12, weight: .medium))
                    }
                }.foregroundColor(VigiaTheme.muted).padding(12).background(VigiaTheme.panel)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
