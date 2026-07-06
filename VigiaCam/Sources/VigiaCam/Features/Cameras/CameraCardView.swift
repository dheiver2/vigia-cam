import SwiftUI

struct CameraCardView: View {
    let camera: Camera
    @State private var isHovered = false
    @State private var showingDetail = false
    var frameImage: NSImage?
    var fps: Double = 0
    var detectionCount: [String: Int] = [:]
    var isOnline: Bool = true

    var body: some View {
        Button(action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    if let img = frameImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 140)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(VigiaTheme.bg)
                            .frame(height: 140)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "video.slash")
                                        .font(.system(size: 28))
                                        .foregroundColor(VigiaTheme.border)
                                    Text("Sem sinal")
                                        .font(.system(size: 11))
                                        .foregroundColor(VigiaTheme.muted)
                                }
                            )
                    }
                    HStack(spacing: 6) {
                        if isOnline { LiveBadge() } else { OfflineBadge() }
                        Spacer()
                        FPSCaption(fps: fps)
                    }.padding(8)
                    if !detectionCount.isEmpty {
                        VStack { Spacer(); HStack { DetectionChips(count: detectionCount); Spacer() }.padding(6) }
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
        .sheet(isPresented: $showingDetail) {
            CameraDetailView(camera: camera, frameImage: frameImage, fps: fps, detectionCount: detectionCount)
        }
    }
}
