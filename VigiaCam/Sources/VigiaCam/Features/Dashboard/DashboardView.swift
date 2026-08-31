import SwiftUI

struct DashboardView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var eventService: EventService
    @State private var totalCameras = 0
    @State private var totalEventos = 0
    @State private var ocorrenciasPorTipo: [(String, Int)] = []
    @State private var historicoStatus: [EventStore.TransicaoStatus] = []
    @ObservedObject private var saude = CameraHealthRegistry.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    KPICardView(title: "Câmeras", value: "\(totalCameras)", icon: "video", color: VigiaTheme.accent)
                    KPICardView(title: "Online", value: "\(saude.online.count)", icon: "wifi",
                                color: saude.online.isEmpty ? VigiaTheme.danger : VigiaTheme.ok)
                    // O dado de indisponíveis já existia no registro e nenhuma
                    // tela mostrava; o grid de 2 colunas ainda deixava o
                    // terceiro card sozinho na linha de baixo.
                    KPICardView(title: "Indisponíveis", value: "\(max(0, totalCameras - saude.online.count))",
                                icon: "wifi.slash",
                                color: totalCameras > saude.online.count ? VigiaTheme.warning : VigiaTheme.muted)
                    KPICardView(title: "Eventos Hoje", value: "\(totalEventos)", icon: "bolt.fill", color: VigiaTheme.accent2)
                }.padding(16)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Eventos Recentes").font(.system(size: 16, weight: .bold)).foregroundColor(.white).padding(.horizontal, 16)
                    if eventService.eventos.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bolt.slash").font(.system(size: 32)).foregroundColor(VigiaTheme.border)
                            Text("Nenhum evento registrado").font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                        }.frame(maxWidth: .infinity).padding(32)
                    } else {
                        ForEach(eventService.eventos.prefix(10)) { evento in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evento.tipo).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                    Text(evento.camera).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                                }
                                Spacer()
                                Text(evento.hora).font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted)
                            }.padding(.horizontal, 16).padding(.vertical, 8)
                            .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.padding(.horizontal, 16)

                // Painel de métricas: contadores de ocorrências por tipo (7 dias)
                if !ocorrenciasPorTipo.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ocorrências por Tipo (7 dias)").font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white).padding(.horizontal, 16)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(ocorrenciasPorTipo, id: \.0) { (tipo, qtd) in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(qtd)").font(.system(size: 22, weight: .black, design: .monospaced))
                                        // "critico" é severidade, não tipo: a
                                        // condição antiga nunca era verdadeira.
                                        .foregroundColor(tipo.uppercased().hasPrefix("ALARME") ? VigiaTheme.danger : VigiaTheme.accent)
                                    Text(tipo).font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(VigiaTheme.muted).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(VigiaTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }.padding(.horizontal, 16)
                    }
                }

                // Log de status das câmeras (transições online/offline)
                if !historicoStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status das Câmeras (histórico)").font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white).padding(.horizontal, 16)
                        ForEach(historicoStatus.prefix(12)) { t in
                            HStack {
                                Circle().fill(t.online ? VigiaTheme.ok : VigiaTheme.danger)
                                    .frame(width: 8, height: 8)
                                Text(t.camera).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                Text(t.online ? "ficou online" : "ficou offline")
                                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                                Spacer()
                                Text(Self.horaFmt.string(from: t.quando))
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted)
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                            .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { carregarDados() }
        .onChange(of: storage.camerasVersao) { carregarDados() }
        // Sem isto os painéis congelavam enquanto a aba ficava aberta, mesmo
        // com o app gravando eventos o tempo todo.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { break }
                carregarDados()
            }
        }
    }

    private static let horaFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"; return f
    }()

    private func carregarDados() {
        totalCameras = storage.carregarCameras().count
        // Era `eventService.eventos.count` lido ANTES do carregamento
        // assíncrono: na primeira abertura mostrava 0 e depois sempre o total
        // da visita anterior, contradizendo a lista logo abaixo. Agora conta no
        // SQLite, a mesma fonte da aba Eventos, e "hoje" é desde a meia-noite.
        let inicioDoDia = Calendar.current.startOfDay(for: Date())
        totalEventos = EventStore.shared.contarDesde(inicioDoDia)
        eventService.carregarEventos(dias: 1)
        ocorrenciasPorTipo = EventStore.shared.contagemPorTipo(dias: 7)
        historicoStatus = EventStore.shared.historicoStatus(dias: 7, limite: 50)
    }
}
