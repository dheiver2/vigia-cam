import Foundation
import Darwin

/// Descoberta de câmeras ONVIF na rede local via WS-Discovery (multicast UDP
/// 239.255.255.250:3702).
///
/// Usa socket BSD cru (não `Network.framework`): um `NWConnection` "conectado"
/// ao endereço multicast só recebe respostas vindas DAQUELE endereço, mas cada
/// câmera responde por unicast a partir do próprio IP — um socket UDP solto
/// (bind em porta efêmera, sem `connect`) é o jeito padrão de implementar o
/// padrão probe/probe-match do WS-Discovery.
final class OnvifDiscoveryService: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String            // EndpointReference (UUID do dispositivo)
        let xAddrs: [String]
        let scopes: [String]

        var host: String? { primeiroXAddr?.host }
        var primeiroXAddr: URL? { xAddrs.first.flatMap(URL.init) }

        /// Nome amigável, extraído do scope `onvif://www.onvif.org/name/...`
        /// quando o fabricante o preenche; senão cai pro IP.
        var nome: String {
            for s in scopes {
                if let range = s.range(of: "/name/") {
                    let bruto = String(s[range.upperBound...])
                        .removingPercentEncoding ?? String(s[range.upperBound...])
                    if !bruto.isEmpty { return bruto }
                }
            }
            return host ?? "Dispositivo ONVIF"
        }
    }

    @Published private(set) var dispositivos: [Device] = []
    @Published private(set) var buscando = false

    private var socketAtivo: Int32 = -1
    private let fila = DispatchQueue(label: "onvif.discovery")

    /// Envia o Probe e escuta respostas por `timeoutSegundos`. Chamável de
    /// novo a qualquer momento — reinicia a busca do zero.
    func buscar(timeoutSegundos: Double = 4.0) {
        parar()
        DispatchQueue.main.async {
            self.dispositivos = []
            self.buscando = true
        }
        fila.async { [weak self] in self?.executar(timeout: timeoutSegundos) }
    }

    func parar() {
        fila.sync {
            if socketAtivo >= 0 { close(socketAtivo); socketAtivo = -1 }
        }
    }

    private func executar(timeout: Double) {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { finalizar(); return }
        socketAtivo = sock

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // recv com timeout curto: sem isto o loop de leitura bloqueia para
        // sempre se nenhuma câmera responder mais nada.
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = INADDR_ANY
        local.sin_port = 0
        let bindOK = withUnsafePointer(to: &local) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else {
            print("[OnvifDiscovery] bind falhou (errno \(errno))")
            finalizar(); return
        }

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(3702).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

        let probe = Self.probeXML()
        _ = probe.withCString { cstr -> Int in
            withUnsafePointer(to: &dest) { destPtr -> Int in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sock, cstr, strlen(cstr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let fimEm = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 65536)
        while Date() < fimEm, socketAtivo >= 0 {
            let n = recv(sock, &buffer, buffer.count, 0)
            guard n > 0 else { continue }   // timeout do recv (-1) ou vazio: tenta de novo até acabar o prazo
            guard let texto = String(bytes: buffer[0..<n], encoding: .utf8) else { continue }
            processarResposta(texto)
        }
        finalizar()
    }

    private func finalizar() {
        if socketAtivo >= 0 { close(socketAtivo); socketAtivo = -1 }
        DispatchQueue.main.async { self.buscando = false }
    }

    private func processarResposta(_ xml: String) {
        guard let parser = OnvifProbeMatchParser(xml: xml), !parser.xAddrs.isEmpty else { return }
        let device = Device(id: parser.endpointRef ?? parser.xAddrs[0], xAddrs: parser.xAddrs, scopes: parser.scopes)
        DispatchQueue.main.async {
            guard !self.dispositivos.contains(where: { $0.id == device.id }) else { return }
            self.dispositivos.append(device)
        }
    }

    private static func probeXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
        <e:Header>
        <w:MessageID>uuid:\(UUID().uuidString)</w:MessageID>
        <w:To e:mustUnderstand="1">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
        <w:Action e:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
        </e:Header>
        <e:Body>
        <d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe>
        </e:Body>
        </e:Envelope>
        """
    }
}

/// Extrai `XAddrs`, `Scopes` e o `EndpointReference` de uma resposta
/// `ProbeMatch` do WS-Discovery. Ignora namespace (compara só o nome local do
/// elemento) porque cada fabricante prefixa de um jeito diferente.
private final class OnvifProbeMatchParser: NSObject, XMLParserDelegate {
    private(set) var xAddrs: [String] = []
    private(set) var scopes: [String] = []
    private(set) var endpointRef: String?

    private var elementoAtual = ""
    private var buffer = ""
    private var dentroDeEndpointRef = false

    init?(xml: String) {
        super.init()
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
    }

    private static func nomeLocal(_ elemento: String) -> String {
        elemento.split(separator: ":").last.map(String.init) ?? elemento
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elementoAtual = Self.nomeLocal(elementName)
        buffer = ""
        if elementoAtual == "EndpointReference" { dentroDeEndpointRef = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = Self.nomeLocal(elementName)
        let texto = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local {
        case "XAddrs": xAddrs = texto.split(separator: " ").map(String.init)
        case "Scopes": scopes = texto.split(separator: " ").map(String.init)
        case "Address": if dentroDeEndpointRef, endpointRef == nil, !texto.isEmpty { endpointRef = texto }
        case "EndpointReference": dentroDeEndpointRef = false
        default: break
        }
    }
}
