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
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(VigiaTheme.accent)
                            Text("Carregando stream...").font(.system(size: 14)).foregroundColor(VigiaTheme.muted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.background(Color.black)
                HStack {
                    Label(camera.tipo.label, systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label(camera.categoria, systemImage: "folder").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label(camera.url, systemImage: "link").font(.system(size: 11, design: .monospaced)).lineLimit(1)
                }.foregroundColor(VigiaTheme.muted).padding(12).background(VigiaTheme.panel)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
