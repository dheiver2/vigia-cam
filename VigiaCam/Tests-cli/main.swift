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
let c = Camera(nome: "Cam1", categoria: "Entrada", url: "rtsp://ex.com/s")
check(c != nil, "URL válida constrói câmera")
check(c?.nome == "Cam1", "preserva nome")
check(c?.tipo == .rtsp, "infere tipo rtsp")
check(Camera(nome: "x", categoria: "y", url: "") == nil, "rejeita URL vazia")
check(Camera(nome: "", categoria: "y", url: "https://b.com/x.m3u8")?.nome == "https://b.com/x.m3u8",
      "usa URL como nome padrão")

let cams = [
    Camera(nome: "A1", categoria: "Entrada", url: "rtsp://a/1")!,
    Camera(nome: "A2", categoria: "Entrada", url: "rtsp://a/2")!,
    Camera(nome: "B1", categoria: "Pátio", url: "https://b/1")!,
]
let grupos = Camera.groupByCategory(cams)
check(grupos.count == 2, "groupByCategory agrupa em 2 categorias")
check(grupos.first(where: { $0.0 == "Entrada" })?.1.count == 2, "categoria Entrada tem 2 câmeras")

print("== AppConfig ==")
let inval = AppConfig(fpsMax: 999, confianca: -1, imgsz: 500, classesMonitoradas: nil,
                      colunas: 2, linhas: 2, retencaoDias: 30)
let v = inval.validated()
check(v.fpsMax == 60, "clampa fpsMax ao máximo (60)")
check(v.confianca == 0.05, "clampa confiança ao mínimo (0.05)")
check(v.imgsz % 32 == 0, "imgsz ajustado a múltiplo de 32")
let d = AppConfig.default
check(d.fpsMax == 15 && d.imgsz == 640 && d.confianca == 0.40, "valores padrão corretos")

print("== AlarmRule ==")
let r = AlarmRule(nome: "Aglomeração", alvo: .classe("person"), limite: 5, severidade: .aviso)
check(r.casaCamera(nome: "Qualquer", categoria: "X"), "escopo .todas casa qualquer câmera")
let rEsc = AlarmRule(nome: "R", alvo: .classe("car"), limite: 3, escopo: .categoria("Pátio"), severidade: .info)
check(rEsc.casaCamera(nome: "Z", categoria: "Pátio"), "escopo casa por categoria")
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

print("== Benchmark: ObjectTracker.update() ==")
// Sem benchmark de latência de detecção real aqui (DetectorService importa Vision/
// CoreML e precisa do .mlmodelc compilado dentro do bundle — não roda fora do app).
// Isto mede o CUSTO DO TRACKER em si, que roda a cada inferência de CADA câmera.
func benchTracker(numTracks: Int, numDets: Int, iters: Int) -> Double {
    let bt = ObjectTracker()
    let labels = ["person", "car", "truck", "bicycle", "dog"]
    var t = 0.0
    // aquece N tracks distintos
    for i in 0..<numTracks {
        let x = Double(i % 50) / 50.0
        bt.update([Detection(label: labels[i % labels.count], confidence: 0.9,
                             boundingBox: CGRect(x: x, y: 0.4, width: 0.05, height: 0.05))], now: t)
        t += 0.4
    }
    let dets = (0..<numDets).map { i -> Detection in
        let x = Double(i % 50) / 50.0
        return Detection(label: labels[i % labels.count], confidence: 0.9,
                         boundingBox: CGRect(x: x, y: 0.4, width: 0.05, height: 0.05))
    }
    let inicio = Date()
    for _ in 0..<iters {
        t += 0.4
        bt.update(dets, now: t)
    }
    return Date().timeIntervalSince(inicio) * 1000 / Double(iters)   // ms/chamada
}
let msPoucos = benchTracker(numTracks: 10, numDets: 10, iters: 200)
let msMuitos = benchTracker(numTracks: 80, numDets: 80, iters: 200)
print(String(format: "  10 tracks/10 det:  %.4f ms/update", msPoucos))
print(String(format: "  80 tracks/80 det:  %.4f ms/update", msMuitos))
check(msMuitos < 50, "update() com 80 tracks/detecções fica sob 50ms (não trava o display loop de 15Hz)")

