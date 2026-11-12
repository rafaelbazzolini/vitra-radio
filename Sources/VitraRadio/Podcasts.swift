import Foundation
import CryptoKit

struct PodcastShow: Codable, Identifiable, Equatable {
    var id: String { feed.absoluteString }
    let title: String
    let author: String
    let feed: URL
    var artwork: URL?
    var summary = ""
}
struct PodcastEpisode: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let audio: URL
    var summary = ""
    var published: Date?
    var duration: Double = 0
    static func identifier(feed: URL, guid: String) -> String {
        SHA256.hash(data: Data((feed.absoluteString + "|" + guid).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func station(show: PodcastShow) -> Station {
        Station(id: "podcast-" + id, name: title, frequency: "PODCAST", genre: show.title, tagline: show.title,
                description: summary, stream: audio, colors: Station.catalogColors, symbol: "mic.fill", isLive: false)
    }
}
struct PodcastFeed {
    var show: PodcastShow
    var language: String
    var episodes: [PodcastEpisode]
}
struct PodcastFailure: LocalizedError {
    let message: String
    var errorDescription: String? { L10n.tr(message) }
}

enum PodcastURLs {
    static func web(_ text: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func plain(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12_000))
    }
}

/// RSS 2.0 and Atom enclosures, parsed without HTML rendering or external entities.
final class PodcastRSSParser: NSObject, XMLParserDelegate {
    private let base: URL
    private let identity: URL
    private var path: [String] = []
    private var texts: [String] = []
    private var feedFields: [String: String] = [:]
    private var fields: [String: String] = [:]
    private var media: URL?
    private var image: URL?
    private var episodes: [PodcastEpisode] = []
    private var seen = Set<String>()
    private var inEpisode = false
    private var root = ""
    private init(base: URL, identity: URL) { self.base = base; self.identity = identity }
    static func parse(_ data: Data, url: URL, identity: URL? = nil) throws -> PodcastFeed {
        guard data.count <= 20_000_000, !String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") else {
            throw PodcastFailure(message: "O RSS é muito grande ou contém uma declaração XML não permitida.")
        }
        let delegate = PodcastRSSParser(base: url, identity: identity ?? url)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), ["rss", "feed", "rdf:rdf"].contains(delegate.root), !delegate.episodes.isEmpty else {
            throw PodcastFailure(message: "Este endereço não contém um podcast RSS com episódios de áudio compatíveis.")
        }
        let title = PodcastURLs.plain(delegate.feedFields["title"] ?? "")
        let show = PodcastShow(title: title.isEmpty ? (url.host ?? "Podcast") : title,
                               author: PodcastURLs.plain(delegate.feedFields["itunes:author"] ?? delegate.feedFields["author"] ?? delegate.feedFields["name"] ?? ""),
                               feed: url, artwork: delegate.image,
                               summary: PodcastURLs.plain(delegate.feedFields["description"] ?? delegate.feedFields["subtitle"] ?? ""))
        return PodcastFeed(show: show, language: delegate.feedFields["language"] ?? delegate.feedFields["xml:lang"] ?? "",
                           episodes: delegate.episodes.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) })
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = name.lowercased()
        if path.isEmpty { root = name; feedFields["xml:lang"] = attributes["xml:lang"] }
        guard path.count < 64 else { parser.abortParsing(); return }
        path.append(name); texts.append("")
        if name == "item" || name == "entry" { inEpisode = true; fields = [:]; media = nil }
        if inEpisode && (name == "enclosure" || (name == "link" && attributes["rel"] == "enclosure")) {
            let mime = (attributes["type"] ?? "").lowercased()
            if media == nil && (mime.isEmpty || mime.hasPrefix("audio/") || mime == "application/octet-stream") {
                media = PodcastURLs.web(attributes["url"] ?? attributes["href"] ?? "", relativeTo: base)
            }
        }
        if !inEpisode && name == "itunes:image" { image = PodcastURLs.web(attributes["href"] ?? "", relativeTo: base) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !texts.isEmpty { texts[texts.count - 1] += string.prefix(max(0, 100_000 - texts[texts.count - 1].count)) } }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { if let text = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: text) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let name = name.lowercased()
        guard let text = texts.popLast() else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inEpisode {
            if !value.isEmpty { fields[name] = value }
            if name == "item" || name == "entry" {
                if let media, episodes.count < 500 {
                    let guid = fields["guid"] ?? fields["id"] ?? media.absoluteString
                    let id = PodcastEpisode.identifier(feed: identity, guid: guid)
                    if seen.insert(id).inserted {
                        episodes.append(PodcastEpisode(id: id, title: PodcastURLs.plain(fields["title"] ?? media.lastPathComponent), audio: media,
                            summary: PodcastURLs.plain(fields["content:encoded"] ?? fields["description"] ?? fields["summary"] ?? fields["content"] ?? ""),
                            published: Self.date(fields["pubdate"] ?? fields["published"] ?? fields["updated"] ?? ""),
                            duration: Self.duration(fields["itunes:duration"] ?? "")))
                    }
                }
                inEpisode = false
            }
        } else if !value.isEmpty {
            if name == "url", path.dropLast().last == "image", image == nil { image = PodcastURLs.web(value, relativeTo: base) }
            if feedFields[name] == nil { feedFields[name] = value }
        }
        _ = path.popLast()
        // Preserve text nested in Atom content or descriptions, without executing markup.
        if !texts.isEmpty { texts[texts.count - 1] += text.prefix(max(0, 100_000 - texts[texts.count - 1].count)) }
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { parser.abortParsing() }
    static func duration(_ text: String) -> Double {
        let pieces = text.split(separator: ":")
        guard !pieces.isEmpty, pieces.count <= 3, pieces.allSatisfy({ Double($0).map { $0.isFinite && $0 >= 0 } ?? false }) else { return 0 }
        return min(7 * 86400, pieces.reduce(0) { $0 * 60 + (Double($1) ?? 0) })
    }
    static func date(_ text: String) -> Date? {
        if let value = ISO8601DateFormatter().date(from: text) { return value }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let value = formatter.date(from: text) { return value }
        }
        return nil
    }
}

