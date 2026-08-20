import SwiftUI

/// Mapa de calor acumulado de uma câmera num período — visualização estática
/// (sem precisar abrir o Ao Vivo), a partir dos buckets gravados em
/// `EventStore.registrarHeatmap`.
struct HeatmapAcumuladoView: View {
    let cameras: [Camera]

    @State private var cameraSelecionada: String = ""
    @State private var dias = 7
    @State private var resultado: (colunas: Int, linhas: Int, grade: [Int])?
    @State private var carregando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("", selection: $cameraSelecionada) {
                    Text("Selecione a câmera").tag("")
                    ForEach(cameras) { c in Text(c.nome).tag(c.nome) }
                }.labelsHidden().frame(width: 220)
                Stepper("Últimos \(dias) dia(s)", value: $dias, in: 1...90)
                    .foregroundColor(VigiaTheme.text)
                Spacer()
                Button {
                    carregar()
                } label: {
                    HStack { Image(systemName: "flame"); Text(carregando ? "Carregando…" : "Gerar mapa") }
                }.buttonStyle(.borderedProminent).tint(VigiaTheme.warning)
                .disabled(cameraSelecionada.isEmpty || carregando)
            }

            if let r = resultado {
                let maximo = r.grade.max() ?? 0
                if maximo == 0 {
                    Text("Nenhuma detecção registrada nesse período para esta câmera.")
                        .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                } else {
                    GeometryReader { geo in
                        let cw = geo.size.width / CGFloat(r.colunas)
                        let ch = geo.size.height / CGFloat(r.linhas)
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(Color.black.opacity(0.3))
                            ForEach(0..<r.grade.count, id: \.self) { i in
                                let valor = r.grade[i]
                                if valor > 0 {
                                    let col = i % r.colunas, linha = i / r.colunas
                                    Rectangle()
                                        .fill(HeatmapService.cor(valor: valor, maximo: maximo))
                                        .frame(width: cw, height: ch)
                                        .position(x: (CGFloat(col) + 0.5) * cw, y: (CGFloat(linha) + 0.5) * ch)
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Mais quente = mais detecções passaram por ali no período. Pico da célula: \(maximo).")
                        .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                }
            } else if !carregando {
                Text("Escolha uma câmera e gere o mapa acumulado do período.")
                    .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
            }
        }
        .onAppear { if cameraSelecionada.isEmpty { cameraSelecionada = cameras.first?.nome ?? "" } }
    }

    private func carregar() {
        carregando = true
        let camera = cameraSelecionada
        let inicio = Calendar.current.date(byAdding: .day, value: -(dias - 1), to: Date()) ?? Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let r = EventStore.shared.heatmapAcumulado(camera: camera, desde: inicio, ate: Date())
            DispatchQueue.main.async {
                resultado = r
                carregando = false
            }
        }
    }
}
