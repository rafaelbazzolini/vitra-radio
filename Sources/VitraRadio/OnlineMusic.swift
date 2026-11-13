import Foundation
import SwiftUI

enum OnlineMusicSource: String, Codable, CaseIterable { case archive = "Internet Archive", jamendo = "Jamendo" }
enum OnlineMusicField: String, CaseIterable { case all = "Tudo", title = "Nome da música", artist = "Cantor / artista", composer = "Compositor" }
struct OnlineMusicItem: Codable, Identifiable, Equatable {
    let source: OnlineMusicSource
    let remoteID: String
    let title: String
    let artist: String
    var album = ""
    var file: String? // Archive search returns collections; files are resolved when opened.
    var license = ""
    var id: String { source.rawValue + ":" + remoteID + ":" + (file ?? "") }
    var isCollection: Bool { source == .archive && file == nil }
    var page: URL { source == .archive ? URL(string: "https://archive.org/details/" + remoteID)! : URL(string: "https://www.jamendo.com/track/" + remoteID)! }
}
struct OnlinePlaylist: Codable, Identifiable {
    var id = UUID()
    var name: String
    var tracks: [OnlineMusicItem] = []
}
struct OnlineMusicPage { let items: [OnlineMusicItem]; let hasMore: Bool }
struct OnlineMusicClient {
    var session: URLSession = .shared
    static let genres = ["", "electronic", "rock", "pop", "jazz", "classical", "ambient", "relaxation", "hiphop", "instrumental"]
    static func genreTitle(_ genre: String) -> String {
        L10n.tr(["": "Todas as categorias", "electronic": "Eletrônica", "rock": "Rock", "pop": "Pop", "jazz": "Jazz", "classical": "Clássica", "ambient": "Ambient", "relaxation": "Relaxamento", "hiphop": "Hip-hop", "instrumental": "Instrumental"][genre] ?? genre)
    }
    static func text(_ value: Any?) -> String {
        if let value = value as? String { return String(value.prefix(1000)) }
        if let value = value as? [String] { return value.prefix(4).joined(separator: " · ") }
        return ""
    }
    static func quote(_ text: String) -> String { "\"" + String(text.prefix(200)).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    static func url(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }; return url
    }
    func json(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        request.setValue("VitraRadio/0.1.11", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= 12_000_000 else { throw failure("A fonte não respondeu. Tente novamente.") }
        var data = Data()
        for try await byte in bytes { guard data.count < 12_000_000 else { throw failure("A resposta da fonte excedeu o limite.") }; data.append(byte) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Resposta inválida da fonte.") }
        return json
    }
    func failure(_ message: String) -> MusicServerError { .message(L10n.tr(message)) }
    func request(_ base: String, _ params: [String: String]) -> URL {
        var parts = URLComponents(string: base)!; parts.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }; return parts.url!
    }
    func search(source: OnlineMusicSource, text: String, field: OnlineMusicField, genre: String, page: Int, clientID: String) async throws -> OnlineMusicPage {
        let term = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if source == .jamendo {
            guard !clientID.isEmpty else { throw failure("Configure o Client ID do Jamendo para pesquisar nesta fonte.") }
            guard field != .composer else { throw failure("O Jamendo não possui filtro de compositor. Use Tudo ou Cantor / artista.") }
            var params = ["client_id": clientID, "format": "json", "limit": "24", "offset": String((page - 1) * 24), "type": "single albumtrack", "audioformat": "mp32", "include": "licenses"]
            if !term.isEmpty { params[field == .title ? "namesearch" : field == .artist ? "artist_name" : "search"] = term }
            if !genre.isEmpty { params["tags"] = genre }
            if term.isEmpty { params["order"] = "popularity_total" }
            let json = try await json(request("https://api.jamendo.com/v3.0/tracks/", params))
            let tracks = try Self.jamendo(json)
            return OnlineMusicPage(items: tracks, hasMore: (json["results"] as? [Any])?.count == 24)
        }
        var clauses = ["mediatype:audio", "(collection:etree OR collection:netlabels OR collection:audio_music OR collection:georgeblood)", "-access-restricted-item:true"]
        if !term.isEmpty {
            let q = Self.quote(term)
            switch field {
            case .all: clauses.append("(title:\(q) OR creator:\(q) OR composer:\(q) OR description:\(q))")
            case .title: clauses.append("title:\(q)")
            case .artist: clauses.append("creator:\(q)")
            case .composer: clauses.append("composer:\(q)")
            }
        }
        if !genre.isEmpty { clauses.append("subject:" + Self.quote(genre)) }
        let json = try await json(request("https://archive.org/advancedsearch.php", ["q": clauses.joined(separator: " AND "), "output": "json", "rows": "24", "page": String(page), "fl[]": "identifier,title,creator,licenseurl", "sort[]": term.isEmpty ? "downloads desc" : ""] ))
        guard let response = json["response"] as? [String: Any], let docs = response["docs"] as? [[String: Any]] else { throw failure("Resposta inválida da fonte.") }
        let items = docs.compactMap { row -> OnlineMusicItem? in
            let id = Self.text(row["identifier"])
            guard Self.safeID(id) else { return nil }
            return OnlineMusicItem(source: .archive, remoteID: id, title: Self.text(row["title"]), artist: Self.text(row["creator"]), license: Self.text(row["licenseurl"]))
        }
        return OnlineMusicPage(items: items, hasMore: page * 24 < (response["numFound"] as? Int ?? 0))
    }
    static func safeID(_ id: String) -> Bool { !id.isEmpty && id.range(of: "^[a-zA-Z0-9_.-]+$", options: .regularExpression) != nil && id != "." && id != ".." }
    static func jamendo(_ json: [String: Any]) throws -> [OnlineMusicItem] {
        guard let headers = json["headers"] as? [String: Any], (headers["status"] as? String) == "success", let rows = json["results"] as? [[String: Any]] else { throw MusicServerError.message(L10n.tr("O Jamendo não aceitou a consulta. Confira o Client ID e tente novamente.")) }
        return rows.compactMap { row in
            let id = text(row["id"])
            guard id.allSatisfy(\.isNumber), !id.isEmpty, url(text(row["audio"])) != nil else { return nil }
            return OnlineMusicItem(source: .jamendo, remoteID: id, title: text(row["name"]), artist: text(row["artist_name"]), album: text(row["album_name"]), license: text(row["license_ccurl"]))
        }
    }
    static func archiveFiles(_ json: [String: Any], item: OnlineMusicItem) throws -> [OnlineMusicItem] {
        let metadata = json["metadata"] as? [String: Any] ?? [:]
        func restricted(_ value: Any?) -> Bool { (value as? Bool) == true || text(value).lowercased() == "true" || text(value) == "1" }
        guard !restricted(json["is_dark"]), !restricted(metadata["access-restricted-item"]), let files = json["files"] as? [[String: Any]] else { throw MusicServerError.message(L10n.tr("Este item está indisponível ou tem acesso restrito.")) }
        var seen = Set<String>()
        return files.sorted { text($0["name"]) < text($1["name"]) }.compactMap { file in
            let name = text(file["name"]), parts = name.split(separator: "/")
            guard !name.hasPrefix("/"), !parts.contains(".."), !restricted(file["private"]), ["mp3", "m4a", "ogg"].contains((name as NSString).pathExtension.lowercased()) else { return nil }
            let key = ((text(file["original"]).isEmpty ? name : text(file["original"])) as NSString).deletingPathExtension
            guard seen.insert(key).inserted else { return nil }
            return OnlineMusicItem(source: .archive, remoteID: item.remoteID, title: text(file["title"]).isEmpty ? (name as NSString).deletingPathExtension : text(file["title"]), artist: text(file["creator"]).isEmpty ? item.artist : text(file["creator"]), album: item.title, file: name, license: text(metadata["licenseurl"]).isEmpty ? item.license : text(metadata["licenseurl"]))
        }.prefix(500).map { $0 }
    }
    func files(_ item: OnlineMusicItem) async throws -> [OnlineMusicItem] {
        guard Self.safeID(item.remoteID) else { throw failure("Item inválido.") }
        return try Self.archiveFiles(await json(URL(string: "https://archive.org/metadata/" + item.remoteID)!), item: item)
    }
    func stream(_ item: OnlineMusicItem, clientID: String) async throws -> URL {
        if item.source == .archive {
            let available = try await files(item)
            guard let file = item.file, available.contains(where: { $0.file == file }) else { throw failure("Esta faixa não está mais disponível para reprodução.") }
            var url = URL(string: "https://archive.org/download/")!; url.appendPathComponent(item.remoteID); url.appendPathComponent(file); return url
        }
        guard !clientID.isEmpty else { throw failure("Configure o Client ID do Jamendo para pesquisar nesta fonte.") }
        let response = try await json(request("https://api.jamendo.com/v3.0/tracks/", ["client_id": clientID, "id": item.remoteID, "format": "json", "audioformat": "mp32"]))
        _ = try Self.jamendo(response)
        guard let row = (response["results"] as? [[String: Any]])?.first, Self.text(row["id"]) == item.remoteID, let audio = Self.url(Self.text(row["audio"])) else { throw failure("Esta faixa não está mais disponível para reprodução.") }; return audio
    }
}

@MainActor final class OnlineMusicStore: ObservableObject {
    @Published private(set) var playlists: [OnlinePlaylist]
    @Published private(set) var results: [OnlineMusicItem] = []
    @Published private(set) var opened: OnlineMusicItem?
    @Published private(set) var tracks: [OnlineMusicItem] = []
    @Published private(set) var working = false
    @Published private(set) var resolving = false
    @Published private(set) var hasMore = false
    @Published var error: String?
    @Published var notice: String?
    @Published var clientID: String { didSet { preferences.set(clientID, forKey: "jamendoClientID") } }
    private let preferences: UserDefaults
    let client: OnlineMusicClient
    private var generation = UUID(), playGeneration = UUID()
    private var lastQuery: (OnlineMusicSource, String, OnlineMusicField, String)?
    private var page = 1
    private var queue: [OnlineMusicItem] = []
    private var index = 0
    init(preferences: UserDefaults, client: OnlineMusicClient = OnlineMusicClient()) {
        self.preferences = preferences; self.client = client
        playlists = preferences.data(forKey: "onlinePlaylists").flatMap { try? JSONDecoder().decode([OnlinePlaylist].self, from: $0) } ?? []
        clientID = preferences.string(forKey: "jamendoClientID") ?? (Bundle.main.object(forInfoDictionaryKey: "JamendoClientID") as? String ?? "")
    }
    func search(source: OnlineMusicSource, text: String, field: OnlineMusicField, genre: String, more: Bool = false) async {
        let token = UUID(); generation = token; working = true; error = nil
        if !more { page = 1; results = []; opened = nil; tracks = []; hasMore = false }
        let requestedPage = more ? page + 1 : 1
        do {
            let found = try await client.search(source: source, text: text, field: field, genre: genre, page: requestedPage, clientID: clientID)
            guard token == generation else { return }
            var seen = Set<String>(); results = (more ? results + found.items : found.items).filter { seen.insert($0.id).inserted }
            page = requestedPage; hasMore = found.hasMore; lastQuery = (source, text, field, genre)
        } catch { if token == generation { self.error = message(error) } }
        if token == generation { working = false }
    }
    func more() async { guard let q = lastQuery, hasMore, !working else { return }; await search(source: q.0, text: q.1, field: q.2, genre: q.3, more: true) }
    func open(_ item: OnlineMusicItem) async {
        let token = UUID(); generation = token; working = true; opened = item; tracks = []; error = nil
        do { let found = try await client.files(item); if token == generation { tracks = found } }
        catch { if token == generation { self.error = message(error) } }
        if token == generation { working = false }
    }
    func clearSearch() { results = []; hasMore = false; lastQuery = nil; close() }
    func close() { generation = UUID(); opened = nil; tracks = []; working = false; error = nil }
    private func message(_ error: Error) -> String { (error as? MusicServerError)?.localizedDescription ?? L10n.tr("Não foi possível acessar a fonte. Confira a conexão e tente novamente.") }
    private func save() { preferences.set(try? JSONEncoder().encode(playlists), forKey: "onlinePlaylists") }
    @discardableResult func create(_ name: String) -> UUID? {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); guard !name.isEmpty, playlists.count < 100 else { return nil }
        let list = OnlinePlaylist(name: name); playlists.append(list); save(); return list.id
    }
    func rename(_ id: UUID, name: String) { guard let i = playlists.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; playlists[i].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); save() }
    func delete(_ id: UUID) { playlists.removeAll { $0.id == id }; save() }
    func movePlaylist(_ id: UUID, direction: Int) { guard let i = playlists.firstIndex(where: { $0.id == id }), playlists.indices.contains(i + direction) else { return }; playlists.swapAt(i, i + direction); save() }
    func add(_ item: OnlineMusicItem, to id: UUID) {
        guard !item.isCollection, let i = playlists.firstIndex(where: { $0.id == id }), playlists[i].tracks.count < 500 else { return }
        guard !playlists[i].tracks.contains(where: { $0.id == item.id }) else { notice = L10n.tr("Esta faixa já está na playlist."); return }
        playlists[i].tracks.append(item); save(); notice = L10n.tr("Faixa adicionada à playlist.")
    }
    func remove(_ item: OnlineMusicItem, from id: UUID) { guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }; playlists[i].tracks.removeAll { $0.id == item.id }; save() }
    func moveTrack(_ item: OnlineMusicItem, in id: UUID, direction: Int) { guard let i = playlists.firstIndex(where: { $0.id == id }), let j = playlists[i].tracks.firstIndex(where: { $0.id == item.id }), playlists[i].tracks.indices.contains(j + direction) else { return }; playlists[i].tracks.swapAt(j, j + direction); save() }
    func play(_ item: OnlineMusicItem, queue: [OnlineMusicItem], on radio: RadioPlayer) async {
        guard let i = queue.firstIndex(where: { $0.id == item.id }), !item.isCollection else { return }
        self.queue = queue; index = i
        await start(on: radio)
    }
    private func start(on radio: RadioPlayer) async {
        let token = UUID(); playGeneration = token; let intent = radio.playbackIntentID
        guard queue.indices.contains(index) else { return }; let item = queue[index]
        resolving = true; error = nil
        do {
            let url = try await client.stream(item, clientID: clientID)
            guard token == playGeneration, intent == radio.playbackIntentID else { if token == playGeneration { resolving = false }; return }
            let station = Station(id: "online-" + item.id, name: item.title, frequency: item.source.rawValue, genre: item.artist, tagline: item.album, description: item.artist, stream: url, colors: Station.catalogColors, symbol: "music.note", isLive: false)
            radio.playMusic(queue: [station], index: 0, advance: { [weak self, weak radio] direction in
                guard let self, let radio, self.queue.indices.contains(self.index + direction) else { return }
                self.index += direction; Task { await self.start(on: radio) }
            })
        } catch { if token == playGeneration { self.error = message(error) } }
        if token == playGeneration { resolving = false }
    }
}

extension OnlineMusicStore {
    func preview() {
        let album = OnlineMusicItem(source: .archive, remoteID: "vitra-demo-album", title: "Paisagens Sonoras", artist: "Estúdio Vitra · demonstração")
        let one = OnlineMusicItem(source: .archive, remoteID: album.remoteID, title: "Uma manhã tranquila", artist: "Estúdio Vitra", album: album.title, file: "demo.mp3")
        let two = OnlineMusicItem(source: .jamendo, remoteID: "0", title: "Horizontes de papel", artist: "Vitra Sessions", album: "Demonstração")
        results = [album, OnlineMusicItem(source: .archive, remoteID: "vitra-demo-jazz", title: "Jazz em boa companhia", artist: "Vitra Sessions · demonstração")]
        playlists = [OnlinePlaylist(name: "Foco e boas ideias", tracks: [one, two]), OnlinePlaylist(name: "Pausa para respirar", tracks: [one])]
    }
}