struct PodcastDirectoryEntry: Decodable {
    let collectionName: String?
    let artistName: String?
    let feedUrl: String?
    let artworkUrl600: String?
    let artworkUrl100: String?
    var show: PodcastShow? {
        guard let title = collectionName, !title.isEmpty, let feed = feedUrl.flatMap({ PodcastURLs.web($0) }) else { return nil }
        return PodcastShow(title: title, author: artistName ?? "", feed: feed,
                           artwork: (artworkUrl600 ?? artworkUrl100).flatMap { PodcastURLs.web($0) })
    }
}
struct PodcastClient {
    var session: URLSession = .shared
    func data(_ url: URL, maximum: Int) async throws -> (Data, URL) {
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("VitraRadio/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let final = response.url,
              PodcastURLs.web(final.absoluteString) != nil, response.expectedContentLength <= maximum else {
            throw PodcastFailure(message: "Não foi possível carregar os podcasts. Confira o endereço e tente novamente.")
        }
        var data = Data()
        for try await byte in bytes {
            if data.count >= maximum { throw PodcastFailure(message: "O RSS é muito grande ou contém uma declaração XML não permitida.") }
            data.append(byte)
            if data.count % 16384 == 0 { try Task.checkCancellation() }
        }
        return (data, final)
    }
    static func decodeDirectory(_ data: Data) throws -> [PodcastShow] {
        struct Result: Decodable { let results: [PodcastDirectoryEntry] }
        var seen = Set<String>()
        return try JSONDecoder().decode(Result.self, from: data).results.compactMap(\.show).filter { seen.insert($0.id).inserted }
    }
    func search(_ term: String, country: String) async throws -> [PodcastShow] {
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "country", value: country),
                          URLQueryItem(name: "media", value: "podcast"), URLQueryItem(name: "entity", value: "podcast"), URLQueryItem(name: "limit", value: "24")]
        let (data, _) = try await data(url.url!, maximum: 2_000_000)
        return try Self.decodeDirectory(data)
    }
    func feed(_ show: PodcastShow) async throws -> PodcastFeed {
        let (data, final) = try await data(show.feed, maximum: 20_000_000)
        var feed = try PodcastRSSParser.parse(data, url: final, identity: show.feed)
        // Keep the requested feed identity stable across HTTP redirects.
        feed.show = PodcastShow(title: feed.show.title, author: feed.show.author, feed: show.feed,
                                artwork: feed.show.artwork ?? show.artwork, summary: feed.show.summary)
        return feed
    }
}

