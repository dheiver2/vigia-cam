import Foundation
import AppKit

/// Gera relatório PDF de eventos por período (para instrução de editais/processos).
enum ReportService {

    /// Monta um PDF paginado a partir dos eventos e devolve a URL salva.
    static func gerarPDF(eventos: [EventService.Evento], periodo: String,
                         usuario: String, cameras: Int) -> URL? {
        let pageW: CGFloat = 595, pageH: CGFloat = 842   // A4 em pontos (72dpi)
        let margem: CGFloat = 40
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = StorageService.shared.dirEventos
            .appendingPathComponent("relatorio-\(f.string(from: Date())).pdf")
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        let titulo: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black]
        let sub: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray]
        let cabec: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.white]
        let linha: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.black]

        let cols: [(String, CGFloat)] = [
            ("Data", 70), ("Hora", 55), ("Tipo", 120), ("Câmera", 150), ("Detalhe", 190)]
        let linhasPorPagina = 40
        let paginas = max(1, Int(ceil(Double(eventos.count) / Double(linhasPorPagina))))

        func desenhar(_ s: String, _ attrs: [NSAttributedString.Key: Any], x: CGFloat, y: CGFloat, w: CGFloat) {
            let ns = NSAttributedString(string: s, attributes: attrs)
            let path = CGPath(rect: CGRect(x: x, y: y - 11, width: w, height: 12), transform: nil)
            let fs = CTFramesetterCreateWithAttributedString(ns)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: min(ns.length, 60)), path, nil)
            CTFrameDraw(frame, ctx)
        }

        for p in 0..<paginas {
            ctx.beginPDFPage(nil)
            // NSGraphicsContext p/ desenhar textos com AppKit
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns

            var y = pageH - margem
            if p == 0 {
                NSAttributedString(string: "VIGIA·CAM — Relatório de Eventos", attributes: titulo)
                    .draw(at: NSPoint(x: margem, y: y - 22))
                y -= 34
                let ger = DateFormatter(); ger.dateFormat = "dd/MM/yyyy HH:mm"
                let info = "Período: \(periodo)   •   Câmeras: \(cameras)   •   Total de eventos: \(eventos.count)   •   Emitido por: \(usuario) em \(ger.string(from: Date()))"
                NSAttributedString(string: info, attributes: sub).draw(at: NSPoint(x: margem, y: y - 12))
                y -= 26
            }

            // cabeçalho da tabela
            ctx.setFillColor(NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).cgColor)
            ctx.fill(CGRect(x: margem, y: y - 16, width: pageW - 2 * margem, height: 18))
            var x = margem + 4
            for (t, w) in cols { desenhar(t, cabec, x: x, y: y - 3, w: w); x += w }
            y -= 22

            let ini = p * linhasPorPagina
            let fim = min(ini + linhasPorPagina, eventos.count)
            if ini < eventos.count {
                for (i, ev) in eventos[ini..<fim].enumerated() {
                    if i % 2 == 0 {
                        ctx.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
                        ctx.fill(CGRect(x: margem, y: y - 14, width: pageW - 2 * margem, height: 15))
                    }
                    let vals = [ev.data, ev.hora, ev.tipo, ev.camera, ev.detalhe]
                    x = margem + 4
                    for (j, w) in cols.map({ $0.1 }).enumerated() {
                        desenhar(vals[j], linha, x: x, y: y - 2, w: w - 6); x += w
                    }
                    y -= 15
                }
            }

            NSAttributedString(string: "Página \(p + 1)/\(paginas)   —   documento gerado automaticamente pelo VIGIA·CAM",
                               attributes: sub).draw(at: NSPoint(x: margem, y: margem - 14))
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        StorageService.shared.auditar("relatorio_pdf", detalhe: "eventos=\(eventos.count) periodo=\(periodo)", usuario: usuario)
        return url
    }
}
