import SwiftUI
import AppKit

/// Relatórios e evidências: gera PDF de eventos por período e abre as pastas
/// de gravações/capturas/cadeia de custódia.
struct ReportsView: View {
    @ObservedObject var eventService: EventService
    let totalCameras: Int
    let usuario: String

    @State private var dias = 7
    @State private var gerando = false
    @State private var ultimoPDF: URL?

    private let storage = StorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Relatórios & Evidências").font(.system(size: 18, weight: .bold)).foregroundColor(.white)

                // Relatório PDF
                painel(titulo: "Relatório de eventos (PDF)", icon: "doc.richtext") {
                    HStack(spacing: 12) {
                        Stepper("Últimos \(dias) dia(s)", value: $dias, in: 1...90)
                            .foregroundColor(VigiaTheme.text)
                        Spacer()
                        Button {
                            gerarPDF()
                        } label: {
                            HStack { Image(systemName: "arrow.down.doc"); Text(gerando ? "Gerando…" : "Gerar PDF") }
                        }.buttonStyle(.borderedProminent).tint(VigiaTheme.accent).disabled(gerando)
                    }
                    if let pdf = ultimoPDF {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(VigiaTheme.ok)
                            Text(pdf.lastPathComponent).font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
                            Spacer()
                            Button("Abrir") { NSWorkspace.shared.open(pdf) }.buttonStyle(.plain).foregroundColor(VigiaTheme.accent2)
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([pdf]) }
                                .buttonStyle(.plain).foregroundColor(VigiaTheme.accent2)
                        }
                    }
                }

                // Atalhos p/ pastas de evidência
                painel(titulo: "Pastas de evidência", icon: "folder.fill") {
                    pastaLinha("Gravações (clipes)", storage.dirGravacoes, "film")
                    pastaLinha("Capturas (snapshots)", storage.dirCapturas, "photo")
                    pastaLinha("Cadeia de custódia", storage.arquivoCadeia.deletingLastPathComponent(), "shield.lefthalf.filled")
                    pastaLinha("Trilha de auditoria", storage.arquivoAuditoria.deletingLastPathComponent(), "list.bullet.rectangle")
                }

                Text("Todos os arquivos ficam em ~/Documents/VigiaCam. Gravações e snapshots são registrados com hash SHA-256 na cadeia de custódia para validade probatória.")
                    .font(.system(size: 11)).foregroundColor(VigiaTheme.muted)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VigiaTheme.bg)
        .onAppear { eventService.carregarEventos(dias: dias) }
    }

    private func gerarPDF() {
        gerando = true
        eventService.carregarEventos(dias: dias)
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        let ini = Calendar.current.date(byAdding: .day, value: -(dias - 1), to: Date()) ?? Date()
        let periodo = "\(f.string(from: ini)) a \(f.string(from: Date()))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ultimoPDF = ReportService.gerarPDF(eventos: eventService.eventos, periodo: periodo,
                                               usuario: usuario, cameras: totalCameras)
            gerando = false
        }
    }

    private func pastaLinha(_ titulo: String, _ url: URL, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(VigiaTheme.accent2).frame(width: 20)
            Text(titulo).font(.system(size: 12, weight: .medium)).foregroundColor(VigiaTheme.text)
            Spacer()
            Button("Abrir pasta") { NSWorkspace.shared.open(url) }
                .buttonStyle(.plain).foregroundColor(VigiaTheme.accent)
        }
    }

    private func painel<Content: View>(titulo: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(VigiaTheme.accent)
                Text(titulo).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VigiaTheme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VigiaTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
