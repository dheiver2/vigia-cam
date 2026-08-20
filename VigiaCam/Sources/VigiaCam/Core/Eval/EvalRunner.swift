import AppKit
import Foundation

/// Harness de métricas de detecção (Fase 0 do plano de qualidade).
///
/// `VigiaCam --eval <dir>` roda o pipeline REAL (Vision/CoreML + parse + NMS,
/// o mesmo do app) sobre cada imagem do diretório que tenha um JSON de
/// ground-truth ao lado (`foo.jpg` + `foo.json`) e imprime precisão, recall e
/// IoU médio por classe — o número que qualquer ajuste de detecção tem que
/// melhorar. Sem isso, calibração de threshold/NMS/modo noturno é chute.
///
/// Formato do ground-truth (pixels, origem no canto SUPERIOR-esquerdo, como
/// qualquer ferramenta de anotação exporta):
///   [{"label": "bus", "x1": 12, "y1": 223, "x2": 809, "y2": 738}, ...]
///
/// Um acerto (TP) é detecção com a MESMA classe e IoU >= 0,5 com um GT ainda
/// não casado (associação gulosa por IoU decrescente — padrão Pascal VOC).
enum EvalRunner {
    struct GT: Decodable { let label: String; let x1: Double; let y1: Double; let x2: Double; let y2: Double }

    /// Chamado no init do app; se `--eval` está nos argumentos, roda e encerra
    /// o processo antes de qualquer UI subir.
    static func rodarSeSolicitado() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--eval"), args.count > i + 1 else { return }
        exit(rodar(dir: URL(fileURLWithPath: args[i + 1])) ? 0 : 1)
    }

    static func rodar(dir: URL) -> Bool {
        let fm = FileManager.default
        guard let arquivos = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            print("eval: diretório inválido: \(dir.path)"); return false
        }
        let imagens = arquivos.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .filter { fm.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !imagens.isEmpty else {
            print("eval: nenhuma imagem com .json de ground-truth em \(dir.path)"); return false
        }

        let detector = DetectorService()
        // O modelo carrega numa fila própria — espera síncrona só aqui (CLI).
        let inicio = Date()
        while !detector.isLoaded {
            if detector.indisponivel || Date().timeIntervalSince(inicio) > 30 {
                print("eval: modelo não carregou (indisponível=\(detector.indisponivel))"); return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        // Acumuladores por classe: TP, FP, FN e soma de IoU dos TPs.
        var tp: [String: Int] = [:], fp: [String: Int] = [:], fn: [String: Int] = [:]
        var somaIoU: [String: Double] = [:]

        for url in imagens {
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let dadosGT = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json")),
                  let gts = try? JSONDecoder().decode([GT].self, from: dadosGT) else {
                print("eval: pulando \(url.lastPathComponent) (imagem/JSON ilegível)"); continue
            }
            let W = Double(cg.width), H = Double(cg.height)
            // GT em pixels topo-esquerda -> convenção Vision (normalizado,
            // origem inferior-esquerda), a mesma das boundingBox do detector.
            let gtBoxes = gts.map { g in
                (label: g.label,
                 box: CGRect(x: g.x1 / W, y: (H - g.y2) / H,
                             width: (g.x2 - g.x1) / W, height: (g.y2 - g.y1) / H))
            }
            let dets = detector.detectar(img)

            // Associação gulosa: pares (det, gt) da mesma classe por IoU
            // decrescente; cada lado casa no máximo uma vez.
            var pares: [(d: Int, g: Int, iou: Double)] = []
            for (di, d) in dets.enumerated() {
                for (gi, g) in gtBoxes.enumerated() where g.label == d.label {
                    let v = iou(d.boundingBox, g.box)
                    if v >= 0.5 { pares.append((di, gi, v)) }
                }
            }
            pares.sort { $0.iou > $1.iou }
            var dUsado = Set<Int>(), gUsado = Set<Int>()
            for p in pares where !dUsado.contains(p.d) && !gUsado.contains(p.g) {
                dUsado.insert(p.d); gUsado.insert(p.g)
                let cls = dets[p.d].label
                tp[cls, default: 0] += 1
                somaIoU[cls, default: 0] += p.iou
            }
            for (di, d) in dets.enumerated() where !dUsado.contains(di) { fp[d.label, default: 0] += 1 }
            for (gi, g) in gtBoxes.enumerated() where !gUsado.contains(gi) { fn[g.label, default: 0] += 1 }
        }

        let classes = Set(tp.keys).union(fp.keys).union(fn.keys).sorted()
        print("\n== Métricas de detecção (\(imagens.count) imagem(ns), IoU>=0.5, conf>=\(String(format: "%.2f", detector.confidenceThreshold)), modelo \(ModelProvider.tipoAtivo.arquivo)) ==")
        print(String(format: "%-16@ %6@ %6@ %6@ %9@ %8@ %8@", "classe", "TP", "FP", "FN", "precisão", "recall", "IoU médio").replacingOccurrences(of: "@", with: "s"))
        var tTP = 0, tFP = 0, tFN = 0
        for c in classes {
            let t = tp[c] ?? 0, f = fp[c] ?? 0, n = fn[c] ?? 0
            tTP += t; tFP += f; tFN += n
            let prec = t + f > 0 ? Double(t) / Double(t + f) : 0
            let rec = t + n > 0 ? Double(t) / Double(t + n) : 0
            let miou = t > 0 ? (somaIoU[c] ?? 0) / Double(t) : 0
            print(String(format: "%-16s %6d %6d %6d %8.0f%% %7.0f%% %8.2f",
                         (c as NSString).utf8String!, t, f, n, prec * 100, rec * 100, miou))
        }
        let precT = tTP + tFP > 0 ? Double(tTP) / Double(tTP + tFP) : 0
        let recT = tTP + tFN > 0 ? Double(tTP) / Double(tTP + tFN) : 0
        print(String(format: "%-16s %6d %6d %6d %8.0f%% %7.0f%%", ("TOTAL" as NSString).utf8String!, tTP, tFP, tFN, precT * 100, recT * 100))
        return true
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let ia = inter.width * inter.height
        let ua = a.width * a.height + b.width * b.height - ia
        return ua > 0 ? Double(ia / ua) : 0
    }
}
