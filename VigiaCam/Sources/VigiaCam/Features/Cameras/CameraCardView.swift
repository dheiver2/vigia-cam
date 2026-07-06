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
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 140)
                            .clipped()
                            .overlay(
                                DetectionOverlay(detections: vm.lastDetections)
                                    .frame(height: 140)
                                    .clipped(),
                                alignment: .center
                            )
                    } else {
                        Rectangle()
                            .fill(Color(VigiaTheme.bg))
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
                }
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

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { det in
                let box = det.boundingBox
                let x = box.origin.x * geo.size.width
                let y = (1.0 - box.origin.y - box.size.height) * geo.size.height
                let w = box.size.width * geo.size.width
                let h = box.size.height * geo.size.height
                let color = DetectorService.color(for: det.label)

                RoundedRectangle(cornerRadius: 2)
                    .stroke(color, lineWidth: 2)
                    .frame(width: max(w, 20), height: max(h, 20))
                    .position(x: x + w / 2, y: y + h / 2)
                    .overlay(
                        Text("\(det.label) \(Int(det.confidence * 100))%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(color)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .position(x: x + w / 2, y: y - 6),
                        alignment: .top
                    )
            }
        }
    }
}