// MARK: - Camera.urlSuportada

print("\n== Camera.urlSuportada ==")
check(Camera.urlSuportada("https://exemplo.com/a.m3u8"), "aceita https")
check(Camera.urlSuportada("rtsp://10.0.0.5:554/stream"), "aceita rtsp com porta")
check(Camera.urlSuportada("  http://exemplo.com/x  "), "ignora espaços em volta")
check(!Camera.urlSuportada(""), "rejeita vazio")
check(!Camera.urlSuportada("exemplo.com/a.m3u8"), "rejeita URL sem esquema")
check(!Camera.urlSuportada("ftp://exemplo.com/a"), "rejeita esquema não suportado")
check(!Camera.urlSuportada("https://"), "rejeita URL sem host")

// MARK: - Modelagem: identidade, migração e tipos explícitos

print("\n== Camera: identidade separada do endereço ==")
let c1 = Camera(nome: "Portaria", categoria: "Entrada", url: "rtsp://10.0.0.9/live")!
var c2 = c1
c2.url = "rtsp://10.0.0.10/live"     // câmera trocou de IP
check(c1.id == c2.id, "trocar a URL preserva a identidade")
check(c2.tipo == .rtsp, "tipo derivado do esquema (rtsp)")
check(Camera(nome: "x", categoria: "y", url: "https://h/a.m3u8")!.tipo == .hls, "tipo derivado do esquema (hls)")
check(Camera(nome: "x", categoria: "y", url: "não é url") == nil, "init recusa endereço inválido")
check(Camera(nome: "  ", categoria: "  ", url: "https://h/a")!.categoria == "Outras", "categoria vazia cai no padrão")

print("\n== Camera: lê o formato antigo (sem id) ==")
let jsonAntigo = #"[{"nome":"Cam 1","categoria":"Entrada","tipo":"hls","url":"https://h/a.m3u8"}]"#
let antigas = try! JSONDecoder().decode([Camera].self, from: Data(jsonAntigo.utf8))
check(antigas.count == 1, "decodifica registro antigo")
check(antigas[0].id == "https://h/a.m3u8", "sem id, a identidade continua sendo a URL (não perde config por câmera)")
check(antigas[0].nome == "Cam 1", "preserva o nome")

print("\n== AppConfig: limites e migração ==")
let bruta = AppConfig(fpsMax: 999, confianca: 9, imgsz: 5000,
                      classesMonitoradas: [], colunas: 99, linhas: 0, retencaoDias: 99999)
let val = bruta.validated()
check(val.fpsMax == 60, "fpsMax limitado a 60")
check(val.colunas == 8 && val.linhas == 1, "colunas/linhas limitadas (antes passavam direto)")
check(val.retencaoDias == 365, "retenção limitada a 365 (antes passava direto)")
check(val.classesMonitoradas == nil, "conjunto vazio vira nil (= todas)")
let cfgAntigo = #"{"fpsMax":20,"confianca":0.5,"imgsz":480,"colunas":2,"linhas":2,"retencapDias":7,"classes":[0,2]}"#
let cfgMigrado = try! JSONDecoder().decode(AppConfig.self, from: Data(cfgAntigo.utf8))
check(cfgMigrado.retencaoDias == 7, "lê a chave antiga com typo (retencapDias)")
check(cfgMigrado.classesMonitoradas == ["person", "car"], "converte índices COCO antigos para nomes")