@MainActor final class PodcastStore: ObservableObject {
    struct Progress: Codable { var seconds: Double; var completed: Bool; var updated: Date }
    @Published private(set) var favorites: [PodcastShow]
    @Published private(set) var results: [PodcastShow] = []
    @Published private(set) var opened: PodcastFeed?
    @Published private(set) var progress: [String: Progress]
    @Published private(set) var lastEpisode: PodcastEpisode?
    @Published private(set) var lastShow: PodcastShow?
    @Published private(set) var searching = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private let preferences: UserDefaults
    private let client: PodcastClient
    private var searchGeneration = UUID()
    private var feedGeneration = UUID()
    init(preferences: UserDefaults, client: PodcastClient = PodcastClient()) {
        self.preferences = preferences; self.client = client
        favorites = preferences.data(forKey: "podcastFavorites").flatMap { try? JSONDecoder().decode([PodcastShow].self, from: $0) } ?? []
        progress = preferences.data(forKey: "podcastProgress").flatMap { try? JSONDecoder().decode([String: Progress].self, from: $0) } ?? [:]
        lastEpisode = preferences.data(forKey: "podcastLastEpisode").flatMap { try? JSONDecoder().decode(PodcastEpisode.self, from: $0) }
        lastShow = preferences.data(forKey: "podcastLastShow").flatMap { try? JSONDecoder().decode(PodcastShow.self, from: $0) }
    }
    func toggle(_ show: PodcastShow) {
        if favorites.contains(where: { $0.id == show.id }) { favorites.removeAll { $0.id == show.id } }
        else { favorites.append(show) }
        preferences.set(try? JSONEncoder().encode(favorites), forKey: "podcastFavorites")
    }
    func search(_ text: String, country: String, language: String = "") async {
        let token = UUID(); searchGeneration = token
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; searching = false; return }
        searching = true; error = nil
        do {
            try await Task.sleep(nanoseconds: 450_000_000)
            let client = self.client
            let found = try await client.search(term, country: country)
            var filtered = found
            if !language.isEmpty {
                filtered = []
                // Bound simultaneous publisher requests while checking actual RSS language metadata.
                for start in stride(from: 0, to: found.count, by: 4) {
                    try Task.checkCancellation()
                    let group = Array(found[start..<min(start + 4, found.count)])
                    let accepted = await withTaskGroup(of: PodcastShow?.self, returning: [PodcastShow].self) { tasks in
                        for show in group { tasks.addTask { guard let feed = try? await client.feed(show), feed.language.lowercased().hasPrefix(language) else { return nil }; return show } }
                        var shows: [PodcastShow] = []; for await show in tasks { if let show { shows.append(show) } }; return shows
                    }
                    filtered += group.filter { show in accepted.contains { $0.id == show.id } }
                }
            }
            try Task.checkCancellation()
            guard token == searchGeneration else { return }
            results = filtered; searching = false
        } catch {
            guard token == searchGeneration else { return }
            searching = false
            if !Task.isCancelled { self.error = "Não foi possível buscar os podcasts. Tente novamente." }
        }
    }
    func open(_ show: PodcastShow) async {
        let token = UUID(); feedGeneration = token; loading = true; opened = nil; error = nil
        do {
            let feed = try await client.feed(show)
            guard token == feedGeneration else { return }
            opened = feed; loading = false
        } catch {
            guard token == feedGeneration else { return }
            loading = false
            if !Task.isCancelled { self.error = (error as? PodcastFailure)?.message ?? "Não foi possível carregar os episódios. Tente novamente." }
        }
    }
    func close() { feedGeneration = UUID(); opened = nil; loading = false; error = nil }
    func remember(episode: PodcastEpisode, show: PodcastShow) {
        lastEpisode = episode; lastShow = show
        preferences.set(try? JSONEncoder().encode(episode), forKey: "podcastLastEpisode")
        preferences.set(try? JSONEncoder().encode(show), forKey: "podcastLastShow")
    }
    func record(id: String, seconds: Double, completed: Bool) {
        guard seconds.isFinite, seconds >= 0 else { return }
        progress[id] = Progress(seconds: completed ? 0 : seconds, completed: completed, updated: Date())
        if progress.count > 500 { progress = Dictionary(uniqueKeysWithValues: progress.sorted { $0.value.updated > $1.value.updated }.prefix(500).map { ($0.key, $0.value) }) }
        preferences.set(try? JSONEncoder().encode(progress), forKey: "podcastProgress")
    }
    func position(_ episode: PodcastEpisode) -> Double { progress[episode.id].map { $0.completed ? 0 : $0.seconds } ?? 0 }
}

extension PodcastStore {
    func preview(episodes: Bool) {
        let show = PodcastShow(title: "Frequências do Amanhã", author: "Estúdio Vitra · demonstração", feed: URL(string: "https://example.invalid/podcast.xml")!, summary: "Conversas sobre ciência, cultura e as ideias que transformam o nosso cotidiano. Podcast fictício para demonstração.")
        let episode = PodcastEpisode(id: "podcast-demo-1", title: "Uma pausa para escutar o mundo", audio: URL(string: "https://example.invalid/episode.mp3")!, summary: "Neste episódio, exploramos como a música e as boas histórias podem mudar a maneira como percebemos o dia.", published: Date(timeIntervalSince1970: 1794394800), duration: 2520)
        favorites = [show, PodcastShow(title: "Histórias em Sintonia", author: "Vitra Sessions", feed: URL(string: "https://example.invalid/stories.xml")!)]
        results = favorites
        if episodes { opened = PodcastFeed(show: show, language: "pt-BR", episodes: [episode, PodcastEpisode(id: "podcast-demo-2", title: "O futuro tem muitas vozes", audio: URL(string: "https://example.invalid/episode2.mp3")!, summary: "Ideias, descobertas e novas perspectivas para acompanhar sua semana.", published: Date(timeIntervalSince1970: 1794308400), duration: 1860)]) }
    }
}
