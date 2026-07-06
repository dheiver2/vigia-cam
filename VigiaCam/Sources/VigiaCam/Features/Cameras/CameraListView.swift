import SwiftUI

struct CameraListView: View {
    @ObservedObject var storage: StorageService
    @State private var cameras: [Camera] = []
    @State private var selectedCategory = "Todas"
    @State private var searchText = ""

    var filteredCameras: [Camera] {
        cameras.filter { c in
            (selectedCategory == "Todas" || c.categoria == selectedCategory) &&
            (searchText.isEmpty || c.nome.localizedCaseInsensitiveContains(searchText))
        }
    }
    var categories: [String] { ["Todas"] + Set(cameras.map { $0.categoria }).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Buscar câmeras...", text: $searchText).textFieldStyle(.plain)
                    .padding(8).background(VigiaTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(VigiaTheme.border, lineWidth: 1))
                ForEach(categories, id: \.self) { cat in
                    Button(action: { selectedCategory = cat }) {
                        Text(cat).font(.system(size: 11, weight: .semibold))
                            .foregroundColor(selectedCategory == cat ? .black : VigiaTheme.text)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selectedCategory == cat ? AnyView(VigiaTheme.accentGradient) : AnyView(VigiaTheme.card))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(12)
            if filteredCameras.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "video.slash").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                    Text("Nenhuma câmera encontrada").font(.system(size: 14, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                    Text("Adicione câmeras na aba Configurações").font(.system(size: 12)).foregroundColor(VigiaTheme.border)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(filteredCameras) { camera in CameraCardView(camera: camera) }
                    }.padding(16)
                }
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { cameras = storage.carregarCameras() }
    }
}
