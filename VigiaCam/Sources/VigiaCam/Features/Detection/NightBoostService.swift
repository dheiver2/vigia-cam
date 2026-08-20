import CoreImage
import CoreGraphics
import Foundation

/// Realce de baixa luz aplicado ao frame ANTES da inferência YOLO — o "modo
/// noturno" de detecção. Os modelos COCO foram treinados majoritariamente com
/// cenas bem iluminadas; em cena escura o recall despenca não porque o objeto
/// sumiu, mas porque o contraste local ficou abaixo do que as primeiras
/// camadas conseguem extrair. Levantar exposição/sombras + corrigir gamma
/// recupera boa parte desse recall sem trocar de modelo.
///
/// Modos: desligado, auto (só realça quando o frame está escuro de fato,
/// medido por luminância média) e sempre.
enum NightBoost {
    enum Modo: String, CaseIterable {
        case desligado, auto, sempre

        var titulo: String {
            switch self {
            case .desligado: return "Desligado"
            case .auto: return "Auto"
            case .sempre: return "Sempre"
            }
        }
    }

    private static let chaveDefaults = "modoNoturnoDeteccao"

    static var modo: Modo {
        get { Modo(rawValue: UserDefaults.standard.string(forKey: chaveDefaults) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: chaveDefaults) }
    }

    /// Abaixo desta luminância média (0–1) o modo `auto` considera a cena
    /// escura. 0,25 ≈ rua à noite com postes; interiores iluminados ficam
    /// tipicamente acima de 0,4.
    static let limiarEscuro: Double = 0.25

    /// Contexto CI compartilhado — criar um por frame custa caro (aloca
    /// pipeline de GPU); um único é thread-safe para render.
    private static let ctx = CIContext(options: [.cacheIntermediates: false])

    /// Luminância média do frame (0–1) via `CIAreaAverage` — reduz a imagem
    /// inteira a 1 pixel na GPU, muito mais barato que varrer bytes na CPU.
    static func luminanciaMedia(_ imagem: CIImage) -> Double {
        guard let filtro = CIFilter(name: "CIAreaAverage") else { return 1 }
        filtro.setValue(imagem, forKey: kCIInputImageKey)
        filtro.setValue(CIVector(cgRect: imagem.extent), forKey: "inputExtent")
        guard let saida = filtro.outputImage else { return 1 }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(saida, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // Rec. 709 — mesma ponderação usada pra converter RGB em luma.
        return (0.2126 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.0722 * Double(px[2])) / 255.0
    }

    /// Realça o frame para detecção noturna. Devolve a imagem original quando
    /// o modo está desligado, quando (em `auto`) a cena não está escura, ou se
    /// qualquer filtro falhar — nunca piora o caminho feliz.
    static func aplicarSeNecessario(_ cgImage: CGImage) -> CGImage {
        guard modo != .desligado else { return cgImage }
        let entrada = CIImage(cgImage: cgImage)
        if modo == .auto, luminanciaMedia(entrada) > limiarEscuro { return cgImage }
        return realcar(entrada) ?? cgImage
    }

    private static func realcar(_ entrada: CIImage) -> CGImage? {
        var img = entrada

        // 1) Levanta sombras sem estourar os highlights (postes/faróis).
        if let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(0.9, forKey: "inputShadowAmount")
            f.setValue(0.7, forKey: "inputHighlightAmount")
            img = f.outputImage ?? img
        }
        // 2) +1,2 EV de exposição — recupera o nível geral da cena.
        if let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(1.2, forKey: kCIInputEVKey)
            img = f.outputImage ?? img
        }
        // 3) Gamma < 1 clareia os tons médios (onde pessoas/veículos vivem
        //    numa cena noturna) sem re-estourar o que a exposição já levantou.
        if let f = CIFilter(name: "CIGammaAdjust") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(0.75, forKey: "inputPower")
            img = f.outputImage ?? img
        }
        // 4) Redução leve de ruído — sensor no escuro gera grão que o realce
        //    amplifica e vira falso positivo de "objeto pequeno".
        if let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(0.02, forKey: "inputNoiseLevel")
            f.setValue(0.40, forKey: "inputSharpness")
            img = f.outputImage ?? img
        }
        return ctx.createCGImage(img, from: entrada.extent)
    }
}
