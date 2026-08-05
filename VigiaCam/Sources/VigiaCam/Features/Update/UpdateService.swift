import Foundation
import Combine
import AppKit
import SwiftUI

/// Auto-update via GitHub Releases: verifica a última versão publicada,
/// baixa o VigiaCam-macOS.zip, troca o próprio .app no disco e reabre.
///
/// Sem dependências (nada de Sparkle): o repositório é público e o release
/// carrega o zip do bundle. A troca só acontece quando o processo roda de um
/// bundle de verdade (Bundle.main com .app); em `swift run` o serviço só avisa.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum Estado: Equatable {
        case ocioso
        case verificando
        case disponivel(versao: String)
        case baixando
        case instalando
        case atualizado                 // instalou; reabrindo
        case emDia
        case falha(String)
    }

    @Published var estado: Estado = .ocioso

    private let repo = "dheiver2/vigia-cam"
    private let nomeAsset = "VigiaCam-macOS.zip"
    private var urlAsset: URL?

    private init() {}

    /// Versão do binário em execução (Info.plist do bundle; "0" em swift run).
    var versaoAtual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Verificação

    func verificar(silencioso: Bool = true) {
        if case .verificando = estado { return }
        estado = .verificando
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            DispatchQueue.main.async {
                guard err == nil, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = obj["tag_name"] as? String else {
                    self.estado = silencioso ? .ocioso : .falha("não foi possível consultar o GitHub")
                    return
                }
                let remota = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = obj["assets"] as? [[String: Any]] ?? []
                let asset = assets.first { ($0["name"] as? String) == self.nomeAsset }
                self.urlAsset = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))

                if Self.ehMaisNova(remota, que: self.versaoAtual), self.urlAsset != nil {
                    self.estado = .disponivel(versao: remota)
                } else {
                    self.estado = silencioso ? .ocioso : .emDia
                }
            }
        }.resume()
    }

    /// Comparação semver simples (2.10.0 > 2.9.1; ignora sufixos).
    static func ehMaisNova(_ a: String, que b: String) -> Bool {
        func partes(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let pa = partes(a), pb = partes(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Instalação

    func baixarEInstalar() {
        guard case .disponivel = estado, let urlAsset else { return }

        // Onde este processo mora. Se não for um .app instalado (ex.: swift
        // run), não há o que trocar — abre a página de download e pronto.
        let destino = Bundle.main.bundleURL
        guard destino.pathExtension == "app" else {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(repo)/releases/latest")!)
            return
        }

        estado = .baixando
        URLSession.shared.downloadTask(with: urlAsset) { [weak self] tmpZip, _, err in
            guard let self else { return }
            guard err == nil, let tmpZip else {
                DispatchQueue.main.async { self.estado = .falha("download falhou") }
                return
            }
            DispatchQueue.main.async { self.estado = .instalando }
            do {
                try self.instalar(zip: tmpZip, sobre: destino)
                DispatchQueue.main.async {
                    self.estado = .atualizado
                    StorageService.shared.auditar("auto_update",
                        detalhe: "de=\(self.versaoAtual)")
                    self.reabrir(destino)
                }
            } catch {
                DispatchQueue.main.async { self.estado = .falha(error.localizedDescription) }
            }
        }.resume()
    }

    private struct ErroUpdate: LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    /// Extrai o zip, valida o bundle novo e faz a troca atômica possível:
    /// o .app antigo vira backup ao lado (removido só no fim).
    private func instalar(zip: URL, sobre destino: URL) throws {
        let fm = FileManager.default
        let raiz = fm.temporaryDirectory.appendingPathComponent("vigia-update-\(UUID().uuidString)")
        try fm.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: raiz) }

        // ditto preserva estrutura/permissões/assinatura do bundle.
        try rodar("/usr/bin/ditto", ["-xk", zip.path, raiz.path])

        guard let novo = try fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }),
              fm.fileExists(atPath: novo.appendingPathComponent("Contents/MacOS/VigiaCam").path) else {
            throw ErroUpdate(msg: "zip sem VigiaCam.app válido")
        }

        // Remove a quarentena ANTES de mover pro lugar — baixado pela rede, o
        // bundle chega quarentenado e o Gatekeeper travaria a reabertura
        // (assinatura é ad-hoc).
        try? rodar("/usr/bin/xattr", ["-dr", "com.apple.quarantine", novo.path])

        let backup = destino.deletingLastPathComponent()
            .appendingPathComponent(".VigiaCam-anterior.app")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: destino, to: backup)
        do {
            // moveItem falha entre volumes (tmp pode ser outro volume) — nesse
            // caso copia com ditto, que é o caminho seguro para bundles.
            do { try fm.moveItem(at: novo, to: destino) }
            catch { try rodar("/usr/bin/ditto", [novo.path, destino.path]) }
        } catch {
            try? fm.moveItem(at: backup, to: destino)   // desfaz: volta o antigo
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// Reabre o app novo depois que este processo morrer.
    private func reabrir(_ destino: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(destino.path)\""]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    fileprivate func rodar(_ caminho: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: caminho)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ErroUpdate(msg: "\((caminho as NSString).lastPathComponent) saiu com código \(p.terminationStatus)")
        }
    }
}

/// Linha de status/ação de update usada em Configurações › Alarmes.
struct UpdateStatusRow: View {
    @ObservedObject private var svc = UpdateService.shared

    var body: some View {
        HStack {
            Button("Verificar agora") { svc.verificar(silencioso: false) }
                .buttonStyle(.bordered).tint(VigiaTheme.accent)
            switch svc.estado {
            case .emDia:
                Text("Você está na versão mais recente.")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.ok)
            case .verificando:
                Text("Consultando GitHub…")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            case .disponivel(let v):
                Button("Atualizar para \(v) e reabrir") { svc.baixarEInstalar() }
                    .buttonStyle(.borderedProminent).tint(VigiaTheme.accent)
            case .baixando:
                Text("Baixando…").font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            case .instalando:
                Text("Instalando…").font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            case .atualizado:
                Text("Atualizado — reabrindo…").font(.system(size: 11)).foregroundColor(VigiaTheme.ok)
            case .falha(let m):
                Text(m).font(.system(size: 11)).foregroundColor(VigiaTheme.danger)
            case .ocioso:
                EmptyView()
            }
            Spacer()
        }
    }
}
