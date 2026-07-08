import Foundation
import CoreGraphics

// Stub de Detection p/ testar o ObjectTracker isolado (o real vive em
// DetectorService.swift, que importa Vision e não compila sem Xcode).
struct Detection: Identifiable { let id = UUID(); let label: String; let confidence: Float; let boundingBox: CGRect }

// Testes de lógica pura executáveis SEM Xcode (só Command Line Tools).
// Compilados junto com os fontes reais por ../run_tests.sh — não usam XCTest.
// A suíte XCTest completa (Crypto/RBAC/Storage) fica em Sources/VigiaCamTests
// e roda com `swift test` em máquinas com Xcode.

var passou = 0, falhou = 0
func check(_ cond: Bool, _ nome: String) {
    if cond { passou += 1; print("  ✓ \(nome)") }
    else { falhou += 1; print("  ✗ FALHOU: \(nome)") }
}

print("== Camera ==")
let c = Camera.normalize(["url": "rtsp://ex.com/s", "nome": "Cam1"])
check(c != nil, "normalize URL válida retorna câmera")
check(c?.nome == "Cam1", "normalize preserva nome")
check(c?.tipo == .rtsp, "normalize infere tipo rtsp")
check(Camera.normalize(["url": ""]) == nil, "normalize rejeita URL vazia")
check(Camera.normalize(["url": "https://b.com/x.m3u8"])?.nome == "https://b.com/x.m3u8",
      "normalize usa URL como nome padrão")

let cams = [
    Camera(nome: "A1", categoria: "Entrada", tipo: .rtsp, url: "rtsp://a/1"),
    Camera(nome: "A2", categoria: "Entrada", tipo: .rtsp, url: "rtsp://a/2"),
    Camera(nome: "B1", categoria: "Pátio", tipo: .hls, url: "https://b/1"),
]
let grupos = Camera.groupByCategory(cams)
check(grupos.count == 2, "groupByCategory agrupa em 2 categorias")
check(grupos.first(where: { $0.0 == "Entrada" })?.1.count == 2, "categoria Entrada tem 2 câmeras")

print("== AppConfig ==")
let inval = AppConfig(fpsMax: 999, confianca: -1, imgsz: 500, classes: nil,
                      colunas: 2, linhas: 2, retencapDias: 30, zonasPrivacidade: nil)
let v = inval.validated()
check(v.fpsMax == 60, "clampa fpsMax ao máximo (60)")
check(v.confianca == 0.05, "clampa confiança ao mínimo (0.05)")
check(v.imgsz % 32 == 0, "imgsz ajustado a múltiplo de 32")
let d = AppConfig.default
check(d.fpsMax == 15 && d.imgsz == 480 && d.confianca == 0.40, "valores padrão corretos")

print("== AlarmRule ==")
let r = AlarmRule(nome: "Aglomeração", classe: "person", limite: 5, escopo: nil, severidade: .aviso)
check(r.casaCamera(nome: "Qualquer", categoria: "X"), "escopo nil casa qualquer câmera")
let rEsc = AlarmRule(nome: "R", classe: "car", limite: 3, escopo: "Pátio", severidade: .info)
check(rEsc.casaCamera(nome: "Z", categoria: "Pátio"), "escopo casa por categoria")
check(rEsc.casaCamera(nome: "Pátio", categoria: "Outra"), "escopo casa por nome")
check(!rEsc.casaCamera(nome: "Z", categoria: "Outra"), "escopo NÃO casa fora do alvo")
check(AlarmRule.exemplos.count == 3, "3 regras de exemplo")
check(Severidade.critico.label == "Crítico", "label de severidade")
check(Severidade.allCases.count == 3, "3 níveis de severidade")

print("== ObjectTracker ==")
let tk = ObjectTracker()
var t = 100.0
for i in 0..<5 {
    let x = 0.1 + Double(i) * 0.15   // objeto atravessa a cena
    tk.update([Detection(label: "car", confidence: 0.9,
                         boundingBox: CGRect(x: x, y: 0.4, width: 0.2, height: 0.2))], now: t)
    t += 0.4
}
let conf = tk.predicted(at: t)
check(conf.count == 1, "1 track confirmado após 5 detecções")
check(conf.first?.vx ?? 0 > 0.2, "velocidade estimada para a direita")
let b0 = tk.predicted(at: t).first?.box.minX ?? 0
let b1 = tk.predicted(at: t + 0.2).first?.box.minX ?? 0
check(b1 > b0, "box extrapola para frente entre inferências (fim do delay)")
check(tk.unicosPorClasse["car"] == 1, "1 objeto único contado")
tk.update([Detection(label: "car", confidence: 0.8,
                     boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1))], now: t + 0.4)
check(tk.unicosPorClasse["car"] == 2, "objeto distante vira 2º único")

print("== LineCounter (tripwire) ==")
let lc = LineCounter()
lc.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.3, y: 0.5))])
lc.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.7, y: 0.5))])
check(lc.totalEntradas + lc.totalSaidas == 1, "conta 1 cruzamento de linha")
let lc3 = LineCounter()
lc3.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.2, y: 0.5))])
lc3.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.3, y: 0.5))])
check(lc3.totalEntradas + lc3.totalSaidas == 0, "não conta sem cruzar")

print("== ZoneMonitor ==")
let zm = ZoneMonitor()
zm.zonas = [ZonaAnalise(x: 0.4, y: 0.4, w: 0.2, h: 0.2, tipo: .intrusao)]
let ev = zm.update([Alvo(id: 1, classe: "person", centro: CGPoint(x: 0.5, y: 0.5))], now: 100)
check(zm.ocupacao.values.reduce(0, +) == 1, "ocupação conta objeto dentro da zona")
check(ev.contains { $0.tipo == .intrusao }, "intrusão emitida na entrada")
let zp = ZoneMonitor(); zp.limiarPermanenciaSeg = 8
zp.zonas = [ZonaAnalise(x: 0, y: 0, w: 1, h: 1, tipo: .permanencia)]
_ = zp.update([Alvo(id: 5, classe: "person", centro: CGPoint(x: 0.5, y: 0.5))], now: 200)
let loit = zp.update([Alvo(id: 5, classe: "person", centro: CGPoint(x: 0.5, y: 0.5))], now: 209)
check(loit.contains { $0.tipo == .permanencia }, "permanência (loitering) após o limiar")

print("\nResultado: \(passou) passaram, \(falhou) falharam")
exit(falhou == 0 ? 0 : 1)
