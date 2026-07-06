import SwiftUI

struct EventListView: View {
    @ObservedObject var eventService: EventService
    @State private var searchText = ""
    @State private var dias: Int = 1

    var filteredEvents: [EventService.Evento] {
        if searchText.isEmpty { return eventService.eventos }
        return eventService.eventos.filter {
            $0.camera.localizedCaseInsensitiveContains(searchText) ||
            $0.tipo.localizedCaseInsensitiveContains(searchText) ||
            $0.detalhe.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(VigiaTheme.muted)
                    TextField("Buscar eventos...", text: $searchText).textFieldStyle(.plain)
                }.padding(8).background(VigiaTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(VigiaTheme.border, lineWidth: 1))
                Picker("Dias", selection: $dias) { Text("1 dia").tag(1); Text("7 dias").tag(7); Text("30 dias").tag(30) }
                    .pickerStyle(.menu).frame(width: 80)
                Button(action: { _ = eventService.exportarCSV() }) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                }.buttonStyle(.bordered).tint(VigiaTheme.accent)
            }.padding(12)
            if filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                    Text("Nenhum evento encontrado").font(.system(size: 14, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEvents) { evento in
                    HStack {
                        Circle().fill(evento.tipo == "deteccao" ? VigiaTheme.accent2 : VigiaTheme.ok).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evento.tipo).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                            Text(evento.camera).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(evento.hora).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                            Text(evento.data).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                        }
                    }.listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { eventService.carregarEventos(dias: dias) }
    }
}