print("\n== AlarmRule: alvo e escopo explícitos ==")
let rTodas = AlarmRule(nome: "r", alvo: .qualquerObjeto, limite: 3, severidade: .info)
check(rTodas.casaCamera(nome: "A", categoria: "B"), "escopo .todas casa qualquer câmera")
check(rTodas.alvo.valor(em: ["person": 2, "car": 2]) == 4, "alvo .qualquerObjeto soma tudo")
check(rTodas.disparou(counts: ["person": 3]), "dispara no limite")
check(!rTodas.disparou(counts: ["person": 2]), "não dispara abaixo do limite")
let rCat = AlarmRule(nome: "r", alvo: .classe("person"), limite: 1, escopo: .categoria("Entrada"), severidade: .info)
check(rCat.casaCamera(nome: "X", categoria: "Entrada"), "escopo por categoria casa a categoria")
check(!rCat.casaCamera(nome: "Entrada", categoria: "Outra"), "escopo por categoria NÃO casa uma câmera de mesmo nome")
let rCam = AlarmRule(nome: "r", alvo: .classe("person"), limite: 1, escopo: .camera("Entrada"), severidade: .info)
check(rCam.casaCamera(nome: "Entrada", categoria: "Outra"), "escopo por câmera casa o nome")
check(!rCam.casaCamera(nome: "X", categoria: "Entrada"), "escopo por câmera NÃO casa a categoria homônima")
check(AlarmRule(nome: "r", alvo: .classe("person"), limite: 0, severidade: .info).limite == 1,
      "limite < 1 é corrigido (senão dispararia com zero objetos)")

print("\n== AlarmRule: lê o formato antigo ==")
let regraAntiga = #"{"id":"r1","nome":"Antiga","classe":"qualquer","limite":4,"escopo":"Portaria","severidade":"aviso","ativo":true}"#
let ra = try! JSONDecoder().decode(AlarmRule.self, from: Data(regraAntiga.utf8))
check(ra.alvo == .qualquerObjeto, #"classe "qualquer" vira .qualquerObjeto"#)
check(ra.escopo == .camera("Portaria"), "escopo em texto vira .camera")
check(ra.limite == 4 && ra.id == "r1", "demais campos preservados")
let semEscopo = #"{"nome":"N","classe":"person","limite":2,"severidade":"info"}"#
check(try! JSONDecoder().decode(AlarmRule.self, from: Data(semEscopo.utf8)).escopo == .todas,
      "escopo ausente vira .todas")

print("\n== Vocabulário de classes ==")
check(ClassesCOCO.nomes.count == 80, "COCO tem 80 classes")
check(ClassesCOCO.nome(indice: 0) == "person", "índice 0 = person")
check(ClassesCOCO.nome(indice: 999) == nil, "índice fora da faixa devolve nil")
check(ClassesEPI.nomes.count == 10, "EPI tem 10 classes")
check(ClassesEPI.indice(nome: "NO-Hardhat") == 2, "índice de NO-Hardhat")

// MARK: - CryptoService (persistência da chave)

print("\n== CryptoService ==")
// Regressão: a chave era gravada com `withUnsafeBytes(of: key)`, que pega os
// bytes da struct (um ponteiro) em vez do material da chave. O `SecItemAdd`
// falhava calado e cada chamada gerava uma chave nova — nada do que era salvo
// (câmeras, config, usuários) conseguia ser lido de volta.
let claro = Data("câmera de teste ✓".utf8)
let cifrado = CryptoService.encrypt(claro)
check(cifrado != claro, "encrypt() não devolve o texto claro")
check(CryptoService.decrypt(cifrado) == claro, "decrypt(encrypt(x)) == x")
check(CryptoService.decrypt(Data("lixo".utf8)) == nil, "decrypt() devolve nil em dado inválido")

// A chave tem de vir do Keychain — duas leituras seguidas precisam ser a MESMA,
// senão o dado gravado num lançamento fica ilegível no próximo.
let k1 = CryptoService.loadOrCreateKey().withUnsafeBytes { Data($0) }
let k2 = CryptoService.loadOrCreateKey().withUnsafeBytes { Data($0) }
check(k1.count == 32, "chave tem 256 bits (\(k1.count * 8))")
check(k1 == k2, "loadOrCreateKey() é estável (persistida no Keychain)")

print("\nResultado: \(passou) passaram, \(falhou) falharam")
exit(falhou == 0 ? 0 : 1)
