import Foundation
import AppKit

/// Decodifica streams RTSP via `ffmpeg` (processo externo).
///
/// O `AVFoundation` do macOS NUNCA suportou RTSP nativamente — só HLS/HTTP
/// progressivo. Antes desta classe, `CameraService` mandava QUALQUER url
/// (inclusive `rtsp://`) direto pro `AVPlayer`, que falhava para sempre e
/// silenciosamente: daí câmeras rtsp:// ficarem eternamente em "Sem resposta
/// do servidor", não importa a rede.
///
/// Usa o formato PPM (`-f image2pipe -vcodec ppm`) em vez de rawvideo: cada
/// frame já vem com um cabeçalho de texto "P6\nW H\n255\n" antes dos bytes
/// RGB, então não é preciso rodar `ffprobe` antes só pra descobrir a
/// resolução do stream.
final class FFmpegRTSPSource {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var buffer = Data()
    private(set) var isRunning = false

    var onFrame: ((NSImage) -> Void)?
    var onEnded: (() -> Void)?

    private static let ffmpegPath: String = {
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return "ffmpeg"   // último recurso: resolvido pelo PATH do processo
    }()

    func start(url: String, fps: Double) {
        stop()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.ffmpegPath)
        proc.arguments = [
            "-rtsp_transport", "tcp",     // TCP é mais tolerante a firewall/NAT que UDP
            "-stimeout", "8000000",       // timeout de conexão (µs) — não trava pra sempre numa câmera morta
            "-i", url,
            "-an",
            "-f", "image2pipe",
            "-vcodec", "ppm",
            "-vf", "fps=\(max(1.0, min(fps, 30.0)))",
            "-loglevel", "error",
            "pipe:1"
        ]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()   // descartado; evita que o buffer de erro encha e trave o ffmpeg
        stdoutPipe = stdout
        buffer.removeAll()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.buffer.append(data)
            self.extrairFrames()
        }

        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.isRunning = false
            self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self.onEnded?() }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
        } catch {
            print("[FFmpegRTSPSource] falha ao iniciar ffmpeg (\(Self.ffmpegPath) instalado?): \(error)")
            DispatchQueue.main.async { [weak self] in self?.onEnded?() }
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        stdoutPipe = nil
        buffer.removeAll()
        isRunning = false
    }

    /// Extrai quantos frames PPM completos já estiverem no buffer acumulado.
    private func extrairFrames() {
        while true {
            let base = buffer.startIndex
            guard let header = Self.parseHeaderPPM(buffer) else { return }
            let totalLen = header.headerLength + header.width * header.height * 3
            guard buffer.count >= totalLen else { return }   // frame ainda incompleto

            let headerEnd = base + header.headerLength
            let frameEnd = base + totalLen
            let pixelData = buffer.subdata(in: headerEnd..<frameEnd)
            if let imagem = Self.criarImagem(rgb: pixelData, width: header.width, height: header.height) {
                DispatchQueue.main.async { [weak self] in self?.onFrame?(imagem) }
            }
            buffer.removeSubrange(base..<frameEnd)
        }
    }

    private struct HeaderPPM { let width: Int; let height: Int; let headerLength: Int }

    /// Cabeçalho PPM binário (P6): "P6\n<W> <H>\n255\n" seguido dos bytes RGB
    /// crus. `headerLength` é o nº de bytes até o fim do cabeçalho (relativo
    /// ao início do buffer), não um índice absoluto — quem chama soma pelo
    /// `startIndex` real do `Data` (que avança a cada `removeSubrange`).
    private static func parseHeaderPPM(_ data: Data) -> HeaderPPM? {
        guard data.count > 2, data[data.startIndex] == UInt8(ascii: "P"),
              data[data.startIndex + 1] == UInt8(ascii: "6") else { return nil }

        var valores: [Int] = []
        var tokenStart: Data.Index?
        var idx = data.startIndex + 2
        while idx < data.endIndex {
            let b = data[idx]
            let isWhitespace = (b == 0x20 || b == 0x0A || b == 0x09 || b == 0x0D)
            if isWhitespace {
                if let start = tokenStart, start < idx {
                    if let v = Int(String(decoding: data[start..<idx], as: UTF8.self)) { valores.append(v) }
                    tokenStart = nil
                }
                if valores.count == 3 {
                    return HeaderPPM(width: valores[0], height: valores[1], headerLength: idx + 1 - data.startIndex)
                }
            } else if tokenStart == nil {
                tokenStart = idx
            }
            idx += 1
        }
        return nil   // cabeçalho ainda não chegou por completo — espera mais bytes
    }

    private static func criarImagem(rgb: Data, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0, rgb.count == width * height * 3,
              let provider = CGDataProvider(data: rgb as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    deinit { stop() }
}
