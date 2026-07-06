import SwiftUI

struct LiveBadge: View {
    var body: some View {
        Text("AO VIVO")
            .font(.system(size: 9, weight: .black))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(VigiaTheme.danger)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: VigiaTheme.danger.opacity(0.5), radius: 4)
    }
}

struct OfflineBadge: View {
    var body: some View {
        Text("OFFLINE")
            .font(.system(size: 9, weight: .black))
            .foregroundColor(VigiaTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(VigiaTheme.border)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct RecBadge: View {
    @State private var pulsando = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.white).frame(width: 6, height: 6)
                .opacity(pulsando ? 0.25 : 1)
            Text("REC").font(.system(size: 9, weight: .black)).foregroundColor(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(VigiaTheme.danger)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulsando = true }
        }
    }
}

struct FPSCaption: View {
    let fps: Double
    var body: some View {
        Text(String(format: "%.0f fps", fps))
            .font(.system(size: 10))
            .foregroundColor(VigiaTheme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(VigiaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct DetectionChips: View {
    let count: [String: Int]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(count.prefix(3)), id: \.key) { label, qty in
                Text("\(label) (\(qty))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(VigiaTheme.accent2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(VigiaTheme.accent2Glow)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

struct KPICardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(VigiaTheme.text)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(VigiaTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VigiaTheme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VigiaTheme.border, lineWidth: 1))
        .overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
