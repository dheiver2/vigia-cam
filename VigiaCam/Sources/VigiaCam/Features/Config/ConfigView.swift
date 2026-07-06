#if canImport(UIKit)
import SwiftUI

struct ConfigView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var rbac: RBACService
    @State private var config: AppConfig = .default
    @State private var cameras: [Camera] = []
    @State private var showingAddCamera = false
    @State private var newCameraNome = ""
    @State private var newCameraURL = ""
    @State private var newCameraCategoria = "Outras"
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) { Text("Detecção").tag(0); Text("Câmeras").tag(1); Text("Usuários").tag(2) }
                .pickerStyle(.segmented).padding(16)
            switch selectedTab {
            case 0: configTab
            case 1: camerasTab
            case 2: usersTab
            default: configTab
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { config = storage.carregarConfig(); cameras = storage.carregarCameras() }
    }

    private var configTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                configRow(title: "FPS Máximo", value: "\(config.fpsMax)") {
                    Stepper("", value: $config.fpsMax, in: 1...60).labelsHidden()
                }
                configRow(title: "Confiança Mínima", value: String(format: "%.0f%%", config.confianca * 100)) {
                    Slider(value: $config.confianca, in: 0.05...0.95, step: 0.05).tint(VigiaTheme.accent)
                }
                configRow(title: "Resolução Inferência", value: "\(config.imgsz)px") {
                    Stepper("", value: $config.imgsz, in: 96...1280, step: 32).labelsHidden()
                }
                configRow(title: "Retenção (dias)", value: "\(config.retencapDias)") {
                    Stepper("", value: $config.retencapDias, in: 1...365).labelsHidden()
                }
                Button(action: { storage.salvarConfig(config.validated()) }) {
                    Text("Salvar Configurações").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }.padding(16)
        }
    }

    private func configRow<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white); Spacer()
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(VigiaTheme.accent) }
            content()
        }.padding(12).background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var camerasTab: some View {
        VStack(spacing: 0) {
            Button(action: { showingAddCamera = true }) {
                Label("Adicionar Câmera", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            .sheet(isPresented: $showingAddCamera) { addCameraSheet }
            if cameras.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                    Text("Nenhuma câmera cadastrada").font(.system(size: 14, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List { ForEach(cameras) { camera in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.nome).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            Text(camera.url).font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted).lineLimit(1)
                        }
                        Spacer()
                        Text(camera.categoria).font(.system(size: 10, weight: .bold)).foregroundColor(VigiaTheme.accent2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(VigiaTheme.accent2Glow).clipShape(RoundedRectangle(cornerRadius: 4))
                        Button(action: { cameras.removeAll { $0.id == camera.id }; storage.salvarCameras(cameras) }) {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundColor(VigiaTheme.danger)
                        }
                    }.listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
                }}.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    private var addCameraSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Nome", text: $newCameraNome).textFieldStyle(.plain).padding(12)
                    .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("URL (rtsp:// ou https://...)", text: $newCameraURL).textFieldStyle(.plain)
                    .autocapitalization(.none).disableAutocorrection(true).padding(12)
                    .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("Categoria", text: $newCameraCategoria).textFieldStyle(.plain).padding(12)
                    .background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                Button(action: {
                    let tipo: Camera.CameraType = newCameraURL.contains("rtsp") ? .rtsp : .hls
                    cameras.append(Camera(nome: newCameraNome.isEmpty ? newCameraURL : newCameraNome, categoria: newCameraCategoria, tipo: tipo, url: newCameraURL))
                    storage.salvarCameras(cameras)
                    newCameraNome = ""; newCameraURL = ""; newCameraCategoria = "Outras"; showingAddCamera = false
                }) {
                    Text("Adicionar").font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }.padding(16).background(VigiaTheme.bg).navigationTitle("Nova Câmera").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var usersTab: some View {
        List { ForEach(rbac.usuarios) { user in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.usuario).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    Text(user.perfil.label).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                }
                Spacer()
                Text(user.perfil.rawValue.uppercased()).font(.system(size: 10, weight: .bold))
                    .foregroundColor(user.perfil == .admin ? VigiaTheme.danger : VigiaTheme.accent2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(user.perfil == .admin ? VigiaTheme.dangerGlow : VigiaTheme.accent2Glow)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }.listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
        }}.listStyle(.plain).scrollContentBackground(.hidden)
    }
}
#endif
