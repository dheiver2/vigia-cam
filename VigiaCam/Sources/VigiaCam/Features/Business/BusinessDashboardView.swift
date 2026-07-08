import SwiftUI

/// Painel de NEGÓCIO por vertical: escolhe o nicho, aplica o pacote de solução
/// (regras + classes) e mostra os KPIs relevantes àquele mercado.
struct BusinessDashboardView: View {
    @ObservedObject private var metrics = BusinessMetricsService.shared
    @State private var nicho: Nicho = .varejo
    @State private var aplicado: Nicho?

    private let cols = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inteligência de Negócio").font(.system(size: 20, weight: .bold)).foregroundColor(.white)

                // seletor de nicho
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Nicho.allCases) { n in
                            Button { nicho = n } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: n.icone)
                                    Text(n.nome).font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(nicho == n ? .black : VigiaTheme.text)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(nicho == n ? AnyView(VigiaTheme.accentGradient) : AnyView(VigiaTheme.card))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text(nicho.descricao).font(.system(size: 13)).foregroundColor(VigiaTheme.muted)
                    Spacer()
                    Button {
                        nicho.aplicar(); aplicado = nicho
                    } label: {
                        HStack { Image(systemName: "wand.and.stars"); Text("Aplicar pacote") }
                    }.buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
                }
                if aplicado == nicho {
                    Label("Pacote \(nicho.nome) aplicado — regras e classes de detecção configuradas.",
                          systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12)).foregroundColor(VigiaTheme.ok)
                }

                // KPIs do nicho
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(nicho.kpis, id: \.self) { kpi in
                        KPICardView(title: kpi, value: metrics.valor(kpi: kpi),
                                    icon: iconeKPI(kpi), color: corKPI(kpi))
                    }
                }

                // detalhamento por câmera
                if !metrics.porCamera.isEmpty {
                    Text("Por câmera").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    VStack(spacing: 6) {
                        ForEach(metrics.porCamera.sorted(by: { $0.key < $1.key }), id: \.key) { nome, m in
                            HStack {
                                Text(nome).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                Spacer()
                                metricaChip("pessoas", m.unicos["person"] ?? 0, VigiaTheme.accent2)
                                metricaChip("veíc.", (["car","truck","bus","motorcycle"].map { m.unicos[$0] ?? 0 }.reduce(0,+)), VigiaTheme.accent)
                                metricaChip("in", m.entradas, VigiaTheme.ok)
                                metricaChip("out", m.saidas, VigiaTheme.warning)
                                if m.intrusoes > 0 { metricaChip("intrus.", m.intrusoes, VigiaTheme.danger) }
                            }
                            .padding(10).background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    Text("Abra o Ao Vivo para as câmeras começarem a alimentar os indicadores. Configure linha de contagem e zonas no detalhe de cada câmera.")
                        .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                }
            }.padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VigiaTheme.bg)
    }

    private func metricaChip(_ t: String, _ v: Int, _ c: Color) -> some View {
        Text("\(v) \(t)").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.25)).clipShape(Capsule())
    }
    private func iconeKPI(_ k: String) -> String {
        if k.contains("Pessoa") { return "person.2.fill" }
        if k.contains("Veíc") || k.contains("Caminh") { return "car.fill" }
        if k.contains("Entrada") { return "arrow.right.to.line" }
        if k.contains("Saída") { return "arrow.left.to.line" }
        if k.contains("Intrus") { return "exclamationmark.shield.fill" }
        if k.contains("Ocupa") { return "square.grid.3x3.fill" }
        if k.contains("Permanên") { return "clock.badge.exclamationmark" }
        if k.contains("Fluxo") || k.contains("Cruz") { return "arrow.left.arrow.right" }
        return "chart.bar.fill"
    }
    private func corKPI(_ k: String) -> Color {
        if k.contains("Intrus") || k.contains("Permanên") { return VigiaTheme.danger }
        if k.contains("Veíc") || k.contains("Caminh") { return VigiaTheme.accent }
        if k.contains("Pessoa") { return VigiaTheme.accent2 }
        return VigiaTheme.ok
    }
}
