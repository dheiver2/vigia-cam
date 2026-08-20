import Foundation
import CryptoKit

enum OnvifError: LocalizedError {
    case respostaInvalida
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .respostaInvalida: return "Resposta ONVIF inesperada (a câmera pode não suportar o serviço solicitado)."
        case .http(let codigo): return "A câmera respondeu HTTP \(codigo) — confira usuário e senha."
        }
    }
}

/// Cliente ONVIF mínimo: só o necessário para (1) resolver a URL RTSP de um
/// dispositivo achado via `OnvifDiscoveryService` e (2) mandar comandos PTZ
/// básicos. Não é uma implementação completa da spec — não há WSDL, XML é
/// montado/lido por extração de texto (as respostas dessas operações têm
/// formato simples e estável o bastante pra isso).
///
/// Autenticação: WS-Security UsernameToken com `PasswordDigest`
/// (Base64(SHA1(nonce + created + senha))) — é o que a spec ONVIF exige; a
/// maioria das câmeras rejeita `PasswordText` puro.
final class OnvifClient {
    let deviceXAddr: URL
    let usuario: String
    let senha: String

    init(deviceXAddr: URL, usuario: String, senha: String) {
        self.deviceXAddr = deviceXAddr
        self.usuario = usuario
        self.senha = senha
    }

    // MARK: - Resolução de câmera (device -> media -> stream RTSP)

    /// Descobre o serviço de Mídia (e o de PTZ, se existir), pega o primeiro
    /// perfil de vídeo e resolve a URL RTSP dele.
    func resolverCameraCompleta() async throws -> (rtsp: URL, ptzXAddr: URL?, perfilToken: String) {
        let caps = try await capabilities()
        let mediaXAddr = caps.media ?? deviceXAddr
        let perfis = try await getProfiles(mediaXAddr: mediaXAddr)
        guard let token = perfis.first else { throw OnvifError.respostaInvalida }
        let rtsp = try await getStreamUri(mediaXAddr: mediaXAddr, profileToken: token)
        return (rtsp, caps.ptz, token)
    }

    func capabilities() async throws -> (media: URL?, ptz: URL?) {
        let body = #"<GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl"><Category>All</Category></GetCapabilities>"#
        let xml = try await post(deviceXAddr, soapAction: "http://www.onvif.org/ver10/device/wsdl/GetCapabilities", body: body)
        return (blocoXAddr(tag: "Media", xml: xml), blocoXAddr(tag: "PTZ", xml: xml))
    }

    func getProfiles(mediaXAddr: URL) async throws -> [String] {
        let body = #"<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>"#
        let xml = try await post(mediaXAddr, soapAction: "http://www.onvif.org/ver10/media/wsdl/GetProfiles", body: body)
        let tokens = Self.extrairAtributo("Profiles", atributo: "token", xml: xml)
        guard !tokens.isEmpty else { throw OnvifError.respostaInvalida }
        return tokens
    }

    func getStreamUri(mediaXAddr: URL, profileToken: String) async throws -> URL {
        let body = """
        <GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">
        <StreamSetup>
        <Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>
        <Transport xmlns="http://www.onvif.org/ver10/schema"><Protocol>RTSP</Protocol></Transport>
        </StreamSetup>
        <ProfileToken>\(Self.escaparXML(profileToken))</ProfileToken>
        </GetStreamUri>
        """
        let xml = try await post(mediaXAddr, soapAction: "http://www.onvif.org/ver10/media/wsdl/GetStreamUri", body: body)
        guard let uriTexto = Self.extrairValores("Uri", xml: xml).first,
              let url = URL(string: uriTexto.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OnvifError.respostaInvalida
        }
        return injetarCredenciais(url)
    }

    /// A URI que o `GetStreamUri` devolve normalmente NÃO traz usuário/senha
    /// — a autenticação de RTSP (se exigida) é feita à parte, via digest do
    /// próprio protocolo RTSP. `ffmpeg` (usado por `FFmpegRTSPSource`) aceita
    /// `rtsp://user:pass@host/...`, então embutimos aqui pra o cadastro já
    /// sair funcional sem passo extra pro usuário.
    private func injetarCredenciais(_ url: URL) -> URL {
        guard url.user == nil, !usuario.isEmpty else { return url }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.user = usuario
        comps?.password = senha
        return comps?.url ?? url
    }

