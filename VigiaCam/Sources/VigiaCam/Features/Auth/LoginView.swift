#if canImport(UIKit)
import SwiftUI

struct LoginView: View {
    @ObservedObject var rbac: RBACService
    @State private var usuario = ""
    @State private var senha = ""
    @State private var erro = ""
    @State private var isLoading = false
    @Binding var isLoggedIn: Bool

    var body: some View {
        ZStack {
            VigiaTheme.bg.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("VIGIA").font(.system(size: 36, weight: .black, design: .rounded)).foregroundColor(.white)
                        Text(".").font(.system(size: 36, weight: .black, design: .rounded)).foregroundColor(VigiaTheme.accent)
                    }
                    .shadow(color: VigiaTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                    Text("MONITORAMENTO INTELIGENTE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(VigiaTheme.muted).tracking(2)
                }
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Usuário").font(.system(size: 12, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                        TextField("admin", text: $usuario).textFieldStyle(.plain).padding(12)
                            .background(VigiaTheme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VigiaTheme.border, lineWidth: 1))
                            .autocapitalization(.none).disableAutocorrection(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Senha").font(.system(size: 12, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                        SecureField("••••••", text: $senha).textFieldStyle(.plain).padding(12)
                            .background(VigiaTheme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VigiaTheme.border, lineWidth: 1))
                    }
                    if !erro.isEmpty {
                        Text(erro).font(.system(size: 12, weight: .semibold)).foregroundColor(VigiaTheme.danger)
                            .padding(8).background(VigiaTheme.dangerGlow).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Button(action: fazerLogin) {
                        if isLoading { ProgressView().tint(.black) }
                        else { Text("ENTRAR").font(.system(size: 15, weight: .black)).foregroundColor(.black) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(isLoading ? VigiaTheme.border : VigiaTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(isLoading || usuario.isEmpty || senha.isEmpty)
                }
                .padding(.horizontal, 32)
                Spacer(); Spacer()
                Text("v2.0.0 • iOS").font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            }
        }
    }

    private func fazerLogin() {
        isLoading = true; erro = ""
        DispatchQueue.global().async {
            let result = rbac.login(usuario: usuario, senha: senha)
            DispatchQueue.main.async {
                isLoading = false
                if result != nil { isLoggedIn = true } else { erro = "Credenciais inválidas" }
            }
        }
    }
}
#endif
