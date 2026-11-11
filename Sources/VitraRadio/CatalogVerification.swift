import Foundation

enum CatalogVerification {
    @MainActor static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ condition: Bool, _ label: String) {
                if condition { print("PASS: \(label)") }
                else { failures += 1; print("FAIL: \(label)") }
                fflush(stdout)
            }
            do {
                let client = RadioCatalogClient()
                let popular = try await client.search(CatalogQuery())
                check(!popular.stations.isEmpty && popular.rawCount == RadioCatalogClient.pageSize, "Catálogo online retorna a primeira página de rádios")
                let second = try await client.search(CatalogQuery(), offset: RadioCatalogClient.pageSize)
                check(!second.stations.isEmpty && Set(second.stations.map(\.id)) != Set(popular.stations.map(\.id)), "Carregar mais retorna outra página")
                let search = try await client.search(CatalogQuery(name: "Antena", brazilOnly: true))
                check(!search.stations.isEmpty && search.stations.allSatisfy { $0.name.localizedCaseInsensitiveContains("Antena") }, "Busca por nome retorna emissoras correspondentes")
                let world = try await client.search(CatalogQuery(name: "BBC", brazilOnly: false))
                check(!world.stations.isEmpty, "Busca mundial acessa emissoras fora do Brasil")
                let model = RadioCatalog(client: client)
                await model.search(CatalogQuery(name: "Antena"))
                check(!model.isLoading && model.error == nil && !model.stations.isEmpty, "Estado da tela finaliza o carregamento sem erro")
            } catch {
                failures += 1
                print("FAIL: \(error)")
            }
            print("CATALOG_VERIFICATION_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
}
