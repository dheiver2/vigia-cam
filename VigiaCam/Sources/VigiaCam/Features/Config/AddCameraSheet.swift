import SwiftUI

/// Diálogo "Nova Câmera".
///
/// É uma View própria de propósito: o conteúdo de um `.sheet` é apresentado em
/// outra janela, e um `@FocusState` declarado na view PAI (a `ConfigView`) não
/// alcança os campos aqui dentro — clicar no campo de URL não dava foco e tudo
/// que era digitado continuava caindo no campo "Nome". Com o `@FocusState`
/// morando junto dos `TextField`s, o foco por clique funciona.
struct AddCameraSheet: View {
    /// Ids (= URLs) das câmeras já cadastradas, para barrar duplicata.
    let existentes: [String]
    let onCancel: () -> Void
    let onAdd: (Camera) -> Void

    private enum Campo: Hashable { case nome, url, categoria }

    @State private var nome = ""
    @State private var url = ""
    @State private var categoria = "Outras"
    @FocusState private var focado: Campo?

    private var urlLimpa: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicada: Bool { existentes.contains(urlLimpa) }

    /// Só aceita o que o player sabe abrir. Sem isso dava para cadastrar
    /// qualquer texto: a câmera entrava na lista e ficava eternamente
    /// "Reconectando…", sem nenhuma pista do motivo.
    private var esquemaValido: Bool { Camera.urlSuportada(urlLimpa) }

    private var podeAdicionar: Bool { !urlLimpa.isEmpty && !duplicada && esquemaValido }

    private var aviso: String? {
        if duplicada { return "Essa URL já está cadastrada." }
        if !urlLimpa.isEmpty && !esquemaValido { return "URL inválida — use rtsp://, http:// ou https://" }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Nova Câmera").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            campo("Nome", text: $nome, id: .nome)
            campo("URL (rtsp:// ou https://...)", text: $url, id: .url)
            campo("Categoria", text: $categoria, id: .categoria)
            if let aviso {
                Text(aviso)
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancelar", action: onCancel).buttonStyle(.plain).padding(.vertical, 10)
                Button(action: adicionar) {
                    Text("Adicionar").font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(podeAdicionar ? 1 : 0.4)
                }.buttonStyle(.plain).disabled(!podeAdicionar)
            }
        }
        .padding(24).frame(width: 400).background(VigiaTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VigiaTheme.border, lineWidth: 1))
        .padding(40)
        .onAppear { focado = .nome }
    }

    /// A caixa inteira (não só a faixa do texto) dá foco ao ser clicada: o
    /// `TextField` sozinho só é clicável na altura da linha de texto, e o
    /// `padding` que desenha a caixa fica fora do hit-test dele.
    @ViewBuilder
    private func campo(_ titulo: String, text: Binding<String>, id: Campo) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(VigiaTheme.card)
            TextField(titulo, text: text)
                .textFieldStyle(.plain)
                .focused($focado, equals: id)
                .padding(.horizontal, 12)
        }
        .frame(height: 42)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { focado = id }
    }

    private func adicionar() {
        guard podeAdicionar else { return }
        // `Camera.init?` já valida a URL e aplica os defaults de nome/categoria;
        // o tipo sai do esquema, não de um palpite sobre o texto.
        guard let nova = Camera(nome: nome, categoria: categoria, url: urlLimpa) else { return }
        onAdd(nova)
        nome = ""; url = ""; categoria = Camera.categoriaPadrao
    }
}
