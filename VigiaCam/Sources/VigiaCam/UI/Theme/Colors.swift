#if canImport(UIKit)
import SwiftUI

/// Paleta visual dark premium.
enum VigiaTheme {
    static let bg = Color(hex: 0x0a0b0e)
    static let panel = Color(hex: 0x121419)
    static let card = Color(hex: 0x171a21)
    static let cardHover = Color(hex: 0x1c1f28)
    static let border = Color(hex: 0x23262f)
    static let borderLight = Color(hex: 0x2e3340)
    static let text = Color(hex: 0xf2f4f8)
    static let muted = Color(hex: 0xaab1c0)
    static let accent = Color(hex: 0xff5a1f)
    static let accentGlow = Color(hex: 0xff5a1f).opacity(0.25)
    static let accent2 = Color(hex: 0x22d3ee)
    static let accent2Glow = Color(hex: 0x22d3ee).opacity(0.25)
    static let ok = Color(hex: 0x34d399)
    static let okGlow = Color(hex: 0x34d399).opacity(0.25)
    static let danger = Color(hex: 0xf87171)
    static let dangerGlow = Color(hex: 0xf87171).opacity(0.25)
    static let warning = Color(hex: 0xfbbf24)
    static let headerGradient = LinearGradient(colors: [panel, bg], startPoint: .top, endPoint: .bottom)
    static let accentGradient = LinearGradient(colors: [accent, Color(hex: 0xff7242)], startPoint: .leading, endPoint: .trailing)
    static let accentGradientPressed = LinearGradient(colors: [Color(hex: 0xe04a15), Color(hex: 0xcc3d10)], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255.0, green: Double((hex >> 8) & 0xFF) / 255.0, blue: Double(hex & 0xFF) / 255.0, opacity: opacity)
    }
}
#endif
