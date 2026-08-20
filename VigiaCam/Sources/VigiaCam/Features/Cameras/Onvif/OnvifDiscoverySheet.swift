import SwiftUI

/// Diálogo "Descobrir câmeras ONVIF" — busca dispositivos na rede local via
/// WS-Discovery, pede credenciais do selecionado e resolve a URL RTSP + (se
/// existir) o serviço PTZ, devolvendo uma `Camera` já pronta para cadastro.
struct OnvifDiscoverySheet: View {
    let onCancel: () -> Void
    let onResolved: (Camera) -> Void

    @StateObject private var discovery = OnvifDiscoveryService()
    @State private var selecionado: OnvifDiscoveryService.Device?
    @State private var usuario = ""
    @State private var senha = ""
    @State private var resolvendo = false
    @State private var erro: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Descobrir Câmeras ONVIF").font(.system(size: 16, weight: .bold)).foregroundColor(.white)

            if discovery.buscando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Buscando na rede local…")
                }.font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
            } else if discovery.dispositivos.isEmpty {
                Text("Nenhum dispositivo ONVIF encontrado. A câmera e este Mac precisam estar na mesma rede/VLAN.")
                    .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(discovery.dispositivos) { device in
                        Button(action: { selecionar(device) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "video.fill").foregroundColor(VigiaTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.nome).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                    if let host = device.host {
                                        Text(host).font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted)
                                    }
                                }
                                Spacer()
                                if selecionado?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(VigiaTheme.ok)
                                }
                            }
                            .padding(10)
                            .background(selecionado?.id == device.id ? VigiaTheme.card : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 140)

            if let selecionado {
                VStack(spacing: 8) {
                    Text("Credenciais ONVIF de \(selecionado.nome)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Usuário", text: $usuario).textFieldStyle(.roundedBorder)
                    SecureField("Senha", text: $senha).textFieldStyle(.roundedBorder)
                    if let erro {
                        Text(erro).font(.system(size: 11)).foregroundColor(VigiaTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: resolver) {
                        HStack(spacing: 6) {
                            if resolvendo { ProgressView().controlSize(.small) }
                            Text(resolvendo ? "Conectando…" : "Usar esta câmera")
                        }.font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(podeResolver ? 1 : 0.4)
                    }.buttonStyle(.plain).disabled(!podeResolver)
                }
            }

            HStack {
                Button("Cancelar", action: onCancel).buttonStyle(.plain)
                Spacer()
                Button(discovery.buscando ? "Buscando…" : "Buscar novamente") { discovery.buscar() }
                    .buttonStyle(.plain).foregroundColor(VigiaTheme.accent)
                    .disabled(discovery.buscando)
            }.font(.system(size: 12, weight: .semibold))
        }
        .padding(24).frame(width: 420).background(VigiaTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VigiaTheme.border, lineWidth: 1))
        .padding(40)
        .onAppear { discovery.buscar() }
        .onDisappear { discovery.parar() }
    }

    private var podeResolver: Bool { !usuario.isEmpty && !senha.isEmpty && !resolvendo }

    private func selecionar(_ device: OnvifDiscoveryService.Device) {
        selecionado = device; usuario = ""; senha = ""; erro = nil
    }

    private func resolver() {
        guard let device = selecionado, let xAddr = device.primeiroXAddr else { return }
        resolvendo = true; erro = nil
        Task {
            do {
                let client = OnvifClient(deviceXAddr: xAddr, usuario: usuario, senha: senha)
                let r = try await client.resolverCameraCompleta()
                guard var camera = Camera(nome: device.nome, categoria: Camera.categoriaPadrao, url: r.rtsp.absoluteString) else {
                    falhar("A câmera devolveu uma URL de stream inválida.")
                    return
                }
                camera.onvifXAddr = xAddr.absoluteString
                camera.onvifPTZXAddr = r.ptzXAddr?.absoluteString
                camera.onvifProfileToken = r.perfilToken
                camera.onvifUsuario = usuario
                camera.onvifSenha = senha
                await MainActor.run {
                    resolvendo = false
                    onResolved(camera)
                }
            } catch {
                await falhar(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func falhar(_ mensagem: String) {
        resolvendo = false
        erro = mensagem
    }
}
