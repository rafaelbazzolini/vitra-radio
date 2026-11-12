import Foundation

private final class CountryCatalogProtocol: URLProtocol {
    static let lock = NSLock()
    private static var offsets: [String: [Int]] = [:]
    static func requestedOffsets(_ code: String) -> [Int] { lock.lock(); defer { lock.unlock() }; return offsets[code] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let code = query.first { $0.name == "countrycode" }?.value ?? "WORLD"
        let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
        Self.lock.lock(); Self.offsets[code, default: []].append(offset); Self.lock.unlock()
        let count = offset == 0 ? 40 : code == "BR" ? 1 : 0
        let rows = (0..<count).map { index -> [String: String] in
            let identifier = "\(code)-\(offset + index)"
            // Deliberate duplicate stream across countries to exercise library deduplication.
            let stream = code == "US" && index == 0 && offset == 0 ? "BR-0" : identifier
            return ["stationuuid": identifier, "name": identifier, "url": "https://example.invalid/\(stream)", "countrycode": code]
        }
        let data = try! JSONSerialization.data(withJSONObject: rows)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum CountryCatalogTests {
    @MainActor static func preferences() -> Int {
        var failures = 0
        func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 } }
        let domain = "com.vitra.radio.country-tests.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: domain)!
        defer { prefs.removePersistentDomain(forName: domain) }
        let store = CatalogCountries(preferences: prefs, region: "PT")
        check(store.codes == ["PT"] && store.needsSetup, "Primeira abertura sugere a região do Mac e pede confirmação")
        store.toggle("BR"); store.finishSetup()
        let restored = CatalogCountries(preferences: prefs, region: "US")
        check(restored.codes == ["BR", "PT"] && !restored.needsSetup, "Vários países persistem sem sobrescrever a escolha em outra região")
        restored.useWorld()
        check(CatalogCountries(preferences: prefs, region: "US").codes.isEmpty, "Mundo todo persiste sem voltar ao país sugerido")
        check(CatalogCountries.clean(["br", "BR", "PT", "invalid"]) == ["BR", "PT"], "Países inválidos e duplicados são removidos")
        check(ProjectSupport(donationURL: "http://example.com/donate").destination == nil, "Apoio rejeita link sem HTTPS")
        check(ProjectSupport(donationURL: "https://user:pass@example.com/donate").destination == nil, "Apoio rejeita credenciais dentro do link")
        check(ProjectSupport(donationURL: nil).destination == nil, "Sem destinatário confirmado, nenhuma cobrança é oferecida")
        return failures
    }
    @MainActor static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 }; fflush(stdout) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [CountryCatalogProtocol.self]
            let client = RadioCatalogClient(session: URLSession(configuration: config))
            do {
                let query = CatalogQuery(countryCodes: ["BR", "US"])
                let page = try await client.search(query)
                check(page.rawCount == 80 && page.hasMore, "Cada país recebe sua própria página, sem truncar o segundo país")
                check(page.stations.prefix(4).map(\.name) == ["BR-0", "US-0", "BR-1", "US-1"], "Resultados dos países são intercalados")
                let model = RadioCatalog(client: client)
                await model.search(query)
                check(model.stations.count == 79, "Streams repetidos entre países não duplicam o catálogo")
                await model.loadMore()
                check(model.stations.count == 80 && !model.hasMore, "Paginação termina após esgotar todos os países")
                check(CountryCatalogProtocol.requestedOffsets("BR").contains(40) && CountryCatalogProtocol.requestedOffsets("US").contains(40), "Carregar mais usa offset por país, e não a soma das páginas")
                _ = try await client.search(CatalogQuery(countryCodes: []))
                check(!CountryCatalogProtocol.requestedOffsets("WORLD").isEmpty, "Sem países selecionados consulta o catálogo mundial")
            } catch { failures += 1; print("FAIL: \(error)") }
            print("COUNTRY_CATALOG_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas (HTTP simulado)")
            fflush(stdout); exit(failures == 0 ? 0 : 1)
        }
    }
}
