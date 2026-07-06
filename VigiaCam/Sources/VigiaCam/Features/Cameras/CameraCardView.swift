import SwiftUI

struct CameraCardView: View {
    let camera: Camera
    @StateObject private var vm: CameraCardViewModel
    @State private var isHovered = false
    @State private var showingDetail = false

    init(camera: Camera) {
        self.camera = camera
        _vm = StateObject(wrappedValue: CameraCardViewModel(camera: camera))
    }

    var body: some View {
        Button(action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    if let img = vm.frameImage {
                        ZStack {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 140)
                                .clipped()
                            // Bounding boxes overlay
                            if !vm.lastDetections.isEmpty {
                                DetectionOverlay(detections: vm.lastDetections, imageSize: img.size)
                                    .frame(height: 140)
                                    .clipped()
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(VigiaTheme.bg)
                            .frame(height: 140)
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView().tint(VigiaTheme.accent)
                                    Text("Conectando...")
                                        .font(.system(size: 11))
                                        .foregroundColor(VigiaTheme.muted)
                                }
                            )
                    }
                    HStack(spacing: 6) {
                        if vm.isOnline { LiveBadge() } else { OfflineBadge() }
                        Spacer()
                        FPSCaption(fps: vm.fps)
                    }.padding(8)
                    if !vm.detectionCount.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                DetectionChips(count: vm.detectionCount)
                                Spacer()
                            }.padding(6)
                        }
                    }
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
            .background(VigiaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHovered ? VigiaTheme.accent : VigiaTheme.border, lineWidth: isHovered ? 1.5 : 1))
            .shadow(color: isHovered ? VigiaTheme.accentGlow : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering } }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showingDetail) {
            CameraDetailView(camera: camera)
        }
    }
}

struct DetectionOverlay: View {
    let detections: [Detection]
    let imageSize: NSSize

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { det in
                let box = det.boundingBox
                let x = box.origin.x * geo.size.width
                let y = (1.0 - box.origin.y - box.size.height) * geo.size.height
                let w = box.size.width * geo.size.width
                let h = box.size.height * geo.size.height

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Detection.color(for: det.label), lineWidth: 2)
                        .frame(width: w, height: h)
                        .position(x: x + w/2, y: y + h/2)
                    Text("\(det.label) \(Int(det.confidence * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Detection.color(for: det.label))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .position(x: x + w/2, y: y - 8)
                }
            }
        }
    }
}
