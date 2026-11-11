import Foundation

struct CatalogStation: Decodable {
    let stationuuid: String
    let name: String
    let url: String
    let url_resolved: String?
    let tags: String?
    let country: String?
    let countrycode: String?
    let state: String?
    let codec: String?

    var station: Station? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = url_resolved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !stationuuid.isEmpty,
              let stream = URL(string: resolved.isEmpty ? url : resolved),
              ["http", "https"].contains(stream.scheme?.lowercased() ?? ""), stream.host != nil else { return nil }
        if let original = Station.all.first(where: { $0.stream == stream }) { return original }
        let location = [state, country].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " · ")
        let styles = (tags ?? "").split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Station(id: "rb-" + stationuuid, name: title,
                       frequency: location.isEmpty ? "WEB RADIO" : location,
                       genre: styles.isEmpty ? "Rádio ao vivo" : styles,
                       tagline: "Sintonize uma nova companhia.",
                       description: location.isEmpty ? "Uma nova frequência para acompanhar o seu dia." : "Ao vivo de \(location). Uma nova frequência para acompanhar o seu dia.",
                       stream: stream, colors: Station.catalogColors, symbol: "antenna.radiowaves.left.and.right")
    }
}

struct CatalogQuery: Equatable, Hashable {
    var name = ""
    var brazilOnly = true
}

struct CatalogPage {
    let stations: [Station]
    let rawCount: Int
}

struct RadioCatalogClient {
    static let pageSize = 40
    var session: URLSession = .shared

    func search(_ query: CatalogQuery, offset: Int = 0) async throws -> CatalogPage {
        // O DNS distribui as conexões entre os espelhos públicos do diretório.
        var components = URLComponents(string: "https://all.api.radio-browser.info/json/stations/search")!
        components.queryItems = [
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if query.brazilOnly { components.queryItems?.append(URLQueryItem(name: "countrycode", value: "BR")) }
        let name = query.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { components.queryItems?.append(URLQueryItem(name: "name", value: name)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 18
        request.setValue("VitraRadio/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        let records = try JSONDecoder().decode([CatalogStation].self, from: data)
        return CatalogPage(stations: records.compactMap(\.station), rawCount: records.count)
    }
}

@MainActor
final class RadioCatalog: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private var query = CatalogQuery()
    private var offset = 0
    private var generation = UUID()
    private let client: RadioCatalogClient

    init(client: RadioCatalogClient = RadioCatalogClient()) { self.client = client }

    func search(_ query: CatalogQuery) async {
        generation = UUID()
        let token = generation
        self.query = query
        stations = []
        offset = 0
        hasMore = false
        error = nil
        isLoading = true
        do {
            try await Task.sleep(nanoseconds: 400_000_000)
            try await receive(token: token)
        } catch {
            if generation == token {
                isLoading = false
                if !Task.isCancelled { self.error = "Não foi possível carregar as rádios. Confira sua conexão e tente novamente." }
            }
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        error = nil
        let token = generation
        do { try await receive(token: token) }
        catch {
            if generation == token {
                isLoading = false
                if !Task.isCancelled { self.error = "Não foi possível carregar mais rádios. Tente novamente." }
            }
        }
    }

    private func receive(token: UUID) async throws {
        let page = try await client.search(query, offset: offset)
        try Task.checkCancellation()
        guard generation == token else { return }
        var ids = Set(stations.map(\.id))
        var streams = Set(stations.map(\.stream))
        stations += page.stations.filter { station in
            guard !ids.contains(station.id), !streams.contains(station.stream) else { return false }
            ids.insert(station.id); streams.insert(station.stream)
            return true
        }
        offset += page.rawCount
        hasMore = page.rawCount == RadioCatalogClient.pageSize
        isLoading = false
    }
}
