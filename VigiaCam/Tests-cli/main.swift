import Foundation

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

print("\nResultado: \(passou) passaram, \(falhou) falharam")
exit(falhou == 0 ? 0 : 1)
