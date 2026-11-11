import Foundation
import CryptoKit
import Security

enum MusicServerKind: String, Codable, CaseIterable, Identifiable {
    case subsonic, jellyfin, folder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .subsonic: return "Navidrome / Subsonic"
        case .jellyfin: return "Jellyfin"
        case .folder: return "Pasta / NAS (SMB)"
        }
    }
}

enum MusicNetwork: String, Codable, CaseIterable, Identifiable {
    case tailscale, local, internet
    var id: String { rawValue }
    var title: String { switch self { case .tailscale: return "Tailscale"; case .local: return "Rede local"; case .internet: return "Internet" } }
    var help: String {
        switch self {
        case .tailscale: return "Conecte o Tailscale no Mac e no servidor. Use o IP 100.x.x.x ou o nome MagicDNS, incluindo a porta do serviço."
        case .local: return "Use o endereço do servidor na sua rede Wi-Fi ou Ethernet, incluindo a porta do serviço."
        case .internet: return "Use o endereço HTTPS público do seu servidor."
        }
    }
}

struct MusicServerProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var kind: MusicServerKind = .subsonic
    var network: MusicNetwork = .tailscale
    var address = ""
    var username = ""
    var folderBookmark: Data?

    func baseURL() throws -> URL {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MusicServerError.message("Informe o endereço do servidor.") }
        if !value.contains("://") { value = (network == .internet ? "https://" : "http://") + value }
        guard var parts = URLComponents(string: value), let host = parts.host, !host.isEmpty,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw MusicServerError.message("Use o endereço do servidor com http:// ou https://, sem usuário, senha ou parâmetros na URL.")
        }
        if network == .internet && parts.scheme?.lowercased() != "https" {
            throw MusicServerError.message("Para conectar pela internet, use o endereço HTTPS do servidor.")
        }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !parts.path.isEmpty { parts.path = "/" + parts.path }
        if kind == .subsonic && parts.path.hasSuffix("/rest") { parts.path = String(parts.path.dropLast(5)) }
        guard let url = parts.url else { throw MusicServerError.message("Endereço inválido.") }
        return url
    }
}

struct MusicCredential: Codable {
    var password = ""
    var token = ""
    var userID = ""
}

struct MusicAlbum: Identifiable {
    let id: String
    let title: String
    let artist: String
    var count = 0
}

struct MusicTrack: Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    var fileURL: URL?
}

enum MusicServerError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }

    static func userMessage(_ error: Error) -> String {
        if let error = error as? MusicServerError { return error.localizedDescription }
        let code = (error as NSError).code
        switch code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "Servidor não encontrado. Confira o endereço e, se usar Tailscale, se ele está conectado e o MagicDNS está ativo."
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
            return "Não foi possível alcançar o servidor. Confira a rede ou o Tailscale, a porta e as permissões de acesso do servidor."
        case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
            return "O certificado HTTPS não foi aceito. Use um certificado válido ou, na sua rede local/VPN, o endereço HTTP do serviço."
        default: return "Não foi possível concluir a conexão. Confira o endereço, o tipo de servidor e suas credenciais."
        }
    }
}

protocol MusicCredentialVault {
    func load(_ id: UUID) throws -> MusicCredential?
    func save(_ credential: MusicCredential, id: UUID) throws
    func delete(_ id: UUID) throws
}

struct KeychainMusicVault: MusicCredentialVault {
    private let service = "com.vitra.radio.music-servers"
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
    func load(_ id: UUID) throws -> MusicCredential? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw MusicServerError.message("Não foi possível ler as credenciais no Chaves do macOS.") }
        return try JSONDecoder().decode(MusicCredential.self, from: data)
    }
    func save(_ credential: MusicCredential, id: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let query = query(id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MusicServerError.message("Não foi possível guardar as credenciais no Chaves do macOS.") }
        } else if status != errSecSuccess { throw MusicServerError.message("Não foi possível atualizar as credenciais no Chaves do macOS.") }
    }
    func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MusicServerError.message("Não foi possível remover as credenciais do Chaves do macOS.") }
    }
}

final class MemoryMusicVault: MusicCredentialVault {
    private var items: [UUID: MusicCredential] = [:]
    func load(_ id: UUID) throws -> MusicCredential? { items[id] }
    func save(_ credential: MusicCredential, id: UUID) throws { items[id] = credential }
    func delete(_ id: UUID) throws { items[id] = nil }
}

enum SubsonicAuthentication {
    static func parameters(username: String, password: String, salt: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) -> [URLQueryItem] {
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        return [URLQueryItem(name: "u", value: username), URLQueryItem(name: "t", value: token), URLQueryItem(name: "s", value: salt),
                URLQueryItem(name: "v", value: "1.16.1"), URLQueryItem(name: "c", value: "VitraRadio"), URLQueryItem(name: "f", value: "json")]
    }
}
