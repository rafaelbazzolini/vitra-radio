import Foundation

private final class MusicRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Não encaminha autenticação a outro servidor ou de HTTPS para HTTP.
        let original = task.originalRequest?.url
        let allowed = request.url?.host?.lowercased() == original?.host?.lowercased()
            && !(original?.scheme == "https" && request.url?.scheme != "https")
        completionHandler(allowed ? request : nil)
    }
}

struct MusicServerClient {
    let profile: MusicServerProfile
    let credential: MusicCredential
    let session: URLSession
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 35
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: MusicRedirectPolicy(), delegateQueue: nil)
    }()

    init(profile: MusicServerProfile, credential: MusicCredential, session: URLSession? = nil) {
        self.profile = profile
        self.credential = credential
        self.session = session ?? Self.sharedSession
    }

    func authenticated(password: String) async throws -> MusicCredential {
        switch profile.kind {
        case .folder: return MusicCredential()
        case .subsonic:
            let secret = password.isEmpty ? credential.password : password
            guard !profile.username.trimmingCharacters(in: .whitespaces).isEmpty, !secret.isEmpty else {
                throw MusicServerError.message("Informe o usuário e a senha da sua conta no servidor.")
            }
            let credential = MusicCredential(password: secret)
            let client = MusicServerClient(profile: profile, credential: credential, session: session)
            _ = try await client.subsonic("ping")
            return credential
        case .jellyfin:
            if password.isEmpty && !credential.token.isEmpty && !credential.userID.isEmpty {
                _ = try await jellyfin("Users/\(credential.userID)")
                return credential
            }
            guard !profile.username.trimmingCharacters(in: .whitespaces).isEmpty else { throw MusicServerError.message("Informe seu usuário no Jellyfin.") }
            let data = try JSONSerialization.data(withJSONObject: ["Username": profile.username, "Pw": password])
            let object = try await jellyfin("Users/AuthenticateByName", body: data)
            guard let token = object["AccessToken"] as? String,
                  let user = object["User"] as? [String: Any], let id = user["Id"] as? String else {
                throw MusicServerError.message("O Jellyfin não retornou uma sessão válida.")
            }
            return MusicCredential(token: token, userID: id)
        }
    }

    func albums(offset: Int = 0) async throws -> (items: [MusicAlbum], hasMore: Bool) {
        switch profile.kind {
        case .subsonic:
            let object = try await subsonic("getAlbumList2", parameters: ["type": "newest", "size": "40", "offset": String(offset)])
            let rows = (object["albumList2"] as? [String: Any])?["album"] as? [[String: Any]] ?? []
            return (rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                return MusicAlbum(id: id, title: row["name"] as? String ?? "Álbum", artist: row["artist"] as? String ?? "Artista desconhecido", count: row["songCount"] as? Int ?? 0)
            }, rows.count == 40)
        case .jellyfin:
            let object = try await jellyfin("Users/\(credential.userID)/Items", parameters: ["IncludeItemTypes": "MusicAlbum", "Recursive": "true", "SortBy": "DateCreated", "SortOrder": "Descending", "StartIndex": String(offset), "Limit": "40"])
            let rows = object["Items"] as? [[String: Any]] ?? []
            return (rows.compactMap { row in
                guard let id = row["Id"] as? String else { return nil }
                return MusicAlbum(id: id, title: row["Name"] as? String ?? "Álbum", artist: row["AlbumArtist"] as? String ?? "Sua biblioteca", count: row["ChildCount"] as? Int ?? 0)
            }, offset + rows.count < (object["TotalRecordCount"] as? Int ?? rows.count))
        case .folder: return ([], false)
        }
    }

    func tracks(album: MusicAlbum? = nil, search: String = "") async throws -> [MusicTrack] {
        switch profile.kind {
        case .subsonic:
            if let album {
                let object = try await subsonic("getAlbum", parameters: ["id": album.id])
                return (((object["album"] as? [String: Any])?["song"] as? [[String: Any]]) ?? []).compactMap(Self.subsonicTrack)
            }
            let object = try await subsonic("search3", parameters: ["query": search, "songCount": "100", "songOffset": "0", "albumCount": "0", "artistCount": "0"])
            return (((object["searchResult3"] as? [String: Any])?["song"] as? [[String: Any]]) ?? []).compactMap(Self.subsonicTrack)
        case .jellyfin:
            var parameters = ["IncludeItemTypes": "Audio", "Recursive": "true", "SortBy": "ParentIndexNumber,IndexNumber,SortName", "Limit": "100"]
            if let album { parameters["ParentId"] = album.id }
            if !search.isEmpty { parameters["SearchTerm"] = search }
            let object = try await jellyfin("Users/\(credential.userID)/Items", parameters: parameters)
            return (object["Items"] as? [[String: Any]] ?? []).compactMap { row in
                guard let id = row["Id"] as? String else { return nil }
                return MusicTrack(id: id, title: row["Name"] as? String ?? "Faixa",
                                  artist: (row["Artists"] as? [String])?.joined(separator: ", ") ?? "Artista desconhecido",
                                  album: row["Album"] as? String ?? "", duration: (row["RunTimeTicks"] as? Double ?? 0) / 10_000_000)
            }
        case .folder: return []
        }
    }

    func playbackStation(_ track: MusicTrack) throws -> Station {
        let url: URL
        if let file = track.fileURL { url = file }
        else if profile.kind == .subsonic {
            var components = URLComponents(url: try endpoint("rest/stream.view"), resolvingAgainstBaseURL: false)!
            components.queryItems = authParameters + [URLQueryItem(name: "id", value: track.id)]
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            url = components.url!
        } else {
            var components = URLComponents(url: try endpoint("Audio/\(track.id)/stream"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "static", value: "true"), URLQueryItem(name: "api_key", value: credential.token)]
            url = components.url!
        }
        return Station(id: "music-\(profile.id.uuidString)-\(track.id)", name: track.title,
                       frequency: track.album, genre: track.artist,
                       tagline: "Sua biblioteca, sempre por perto.", description: "\(track.artist) · \(track.album)",
                       stream: url, colors: Station.catalogColors, symbol: "music.note", isLive: false)
    }

    private var authParameters: [URLQueryItem] { SubsonicAuthentication.parameters(username: profile.username, password: credential.password) }
    private func endpoint(_ path: String) throws -> URL { try profile.baseURL().appendingPathComponent(path) }

    private func subsonic(_ method: String, parameters: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: try endpoint("rest/\(method).view"))
        request.httpMethod = "POST"
        var form = URLComponents()
        form.queryItems = authParameters + parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let object = try await json(request)
        guard let response = object["subsonic-response"] as? [String: Any] else { throw MusicServerError.message("Esse endereço não retornou uma API Subsonic. Confira o tipo de servidor e o endereço base.") }
        if response["status"] as? String != "ok" {
            let code = (response["error"] as? [String: Any])?["code"] as? Int ?? 0
            throw MusicServerError.message(code == 40 ? "Usuário ou senha não aceitos pelo servidor." : "O servidor não permitiu essa operação (código \(code)).")
        }
        return response
    }

    private func jellyfin(_ path: String, parameters: [String: String] = [:], body: Data? = nil) async throws -> [String: Any] {
        var components = URLComponents(url: try endpoint(path), resolvingAgainstBaseURL: false)!
        if !parameters.isEmpty { components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let token = credential.token.replacingOccurrences(of: "\"", with: "")
        request.setValue("MediaBrowser Client=\"VitraRadio\", Device=\"Mac\", DeviceId=\"\(profile.id.uuidString)\", Version=\"1.2.0\"" + (token.isEmpty ? "" : ", Token=\"\(token)\""), forHTTPHeaderField: "Authorization")
        return try await json(request)
    }

    private func json(_ original: URLRequest) async throws -> [String: Any] {
        var request = original
        request.setValue("VitraRadio/1.2", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 { throw MusicServerError.message("Acesso não autorizado. Confira usuário, senha e permissões da conta.") }
        guard (200..<300).contains(http.statusCode) else { throw MusicServerError.message("O servidor respondeu com erro \(http.statusCode). Confira o endereço e o tipo de servidor.") }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw MusicServerError.message("O endereço retornou uma página em vez da biblioteca. Informe o endereço base do serviço, sem /web ou a página de login.") }
        return object
    }

    private static func subsonicTrack(_ row: [String: Any]) -> MusicTrack? {
        guard let id = row["id"] as? String else { return nil }
        return MusicTrack(id: id, title: row["title"] as? String ?? "Faixa", artist: row["artist"] as? String ?? "Artista desconhecido", album: row["album"] as? String ?? "", duration: row["duration"] as? Double ?? 0)
    }
}
