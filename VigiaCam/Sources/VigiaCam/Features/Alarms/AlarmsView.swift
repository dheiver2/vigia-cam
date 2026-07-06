import SwiftUI

/// Painel de alarmes: ocorrências ao vivo + gestão das regras (analíticos).
struct AlarmsView: View {
    @ObservedObject private var alarms = AlarmService.shared
    let categorias: [String]

    @State private var nome = ""
    @State private var classe = "person"
    @State private var limite = 5
    @State private var escopo = "Todas"
    @State private var severidade: Severidade = .aviso

    private let classes = ["person", "car", "truck", "bus", "motorcycle", "bicycle", "qualquer"]

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
            }.padding(16)

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
                                Text("\(r.classe) ≥ \(r.limite) · \(r.escopo ?? "Todas")")
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
                    Picker("Classe", selection: $classe) { ForEach(classes, id: \.self) { Text($0) } }.frame(width: 130)
                    Stepper("≥ \(limite)", value: $limite, in: 1...50).font(.system(size: 11))
                }
                HStack {
                    Picker("Câmera", selection: $escopo) {
                        ForEach(["Todas"] + categorias, id: \.self) { Text($0) }
                    }
                    Picker("Sev.", selection: $severidade) {
                        ForEach(Severidade.allCases) { Text($0.label).tag($0) }
                    }.frame(width: 110)
                }
                Button {
                    let r = AlarmRule(nome: nome.isEmpty ? "\(classe) ≥ \(limite)" : nome,
                                      classe: classe, limite: limite,
                                      escopo: escopo == "Todas" ? nil : escopo, severidade: severidade)
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
