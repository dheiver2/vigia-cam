import SwiftUI

/// Bloqueia o app enquanto o admin estiver com a senha padrão.
///
/// `AuthService.precisaTrocarSenhaPadrao` já existia, mas nada forçava a troca:
/// a tela de login apenas avisava — e ainda exibia a credencial padrão para
/// qualquer pessoa em frente ao monitor.
struct TrocaSenhaObrigatoriaView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var nova = ""
    @State private var confirmacao = ""
    @State private var erro: String?

    /// Mesmo critério do cadastro de usuários.
    static func senhaAceitavel(_ s: String) -> Bool { s.count >= 8 }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.rotation").font(.system(size: 40)).foregroundColor(VigiaTheme.accent)
            Text("Defina uma senha para o administrador")
                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text("Este sistema ainda está com a senha padrão. Troque-a para continuar — qualquer pessoa com acesso à rede conhece a combinação de fábrica.")
                .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)

            SecureField("Nova senha (mínimo 8 caracteres)", text: $nova)
                .textFieldStyle(.roundedBorder).frame(width: 320)
            SecureField("Repita a nova senha", text: $confirmacao)
                .textFieldStyle(.roundedBorder).frame(width: 320)

            if let erro {
                Text(erro).font(.system(size: 11)).foregroundColor(VigiaTheme.danger)
            }

            Button(action: trocar) {
                Text("Salvar e continuar").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    .frame(width: 320).padding(.vertical, 10)
                    .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)

            Button("Sair") { auth.logout() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VigiaTheme.bg)
    }

    private func trocar() {
        guard Self.senhaAceitavel(nova) else {
            erro = "A senha precisa ter ao menos 8 caracteres."; return
        }
        guard nova == confirmacao else { erro = "As senhas não conferem."; return }
        guard nova != "admin" else { erro = "Escolha uma senha diferente da padrão."; return }
        guard let admin = auth.usuarios.first(where: { $0.nome == "admin" }),
              auth.trocarSenha(admin, nova: nova) else {
            erro = "Não foi possível salvar a nova senha."; return
        }
        erro = nil
    }
}
