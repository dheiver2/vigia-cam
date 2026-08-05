import SwiftUI

/// Gestão de usuários/operadores (aba de Configurações, só admin).
struct UsersAdminView: View {
    @ObservedObject var auth = AuthService.shared
    @State private var novoNome = ""
    @State private var novaSenha = ""
    @State private var novoPapel: Papel = .operador
    @State private var trocandoSenhaDe: Usuario?
    @State private var senhaNova = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Novo usuário", text: $novoNome).textFieldStyle(.roundedBorder).frame(width: 140)
                SecureField("Senha", text: $novaSenha).textFieldStyle(.roundedBorder).frame(width: 120)
                Picker("", selection: $novoPapel) {
                    ForEach(Papel.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.menu).frame(width: 140)
                Button("Criar") {
                    if auth.criar(nome: novoNome, senha: novaSenha, papel: novoPapel) {
                        novoNome = ""; novaSenha = ""
                    }
                }.buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
                    .disabled(novoNome.trimmingCharacters(in: .whitespaces).isEmpty || novaSenha.isEmpty)
                Spacer()
            }.padding(.horizontal, 16)

            List(auth.usuarios) { u in
                HStack {
                    Image(systemName: u.papel == .admin ? "person.badge.shield.checkmark.fill" : "person.fill")
                        .foregroundColor(u.papel == .admin ? VigiaTheme.accent : VigiaTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.nome).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        Text("\(u.papel.label) • criado \(dataCurta(u.criadoEm))" +
                             (u.ultimoAcesso.map { " • último acesso \(dataCurta($0))" } ?? " • nunca acessou"))
                            .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                    }
                    Spacer()
                    Button("Trocar senha") { trocandoSenhaDe = u; senhaNova = "" }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(action: { auth.remover(u) }) {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundColor(VigiaTheme.danger)
                    }.buttonStyle(.plain)
                        .disabled(u.id == auth.logado?.id)
                }
                .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .sheet(item: $trocandoSenhaDe) { u in
            VStack(spacing: 12) {
                Text("Nova senha para \(u.nome)").font(.headline)
                SecureField("Nova senha", text: $senhaNova).textFieldStyle(.roundedBorder).frame(width: 220)
                HStack {
                    Button("Cancelar") { trocandoSenhaDe = nil }
                    Button("Salvar") {
                        _ = auth.trocarSenha(u, nova: senhaNova)
                        trocandoSenhaDe = nil
                    }.buttonStyle(.borderedProminent).disabled(senhaNova.isEmpty)
                }
            }.padding(24)
        }
    }

    private func dataCurta(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: d)
    }
}

/// Trilha de auditoria (leitura do JSONL já existente) — antes era gravada e
/// nunca exibida em lugar nenhum.
struct AuditLogView: View {
    @State private var linhas: [[String: Any]] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(linhas.count) registros").font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted)
                Spacer()
                Button(action: carregar) { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
            }.padding(12)
            List(Array(linhas.enumerated()), id: \.offset) { _, reg in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reg["acao"] as? String ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        let det = reg["detalhe"] as? String ?? ""
                        if !det.isEmpty {
                            Text(det).font(.system(size: 10)).foregroundColor(VigiaTheme.muted).lineLimit(2)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(reg["usuario"] as? String ?? "").font(.system(size: 11, weight: .bold)).foregroundColor(VigiaTheme.accent2)
                        Text(reg["quando"] as? String ?? "").font(.system(size: 10, design: .monospaced)).foregroundColor(VigiaTheme.muted)
                    }
                }
                .listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .onAppear(perform: carregar)
    }

    private func carregar() {
        linhas = StorageService.shared.lerAuditoria(maxLinhas: 500).reversed()
    }
}
