import SwiftUI

/// Aba Placas: leituras ao vivo, busca histórica e gestão da lista de interesse.
struct LPRView: View {
    @ObservedObject private var lpr = LPRService.shared
    var podeGerenciar = true

    @State private var modo = 0            // 0 = ao vivo, 1 = busca, 2 = interesse
    @State private var busca = ""
    @State private var dias = 7
    @State private var resultados: [EventStore.Placa] = []
    @State private var interesse: [(String, String)] = []
    @State private var novaPlaca = ""
    @State private var novaDescricao = ""
    /// Placas de interesse em memória: `linhaPlaca` consultava o SQLite (com
    /// `fila.sync`) uma vez por linha a cada redraw — até 500 queries síncronas
    /// na main thread por frame de UI, travando a lista.
    @State private var interesseSet: Set<String> = []
    @State private var avisoPlaca: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $modo) {
                    Text("Ao vivo").tag(0); Text("Busca").tag(1); Text("Placas de interesse").tag(2)
                }.pickerStyle(.segmented).frame(width: 340)
                Spacer()
                Toggle("LPR ativo", isOn: $lpr.ativo).toggleStyle(.switch).tint(VigiaTheme.accent)
                    .disabled(!podeGerenciar)
            }.padding(12)

            switch modo {
            case 0: aoVivo
            case 1: buscaView
            default: interesseView
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { recarregarInteresse() }
    }

    private var aoVivo: some View {
        Group {
            if lpr.recentes.isEmpty {
                vazio("Nenhuma placa lida nesta sessão",
                      "As leituras aparecem aqui conforme veículos passam pelas câmeras.")
            } else {
                List(lpr.recentes) { linhaPlaca($0) }
                    .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    private var buscaView: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Placa (parcial vale: ABC...)", text: $busca)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                    .onSubmit(buscar)
                Picker("", selection: $dias) {
                    Text("7 dias").tag(7); Text("30 dias").tag(30); Text("90 dias").tag(90)
                }.pickerStyle(.menu).frame(width: 100)
                Button("Buscar", action: buscar).buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
                Spacer()
                Text("\(resultados.count) leituras").font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VigiaTheme.muted)
            }.padding(.horizontal, 12).padding(.bottom, 8)
            if resultados.isEmpty {
                vazio("Sem resultados", "Busque por placa completa ou parcial.")
            } else {
                List(resultados) { linhaPlaca($0) }
                    .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    private var interesseView: some View {
        VStack(spacing: 8) {
            if podeGerenciar {
                HStack {
                    TextField("Placa (ABC1D23)", text: $novaPlaca).textFieldStyle(.roundedBorder).frame(width: 140)
                    TextField("Descrição (ex.: veículo furtado)", text: $novaDescricao).textFieldStyle(.roundedBorder)
                    Button("Adicionar") {
                        let p = novaPlaca.uppercased().replacingOccurrences(of: "-", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        // Antes: `guard p.count == 7 else { return }` — placa
                        // curta ou fora do padrão sumia sem nenhuma mensagem, e
                        // "1234567" era aceito como se fosse placa.
                        guard Self.placaValida(p) else {
                            avisoPlaca = "Placa inválida. Use o formato ABC1D23 (Mercosul) ou ABC1234."
                            return
                        }
                        avisoPlaca = nil
                        EventStore.shared.adicionarInteresse(p, descricao: novaDescricao)
                        novaPlaca = ""; novaDescricao = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            recarregarInteresse()
                        }
                    }.buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
                }.padding(.horizontal, 12)
            }
            if let avisoPlaca {
                Text(avisoPlaca).font(.system(size: 11)).foregroundColor(VigiaTheme.danger)
                    .padding(.horizontal, 12)
            }
            if interesse.isEmpty {
                vazio("Lista de interesse vazia",
                      "Placas aqui geram alarme crítico assim que forem lidas.")
            } else {
                List(interesse, id: \.0) { (placa, desc) in
                    HStack {
                        Text(placa).font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(VigiaTheme.danger)
                        Text(desc).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                        Spacer()
                        if podeGerenciar {
                            Button(action: {
                                EventStore.shared.removerInteresse(placa)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    recarregarInteresse()
                                }
                            }) {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundColor(VigiaTheme.danger)
                            }.buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    /// Mesmo formato aceito pelo motor de leitura (Mercosul ou antiga).
    static func placaValida(_ p: String) -> Bool {
        p.range(of: "^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$", options: .regularExpression) != nil
    }

    private func recarregarInteresse() {
        interesse = EventStore.shared.listarInteresse()
        interesseSet = Set(interesse.map(\.0))
    }

    private func linhaPlaca(_ p: EventStore.Placa) -> some View {
        HStack {
            Text(p.placa).font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(interesseSet.contains(p.placa) ? VigiaTheme.danger : .white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(VigiaTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(VigiaTheme.border, lineWidth: 1))
            Text(p.camera).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            Spacer()
            Text(quando(p.quando)).font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted)
        }
        .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
    }

    private func vazio(_ titulo: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "text.rectangle.page").font(.system(size: 42)).foregroundColor(VigiaTheme.border)
            Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundColor(VigiaTheme.muted)
            Text(sub).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buscar() {
        resultados = EventStore.shared.buscarPlacas(texto: busca.uppercased(), dias: dias)
    }

    private func quando(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"; return f.string(from: d)
    }
}
