import SwiftUI
import MapKit

/// Mapa de câmeras: pin colorido pelo estado real do stream (verde online,
/// vermelho inalcançável, cinza sem sinal). Câmeras sem coordenada aparecem
/// numa lista lateral e podem ser posicionadas no centro do mapa atual.
struct CameraMapView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject private var health = CameraHealthRegistry.shared

    @State private var cameras: [Camera] = []
    @State private var posicao: MapCameraPosition = .region(MKCoordinateRegion(
        // Centro inicial: Brasil (ajusta sozinho quando há câmeras posicionadas)
        center: CLLocationCoordinate2D(latitude: -14.2, longitude: -51.9),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)))
    @State private var centroAtual = CLLocationCoordinate2D(latitude: -14.2, longitude: -51.9)

    private var comCoordenada: [Camera] {
        cameras.filter { $0.latitude != nil && $0.longitude != nil }
    }
    private var semCoordenada: [Camera] {
        cameras.filter { $0.latitude == nil || $0.longitude == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            Map(position: $posicao) {
                ForEach(comCoordenada) { cam in
                    Annotation(cam.nome, coordinate: CLLocationCoordinate2D(
                        latitude: cam.latitude!, longitude: cam.longitude!)) {
                        ZStack {
                            Circle().fill(cor(cam)).frame(width: 16, height: 16)
                            Image(systemName: "video.fill").font(.system(size: 7)).foregroundColor(.black)
                        }
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .contextMenu {
                            Button("Remover do mapa") { definirCoordenada(cam, coord: nil) }
                        }
                    }
                }
            }
            .onMapCameraChange { ctx in centroAtual = ctx.region.center }

            painelLateral
        }
        .background(VigiaTheme.bg)
        .onAppear(perform: recarregar)
        .onChange(of: storage.camerasVersao) { recarregar() }
    }

    private var painelLateral: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAPA DE CÂMERAS").font(.system(size: 11, weight: .black)).foregroundColor(VigiaTheme.muted)
                .padding(.top, 12)
            HStack(spacing: 12) {
                legenda(VigiaTheme.ok, "Online")
                legenda(VigiaTheme.danger, "Inalcançável")
                legenda(VigiaTheme.muted, "Sem sinal")
            }
            Divider().background(VigiaTheme.border)
            if semCoordenada.isEmpty {
                Text("Todas as câmeras posicionadas.")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            } else {
                Text("Sem posição (\(semCoordenada.count)) — centralize o mapa no local e clique em fixar:")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                List(semCoordenada) { cam in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cam.nome).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                            Text(cam.categoria).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                        }
                        Spacer()
                        Button(action: { definirCoordenada(cam, coord: centroAtual) }) {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                        }.buttonStyle(.bordered).controlSize(.small).tint(VigiaTheme.accent)
                            .help("Fixar no centro do mapa")
                    }
                    .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 240)
        .background(VigiaTheme.panel)
    }

    private func legenda(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
        }
    }

    private func cor(_ cam: Camera) -> Color {
        if health.online.contains(cam.id) { return VigiaTheme.ok }
        if health.inalcancaveis.contains(cam.id) { return VigiaTheme.danger }
        return VigiaTheme.muted
    }

    private func definirCoordenada(_ cam: Camera, coord: CLLocationCoordinate2D?) {
        guard let i = cameras.firstIndex(where: { $0.id == cam.id }) else { return }
        cameras[i].latitude = coord?.latitude
        cameras[i].longitude = coord?.longitude
        storage.salvarCameras(cameras)
    }

    private func recarregar() {
        cameras = storage.carregarCameras()
        // Enquadra as câmeras já posicionadas.
        let coords = comCoordenada.compactMap { c in
            c.latitude.flatMap { la in c.longitude.map { lo in CLLocationCoordinate2D(latitude: la, longitude: lo) } }
        }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let centro = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.05, (lats.max()! - lats.min()!) * 1.4),
                                    longitudeDelta: max(0.05, (lons.max()! - lons.min()!) * 1.4))
        posicao = .region(MKCoordinateRegion(center: centro, span: span))
    }
}
