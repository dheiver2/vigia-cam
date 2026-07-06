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
                        ZStack {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if !vm.lastDetections.isEmpty {
                                GeometryReader { geo in
                                    ForEach(vm.lastDetections) { det in
                                        let box = det.boundingBox
                                        let x = box.origin.x * geo.size.width
                                        let y = (1.0 - box.origin.y - box.size.height) * geo.size.height
                                        let w = box.size.width * geo.size.width
                                        let h = box.size.height * geo.size.height

                                        VStack(alignment: .leading, spacing: 2) {
                                            Rectangle()
                                                .stroke(Detection.color(for: det.label), lineWidth: 2)
                                                .frame(width: w, height: h)
                                                .position(x: x + w/2, y: y + h/2)
                                            Text("\(det.label) \(Int(det.confidence * 100))%")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 3)
                                                .background(Detection.color(for: det.label))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .position(x: x + w/2, y: y - 10)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(VigiaTheme.accent)
                            Text("Carregando stream...").font(.system(size: 14)).foregroundColor(VigiaTheme.muted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !vm.detectionCount.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                DetectionChips(count: vm.detectionCount)
                                Spacer()
                            }.padding(12)
                        }
                    }
                }.background(Color.black)
                HStack {
                    Label(camera.tipo.label, systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label(camera.categoria, systemImage: "folder").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label("\(vm.detectionCount.values.reduce(0, +)) objetos", systemImage: "viewfinder.rectangular").font(.system(size: 12, weight: .medium))
                }.foregroundColor(VigiaTheme.muted).padding(12).background(VigiaTheme.panel)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
