import SwiftUI

/// Painel de NEGÓCIO por vertical: escolhe o nicho, aplica o pacote de solução
/// (regras + classes) e mostra os KPIs relevantes àquele mercado.
struct BusinessDashboardView: View {
    @ObservedObject private var metrics = BusinessMetricsService.shared
    @State private var nicho: Nicho = .varejo
    @State private var aplicado: Nicho?

    enum Janela: String, CaseIterable, Identifiable {
        case aoVivo = "Ao vivo"
        case dias7 = "7 dias"
        case dias30 = "30 dias"
        var id: String { rawValue }
        var dias: Int? {   // nil = ao vivo (sem janela histórica)
            switch self {
            case .aoVivo: return nil
            case .dias7: return 7
            case .dias30: return 30
            }
        }
    }
    @State private var janela: Janela = .aoVivo

    private let cols = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    /// `nil` quando "Ao vivo" está selecionado — os KPIs seguem lendo direto
    /// de `metrics.porCamera`, como sempre fizeram.
    ///
    /// Era uma computed property que rodava `somarPeriodo` DUAS vezes e era
    /// avaliada dentro do ForEach dos KPIs: com 4 cards davam 8 varreduras
    /// SQLite síncronas na main thread a cada redraw. Agora é calculada uma vez
    /// por mudança de janela, fora da main.
    @State private var comparacao: (atual: BusinessMetricsService.Metrica, anterior: BusinessMetricsService.Metrica)?
    @State private var carregandoComparacao = false

    private func recalcularComparacao() {
        guard let dias = janela.dias else { comparacao = nil; return }
        carregandoComparacao = true
        DispatchQueue.global(qos: .userInitiated).async {
            let agora = Date()
            let inicioAtual = agora.addingTimeInterval(-Double(dias) * 86400)
            let inicioAnterior = inicioAtual.addingTimeInterval(-Double(dias) * 86400)
            let atual = EventStore.shared.somarPeriodo(desde: inicioAtual, ate: agora)
            let anterior = EventStore.shared.somarPeriodo(desde: inicioAnterior, ate: inicioAtual)
            DispatchQueue.main.async {
                comparacao = (atual, anterior)
                carregandoComparacao = false
            }
        }
    }

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

                // janela de comparação — "Ao vivo" preserva o comportamento de sempre
                HStack {
                    Text("Janela").font(.system(size: 12, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                    Picker("", selection: $janela) {
                        ForEach(Janela.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    Spacer()
                    if let dias = janela.dias {
                        Text("vs \(dias) dias anteriores").font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                    }
                }

                // KPIs do nicho
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(nicho.kpis, id: \.self) { kpi in
                        if let comparacao, !BusinessMetricsService.kpisSemJanela.contains(kpi) {
                            let r = metrics.valorComparado(kpi: kpi, atual: comparacao.atual, anterior: comparacao.anterior)
                            KPICardView(title: kpi, value: r.atual, icon: iconeKPI(kpi), color: corKPI(kpi), variacaoPct: r.variacaoPct)
                        } else {
                            // Sem janela (ou KPI que só existe ao vivo): mostra o
                            // valor instantâneo SEM seta de variação, em vez de
                            // exibir "vs N dias" com 0% eterno.
                            KPICardView(title: kpi, value: metrics.valor(kpi: kpi), icon: iconeKPI(kpi), color: corKPI(kpi))
                        }
                    }
                }

                // entregáveis recomendados p/ este nicho — orientação de uso dos
                // recursos que já existem (Relatórios, detalhe da câmera), não
                // atalho de navegação: evita acoplar este painel à navegação
                // por abas do app.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entregáveis recomendados para \(nicho.nome)")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    ForEach(nicho.analiticosRecomendados) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icone).font(.system(size: 13)).foregroundColor(VigiaTheme.accent)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.titulo).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                Text(item.motivo).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(10).background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
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
        .onAppear(perform: recalcularComparacao)
        .onChange(of: janela) { recalcularComparacao() }
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