    // MARK: - PTZ

    /// Move continuamente até `ptzParar` ser chamado. `panX`/`tiltY`/`zoom`
    /// em -1...1 (velocidade normalizada, convenção ONVIF).
    func ptzMover(ptzXAddr: URL, profileToken: String, panX: Double, tiltY: Double, zoom: Double = 0) async throws {
        let body = """
        <ContinuousMove xmlns="http://www.onvif.org/ver10/ptz/wsdl">
        <ProfileToken>\(Self.escaparXML(profileToken))</ProfileToken>
        <Velocity>
        <PanTilt xmlns="http://www.onvif.org/ver10/schema" x="\(panX)" y="\(tiltY)"/>
        <Zoom xmlns="http://www.onvif.org/ver10/schema" x="\(zoom)"/>
        </Velocity>
        </ContinuousMove>
        """
        _ = try await post(ptzXAddr, soapAction: "http://www.onvif.org/ver10/ptz/wsdl/ContinuousMove", body: body)
    }

    func ptzParar(ptzXAddr: URL, profileToken: String) async throws {
        let body = """
        <Stop xmlns="http://www.onvif.org/ver10/ptz/wsdl">
        <ProfileToken>\(Self.escaparXML(profileToken))</ProfileToken>
        <PanTilt>true</PanTilt>
        <Zoom>true</Zoom>
        </Stop>
        """
        _ = try await post(ptzXAddr, soapAction: "http://www.onvif.org/ver10/ptz/wsdl/Stop", body: body)
    }

    // MARK: - Transporte SOAP

    private func post(_ xAddr: URL, soapAction: String, body: String) async throws -> String {
        var req = URLRequest(url: xAddr)
        req.httpMethod = "POST"
        req.setValue("application/soap+xml; charset=utf-8; action=\"\(soapAction)\"", forHTTPHeaderField: "Content-Type")
        req.httpBody = envelope(body: body).data(using: .utf8)
        req.timeoutInterval = 8
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnvifError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func envelope(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
        <s:Header>\(securityHeader())</s:Header>
        <s:Body>\(body)</s:Body>
        </s:Envelope>
        """
    }

    private func securityHeader() -> String {
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let created = ISO8601DateFormatter().string(from: Date())
        var entrada = nonce
        entrada.append(Data(created.utf8))
        entrada.append(Data(senha.utf8))
        let digest = Insecure.SHA1.hash(data: entrada)
        let digestB64 = Data(digest).base64EncodedString()
        let nonceB64 = nonce.base64EncodedString()
        return """
        <Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
        <UsernameToken>
        <Username>\(Self.escaparXML(usuario))</Username>
        <Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">\(digestB64)</Password>
        <Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">\(nonceB64)</Nonce>
        <Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">\(created)</Created>
        </UsernameToken>
        </Security>
        """
    }

    // MARK: - Extração de XML (regex — respostas dessas operações têm forma simples e estável)

    private func blocoXAddr(tag: String, xml: String) -> URL? {
        let padrao = "<(?:\\w+:)?\(tag)>(.*?)</(?:\\w+:)?\(tag)>"
        guard let re = try? NSRegularExpression(pattern: padrao, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(m.range(at: 1), in: xml) else { return nil }
        let bloco = String(xml[range])
        return Self.extrairValores("XAddr", xml: bloco).first.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func extrairValores(_ tag: String, xml: String) -> [String] {
        let padrao = "<(?:\\w+:)?\(tag)(?:\\s[^>]*)?>(.*?)</(?:\\w+:)?\(tag)>"
        guard let re = try? NSRegularExpression(pattern: padrao, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = xml as NSString
        return re.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func extrairAtributo(_ tag: String, atributo: String, xml: String) -> [String] {
        let padrao = "<(?:\\w+:)?\(tag)[^>]*\\s\(atributo)=\"([^\"]*)\""
        guard let re = try? NSRegularExpression(pattern: padrao) else { return [] }
        let ns = xml as NSString
        return re.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func escaparXML(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
