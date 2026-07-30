import SwiftUI

/// Painel de alarmes: ocorrências ao vivo + gestão das regras (analíticos).
struct AlarmsView: View {
    @ObservedObject private var alarms = AlarmService.shared
    let categorias: [String]

    @State private var nome = ""
    @State private var alvo: AlvoAlarme = .classe("person")
    @State private var limite = 5
    @State private var escopo: EscopoAlarme = .todas
    @State private var severidade: Severidade = .aviso

    private let alvos: [AlvoAlarme] = [
        .classe("person"), .classe("car"), .classe("truck"), .classe("bus"),
        .classe("motorcycle"), .classe("bicycle"), .qualquerObjeto
    ]

    /// O seletor listava categorias sob o rótulo "Câmera" e gravava só o texto,
    /// num campo que casava por nome OU categoria. Agora cada opção diz o que é.
    private var escopos: [EscopoAlarme] { [.todas] + categorias.map { EscopoAlarme.categoria($0) } }

    var body: some View {
        HStack(spacing: 0) {
            ocorrencias
            Divider().background(VigiaTheme.border)
            regrasPanel.frame(width: 380)
        }
        .background(VigiaTheme.bg)
    }

    // MARK: - Ocorrências ao vivo

    private var ocorrencias: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ocorrências de alarme").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Spacer()
                Toggle("Som", isOn: $alarms.somAtivo).toggleStyle(.switch).tint(VigiaTheme.accent)
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                Toggle("Auto-evidência", isOn: $alarms.autoSnapshot).toggleStyle(.switch).tint(VigiaTheme.accent)
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            }.padding(.horizontal, 16).padding(.top, 16)

            // Integração: webhook de notificação (SIEM / central)
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.waveform").foregroundColor(VigiaTheme.accent2)
                TextField("Webhook (POST JSON em cada alarme) — https://…", text: $alarms.webhookURL)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
            }.padding(.horizontal, 16).padding(.bottom, 8)

            if alarms.recentes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash").font(.system(size: 40)).foregroundColor(VigiaTheme.border)
                    Text("Nenhum alarme na sessão").foregroundColor(VigiaTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(alarms.recentes) { a in
                            HStack(spacing: 10) {
                                Circle().fill(cor(a.severidade)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.mensagem).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                    Text(a.camera).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                                }
                                Spacer()
                                Text(hora(a.quando)).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                            }
                            .padding(10)
                            .background(VigiaTheme.card)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cor(a.severidade).opacity(0.4)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Regras

    private var regrasPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Regras de detecção").font(.system(size: 15, weight: .bold)).foregroundColor(.white).padding(16)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(alarms.regras) { r in
                        HStack(spacing: 8) {
                            Button { alarms.alternarAtivo(r) } label: {
                                Image(systemName: r.ativo ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(r.ativo ? VigiaTheme.ok : VigiaTheme.border)
                            }.buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.nome).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                Text("\(r.alvo.descricao) ≥ \(r.limite) · \(r.escopo.descricao)")
                                    .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                            }
                            Spacer()
                            Circle().fill(cor(r.severidade)).frame(width: 8, height: 8)
                            Button { alarms.remover(r) } label: {
                                Image(systemName: "trash").foregroundColor(VigiaTheme.danger)
                            }.buttonStyle(.plain)
                        }
                        .padding(10).background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 16)
            }

            Divider().background(VigiaTheme.border).padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Nova regra").font(.system(size: 12, weight: .bold)).foregroundColor(VigiaTheme.accent)
                TextField("Nome da regra", text: $nome).textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Classe", selection: $alvo) {
                        ForEach(alvos, id: \.self) { Text($0.descricao).tag($0) }
                    }.frame(width: 130)
                    Stepper("≥ \(limite)", value: $limite, in: 1...50).font(.system(size: 11))
                }
                HStack {
                    Picker("Escopo", selection: $escopo) {
                        ForEach(escopos, id: \.self) { Text($0.descricao).tag($0) }
                    }
                    Picker("Sev.", selection: $severidade) {
                        ForEach(Severidade.allCases) { Text($0.label).tag($0) }
                    }.frame(width: 110)
                }
                Button {
                    let r = AlarmRule(nome: nome.isEmpty ? "\(alvo.descricao) ≥ \(limite)" : nome,
                                      alvo: alvo, limite: limite,
                                      escopo: escopo, severidade: severidade)
                    alarms.adicionar(r); nome = ""
                } label: {
                    Text("Adicionar regra").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
            }.padding(16)
        }
        .background(VigiaTheme.panel)
    }

    private func cor(_ s: Severidade) -> Color {
        switch s { case .info: return VigiaTheme.accent2; case .aviso: return VigiaTheme.warning; case .critico: return VigiaTheme.danger }
    }
    private func hora(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d) }
}
