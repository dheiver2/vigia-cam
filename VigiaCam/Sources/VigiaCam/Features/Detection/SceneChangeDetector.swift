import Foundation
import AppKit

/// Detecção de MUDANÇA DE CENA (câmera tampada, virada ou desfocada):
/// compara o histograma de luminância de um frame amostrado contra a
/// referência estabelecida; queda de correlação sustentada dispara.
final class SceneChangeDetector {
    private var referencia: [Double]?
    private var suspeitasSeguidas = 0
    /// Nº de amostras consecutivas abaixo do limiar antes de disparar — evita
    /// falso positivo com um caminhão passando na frente por um instante.
    private let confirmacoes = 3
    private let limiarCorrelacao = 0.55
    private var disparado = false

    /// Amostra o frame (chamar ~1×/5s). Retorna true no momento da mudança.
    func amostrar(_ img: NSImage) -> Bool {
        guard let h = Self.histograma(img) else { return false }
        guard let ref = referencia else { referencia = h; return false }

        let corr = Self.correlacao(ref, h)
        if corr < limiarCorrelacao {
            suspeitasSeguidas += 1
            if suspeitasSeguidas >= confirmacoes && !disparado {
                disparado = true
                referencia = h        // nova cena vira a referência
                suspeitasSeguidas = 0
                return true
            }
        } else {
            suspeitasSeguidas = 0
            disparado = false
            // Atualização lenta da referência: acompanha mudança gradual de luz
            // (dia/noite) sem perder a sensibilidade a mudanças bruscas.
            referencia = zip(ref, h).map { $0 * 0.95 + $1 * 0.05 }
        }
        return false
    }

    /// Histograma de luminância 32 bins, normalizado, de uma versão reduzida.
    private static func histograma(_ img: NSImage) -> [Double]? {
        let lado = 64
        guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8,
                                  bytesPerRow: lado, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        var rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        guard let dados = ctx.data else { return nil }
        let px = dados.bindMemory(to: UInt8.self, capacity: lado * lado)
        var bins = [Double](repeating: 0, count: 32)
        for i in 0..<(lado * lado) { bins[Int(px[i]) / 8] += 1 }
        let total = Double(lado * lado)
        return bins.map { $0 / total }
    }

    private static func correlacao(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count {
            let xa = a[i] - ma, xb = b[i] - mb
            num += xa * xb; da += xa * xa; db += xb * xb
        }
        let den = (da * db).squareRoot()
        return den > 0 ? num / den : 1
    }
}
