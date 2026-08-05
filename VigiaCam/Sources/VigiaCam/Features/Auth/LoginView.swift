import SwiftUI

/// Tela de login — bloqueia o app até autenticar.
struct LoginView: View {
    @ObservedObject var auth = AuthService.shared
    @State private var nome = ""
    @State private var senha = ""
    @State private var erro = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("VIGIA").font(.system(size: 34, weight: .black, design: .rounded)).foregroundColor(.white)
                    Text(".").font(.system(size: 34, weight: .black, design: .rounded)).foregroundColor(VigiaTheme.accent)
                }
                Text("Central de Monitoramento").font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
            }
            VStack(spacing: 10) {
                TextField("Usuário", text: $nome)
                    .textFieldStyle(.plain).padding(10)
                    .background(VigiaTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VigiaTheme.border, lineWidth: 1))
                SecureField("Senha", text: $senha)
                    .textFieldStyle(.plain).padding(10)
                    .background(VigiaTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VigiaTheme.border, lineWidth: 1))
                    .onSubmit(entrar)
                if erro {
                    Text("Usuário ou senha inválidos")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(VigiaTheme.danger)
                }
                Button(action: entrar) {
                    Text("Entrar").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            .frame(width: 280)
            if auth.precisaTrocarSenhaPadrao {
                Label("Primeiro acesso: usuário admin, senha admin — troque a senha em Configurações › Usuários.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.warning)
                    .frame(width: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VigiaTheme.bg)
    }

    private func entrar() {
        erro = !auth.login(nome: nome, senha: senha)
        if !erro { senha = "" }
    }
}
