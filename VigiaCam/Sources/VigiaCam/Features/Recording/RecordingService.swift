import Foundation
import AVFoundation
import AppKit

/// Captura de evidência: snapshot PNG e gravação manual de clipe (MP4), ambos
/// com carimbo de data/hora, hash SHA-256 e cadeia de custódia (via Storage).
final class RecordingService: ObservableObject {
    static let shared = RecordingService()

    /// Câmeras que estão gravando agora (por nome) — dirige o indicador ● REC.
    @Published var gravando: Set<String> = []

    private let storage = StorageService.shared
    private var writers: [String: ClipWriter] = [:]
    private var usuario: String = "sistema"
    private let fila = DispatchQueue(label: "recording", qos: .utility)

    private init() {}

    func definirUsuario(_ u: String) { usuario = u }

    // MARK: - Snapshot

    /// Salva o frame atual como PNG (com carimbo) e registra na cadeia de custódia.
    @discardableResult
    func snapshot(_ image: NSImage, camera: String) -> URL? {
        let carimbada = comCarimbo(image, camera: camera)
        guard let tiff = carimbada.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = storage.caminhoCaptura(camera: camera)
        do {
            try png.write(to: url)
        } catch { return nil }
        _ = storage.registrarCadeia(arquivo: url.path, tipo: "snapshot", camera: camera, usuario: usuario)
        storage.auditar("snapshot", detalhe: "camera=\(camera) arquivo=\(url.lastPathComponent)", usuario: usuario)
        return url
    }

    // MARK: - Gravação manual de clipe

    func estaGravando(_ camera: String) -> Bool { gravando.contains(camera) }

    func alternarGravacao(_ camera: String, tamanho: CGSize, fps: Int = 10) {
        if gravando.contains(camera) { pararGravacao(camera) }
        else { iniciarGravacao(camera, tamanho: tamanho, fps: fps) }
    }

    private func iniciarGravacao(_ camera: String, tamanho: CGSize, fps: Int) {
        let url = storage.caminhoGravacao(camera: camera)
        fila.async { [weak self] in
            guard let self else { return }
            guard let w = ClipWriter(url: url, size: tamanho, fps: fps) else { return }
            self.writers[camera] = w
            DispatchQueue.main.async { self.gravando.insert(camera) }
            self.storage.auditar("gravacao_iniciada", detalhe: "camera=\(camera)", usuario: self.usuario)
        }
    }

    func pararGravacao(_ camera: String) {
        fila.async { [weak self] in
            guard let self, let w = self.writers[camera] else { return }
            let url = w.url
            w.finalizar { [weak self] in
                guard let self else { return }
                _ = self.storage.registrarCadeia(arquivo: url.path, tipo: "gravacao", camera: camera, usuario: self.usuario)
                self.storage.auditar("gravacao_finalizada", detalhe: "camera=\(camera) arquivo=\(url.lastPathComponent)", usuario: self.usuario)
            }
            self.writers[camera] = nil
            DispatchQueue.main.async { self.gravando.remove(camera) }
        }
    }

    /// Alimenta o writer com o frame atual (chamado pelo card enquanto grava).
    func alimentar(_ camera: String, image: NSImage) {
        fila.async { [weak self] in
            self?.writers[camera]?.acrescentar(self!.comCarimbo(image, camera: camera))
        }
    }

    // MARK: - Carimbo forense

    private func comCarimbo(_ image: NSImage, camera: String) -> NSImage {
        let size = image.size
        guard size.width > 0 else { return image }
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let texto = "\(camera)  \(f.string(from: Date()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(11, size.height * 0.028), weight: .semibold),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black, .strokeWidth: -3.0,
        ]
        texto.draw(at: NSPoint(x: 8, y: 6), withAttributes: attrs)
        out.unlockFocus()
        return out
    }
}

/// Encapsula AVAssetWriter para gravar NSImages sequenciais em MP4 H.264.
private final class ClipWriter {
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let size: CGSize
    private let fps: Int
    private var frameIndex: Int64 = 0
    private var iniciado = false

    init?(url: URL, size: CGSize, fps: Int) {
        let w = Int(size.width.rounded()) & ~1     // dimensões pares p/ H.264
        let h = Int(size.height.rounded()) & ~1
        guard w > 0, h > 0, let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        self.url = url; self.size = CGSize(width: w, height: h); self.fps = max(1, fps)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        self.writer = writer
    }

    func acrescentar(_ image: NSImage) {
        if !iniciado {
            writer.startWriting(); writer.startSession(atSourceTime: .zero); iniciado = true
        }
        guard input.isReadyForMoreMediaData, let pb = pixelBuffer(from: image) else { return }
        let t = CMTime(value: frameIndex, timescale: Int32(fps))
        adaptor.append(pb, withPresentationTime: t)
        frameIndex += 1
    }

    func finalizar(_ done: @escaping () -> Void) {
        guard iniciado else { done(); return }
        input.markAsFinished()
        writer.finishWriting(completionHandler: done)
    }

    private func pixelBuffer(from image: NSImage) -> CVPixelBuffer? {
        let w = Int(size.width), h = Int(size.height)
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32ARGB, attrs, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            ctx.draw(cg, in: rect)
        }
        return buffer
    }
}
