import SwiftUI

struct DashboardView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var eventService: EventService
    @State private var totalCameras = 0
    @State private var totalUsuarios = 0
    @State private var totalEventos = 0
    @State private var onlineCameras = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    KPICardView(title: "Câmeras", value: "\(totalCameras)", icon: "video", color: VigiaTheme.accent)
                    KPICardView(title: "Online", value: "\(onlineCameras)", icon: "wifi", color: VigiaTheme.ok)
                    KPICardView(title: "Eventos Hoje", value: "\(totalEventos)", icon: "bolt.fill", color: VigiaTheme.accent2)
                    KPICardView(title: "Usuários", value: "\(totalUsuarios)", icon: "person.2.fill", color: VigiaTheme.danger)
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
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { carregarDados() }
    }

    private func carregarDados() {
        totalCameras = storage.carregarCameras().count
        totalUsuarios = RBACService.shared.usuarios.count
        totalEventos = eventService.eventos.count
        onlineCameras = totalCameras
        eventService.carregarEventos(dias: 1)
    }
}
