import AppKit

private final class MusicFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".example.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var status = 200
        let path = request.url?.path ?? ""
        var body: [String: Any] = [:]
        if request.url?.host == "subsonic.example.test" {
            let parameters = Self.form(request)
            let salt = parameters["s"] ?? ""
            let expected = SubsonicAuthentication.parameters(username: "tester+local", password: "sesame", salt: salt)
            let token = expected.first { $0.name == "t" }?.value
            if request.httpMethod != "POST" || parameters["u"] != "tester+local" || parameters["t"] != token || salt.count < 6 || parameters["p"] != nil {
                body = ["subsonic-response": ["status": "failed", "error": ["code": 40]]]
            } else if path == "/music/rest/ping.view" {
                body = ["subsonic-response": ["status": "ok", "version": "1.16.1"]]
            } else if path == "/music/rest/getAlbumList2.view" {
                body = ["subsonic-response": ["status": "ok", "albumList2": ["album": [["id": "a1", "name": "Álbum de teste", "artist": "Artista", "songCount": 1]]]]]
            } else if path == "/music/rest/getAlbum.view" {
                body = ["subsonic-response": ["status": "ok", "album": ["song": [["id": "t1", "title": "Faixa de teste", "artist": "Artista", "album": "Álbum de teste", "duration": 123]]]]]
            } else if path == "/music/rest/search3.view" {
                body = ["subsonic-response": ["status": "ok", "searchResult3": ["song": [["id": "t1", "title": parameters["query"] ?? "", "artist": "Artista", "duration": 123]]]]]
            } else { status = 404 }
        } else if path == "/jellyfin/Users/AuthenticateByName" {
            let input = (try? JSONSerialization.jsonObject(with: Self.body(request))) as? [String: Any]
            if input?["Username"] as? String == "tester" && input?["Pw"] as? String == "fixture-password" {
                body = ["AccessToken": "fixture-token", "User": ["Id": "user1"]]
            } else { status = 401 }
        } else if request.value(forHTTPHeaderField: "Authorization")?.contains("Token=\"fixture-token\"") != true {
            status = 401
        } else if path == "/jellyfin/Users/user1" {
            body = ["Id": "user1", "Name": "tester"]
        } else if path == "/jellyfin/Users/user1/Items" {
            let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if params.contains(where: { $0.name == "Fields" && $0.value?.contains("RunTimeTicks") == true }) {
                status = 400
            } else if params.first(where: { $0.name == "IncludeItemTypes" })?.value == "MusicAlbum" {
                body = ["Items": [["Id": "ja1", "Name": "Jelly Album", "AlbumArtist": "Artista"]], "TotalRecordCount": 1]
            } else {
                body = ["Items": [["Id": "jt1", "Name": "Jelly Track", "Artists": ["Artista"], "Album": "Jelly Album", "RunTimeTicks": 1_230_000_000]], "TotalRecordCount": 1]
            }
        } else { status = 404 }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    private static func form(_ request: URLRequest) -> [String: String] {
        let text = String(data: body(request), encoding: .utf8) ?? ""
        let parts = URLComponents(string: "https://fixture.invalid/?" + text.replacingOccurrences(of: "+", with: "%20"))
        return Dictionary((parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}

enum MusicServerVerification {
    @MainActor static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ value: Bool, _ label: String) {
                if value { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures += 1 }
                fflush(stdout)
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MusicFixtureProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let domain = "com.vitra.radio.server-tests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: domain)!
            defer { preferences.removePersistentDomain(forName: domain) }
            do {
                let vector = SubsonicAuthentication.parameters(username: "joe", password: "sesame", salt: "c19b2d")
                check(vector.first { $0.name == "t" }?.value == "26719a1196d2a940705a59634eb18eab", "Autenticação Subsonic corresponde ao vetor oficial")
                var profile = MusicServerProfile(name: "Minha música", address: "http://subsonic.example.test/music/rest/", username: "tester+local")
                check(try profile.baseURL().path == "/music", "Endereço mantém o caminho do proxy e normaliza /rest")
                let auth = try await MusicServerClient(profile: profile, credential: MusicCredential(), session: session).authenticated(password: "sesame")
                let subsonic = MusicServerClient(profile: profile, credential: auth, session: session)
                let albums = try await subsonic.albums()
                check(albums.items.first?.title == "Álbum de teste", "Conector Subsonic lista álbuns autenticados")
                let tracks = try await subsonic.tracks(album: albums.items.first)
                check(tracks.first?.duration == 123, "Conector Subsonic lê faixas do álbum")
                let found = try await subsonic.tracks(search: "João + Maria")
                check(found.first?.title == "João + Maria", "Busca preserva acentos, espaços e sinal de mais")
                let station = try subsonic.playbackStation(tracks[0])
                check(!station.isLive && station.stream.path == "/music/rest/stream.view" && !station.stream.absoluteString.contains("sesame"), "Streaming usa token com salt e mantém a faixa fora de rádios ao vivo")
                let radio = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
                radio.remember(station); radio.toggleFavorite(station)
                check(!radio.library.contains(where: { $0.id == station.id }), "URL de música autenticada não é persistida na biblioteca de rádios")
                radio.shutdown()
                let vault = MemoryMusicVault()
                let store = MusicServerStore(preferences: preferences, vault: vault, makeClient: { MusicServerClient(profile: $0, credential: $1, session: session) })
                let saved = await store.saveAndConnect(profile, password: "sesame")
                check(saved && store.activeProfile?.id == profile.id && store.albums.count == 1, "Salvar conexão abre a biblioteca sem iniciar áudio")
                let serialized = String(data: preferences.data(forKey: "musicServers") ?? Data(), encoding: .utf8) ?? ""
                check(!serialized.contains("sesame") && !serialized.contains("fixture-token"), "Preferências de conexão não contêm senha nem token")
                let restored = MusicServerStore(preferences: preferences, vault: vault, makeClient: { MusicServerClient(profile: $0, credential: $1, session: session) })
                check(restored.profiles.count == 1 && restored.activeProfile == nil, "Perfil persiste sem conectar à rede automaticamente")
                await restored.connect(profile)
                check(restored.activeProfile?.id == profile.id, "Perfil reconecta usando credencial guardada separadamente")
                restored.remove(profile)
                let removedCredential = try vault.load(profile.id)
                check(restored.profiles.isEmpty && removedCredential == nil, "Remover conexão também remove a credencial")
                profile.kind = .jellyfin; profile.address = "http://jellyfin.example.test/jellyfin"; profile.username = "tester"
                let jfAuth = try await MusicServerClient(profile: profile, credential: MusicCredential(), session: session).authenticated(password: "fixture-password")
                check(jfAuth.password.isEmpty && jfAuth.token == "fixture-token", "Jellyfin guarda token de sessão, sem guardar a senha")
                let jellyfin = MusicServerClient(profile: profile, credential: jfAuth, session: session)
                let jfAlbums = try await jellyfin.albums()
                let jfTracks = try await jellyfin.tracks(album: jfAlbums.items.first)
                check(jfAlbums.items.count == 1 && jfTracks.first?.duration == 123, "Conector Jellyfin lista álbuns e faixas autenticadas")
                let jfStation = try jellyfin.playbackStation(jfTracks[0])
                check(jfStation.stream.path == "/jellyfin/Audio/jt1/stream" && !jfStation.isLive, "Jellyfin gera endpoint de reprodução de áudio")
                do {
                    _ = try await MusicServerClient(profile: profile, credential: MusicCredential(), session: session).authenticated(password: "wrong")
                    check(false, "Credenciais incorretas são rejeitadas")
                } catch { check(true, "Credenciais incorretas são rejeitadas") }
                check(MiniSizing.clamped(CGSize(width: 100, height: 10)) == MiniSizing.minimum, "Miniplayer mantém controles acessíveis no tamanho mínimo")
                check(MiniSizing.clamped(CGSize(width: 280, height: 56)).height == 56, "Miniplayer aceita altura reduzida para acompanhar a Dock")
                check(MiniSizing.clamped(CGSize(width: 900, height: 600)) == MiniSizing.maximum, "Redimensionamento respeita limites máximos")
            } catch {
                failures += 1
                print("FAIL: \(MusicServerError.userMessage(error))")
            }
            print("MUSIC_SERVER_VERIFICATION_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas (respostas HTTP de teste; sem usar servidor ou credenciais pessoais)")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
}
