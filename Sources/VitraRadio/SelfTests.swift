import Foundation
import CoreGraphics

enum SelfTests {
    @MainActor static func run() {
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            if condition() { print("PASS: \(label)") }
            else { failures += 1; print("FAIL: \(label)") }
        }
        let domain = "com.vitra.radio.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }

        check(Station.all.count == 5, "Cinco emissoras fictícias para testes")
        check(Set(Station.all.map(\.id)).count == Station.all.count, "Identificadores de rádio únicos")
        check(Station.all.allSatisfy { $0.stream.scheme == "https" }, "Streams HTTPS")
        check(Station.all.allSatisfy { $0.stream.host == "example.invalid" }, "Fixtures não contêm rádios pessoais")
        let radio = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        check(radio.state == .idle && !radio.active, "Abrir o app não reproduz áudio")
        check(radio.volume == 0.55, "Volume inicial moderado")
        check(radio.favorites.count == Station.all.count, "Rádios iniciais disponíveis nas favoritas")
        radio.toggleFavorite(Station.all[1])
        let restored = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        check(!restored.favorites.contains(Station.all[1].id), "Favoritas persistem ao reabrir")
        let record = try! JSONDecoder().decode(CatalogStation.self, from: Data("""
        {"stationuuid":"catalog-test","name":"Rádio de teste","url":"http://example.com/original","url_resolved":"https://example.com/live.mp3","tags":"jazz,blues","country":"Brazil","countrycode":"BR","state":"RS","codec":"MP3"}
        """.utf8))
        let external = record.station!
        check(external.stream.absoluteString == "https://example.com/live.mp3", "Catálogo prioriza o stream resolvido")
        radio.toggleFavorite(external)
        check(radio.isFavorite(external) && !radio.active, "Favoritar uma rádio do catálogo não inicia áudio")
        radio.remember(external)
        check(radio.library.filter { $0.id == external.id }.count == 1, "Rádio do catálogo salva sem duplicação")
        preferences.set(external.id, forKey: "station")
        let catalogRestored = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        check(catalogRestored.isFavorite(external) && catalogRestored.library.contains(where: { $0.id == external.id }), "Rádio favoritada do catálogo persiste ao reabrir")
        check(catalogRestored.selected.id == external.id && !catalogRestored.active, "Última rádio do catálogo restaurada sem autoplay")
        catalogRestored.toggleFavorite(external)
        check(!catalogRestored.isFavorite(external), "Rádio externa pode ser removida das favoritas")
        let invalid = try! JSONDecoder().decode(CatalogStation.self, from: Data("""
        {"stationuuid":"bad","name":"Rádio inválida","url":"file:///etc/passwd"}
        """.utf8))
        check(invalid.station == nil, "Catálogo rejeita endereços que não são HTTP ou HTTPS")
        catalogRestored.shutdown()
        radio.volume = 0.3
        check(preferences.double(forKey: "volume") == 0.3, "Volume persistido")
        radio.setSleep(minutes: 15)
        check(radio.sleepDeadline != nil && radio.remainingMinutes == 15, "Timer de 15 minutos")
        radio.setSleep(minutes: nil)
        check(radio.sleepDeadline == nil && radio.remainingMinutes == 0, "Cancelar timer limpa prazo")
        radio.pause()
        check(radio.state == .paused && !radio.active, "Pausa encerra reprodução e reconexões")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 244, height: 86)
        let clamped = MiniPlacement.clamped(CGPoint(x: 4000, y: -500), size: size, screens: [screen])
        check(clamped == CGPoint(x: 1188, y: 8), "Miniplayer de monitor removido volta à tela")
        let dockOrigin = CGPoint(x: 1180, y: 14)
        check(MiniPlacement.clamped(dockOrigin, size: size, screens: [screen]) == dockOrigin, "Posição na faixa da Dock preservada")
        let secondScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let secondOrigin = CGPoint(x: -600, y: 20)
        check(MiniPlacement.clamped(secondOrigin, size: size, screens: [screen, secondScreen]) == secondOrigin, "Posição no segundo monitor preservada")
        check(radio.recentStations.isEmpty, "Favoritar sem ouvir não cria histórico recente")
        radio.select(Station.all[0]); radio.pause()
        radio.select(external); radio.pause()
        radio.select(Station.all[0]); radio.pause()
        check(radio.recentStations.map(\.id) == [Station.all[0].id, external.id], "Recentes ordenam por última reprodução sem duplicar")
        let historyRestored = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        check(historyRestored.recentStations.map(\.id) == radio.recentStations.map(\.id) && !historyRestored.active, "Recentes persistem ao reabrir sem iniciar áudio")
        historyRestored.shutdown()
        radio.shutdown()
        restored.shutdown()
        check(FrequencyScale.fm("94,7 FM") == 94.7, "Sintonia reconhece a frequência FM com vírgula")
        check(FrequencyScale.fm("93.7 MHz") == 93.7, "Sintonia reconhece ponto decimal e MHz")
        check(FrequencyScale.fm("WEB RADIO") == nil && FrequencyScale.fm("Brasil") == nil, "Rádio web não recebe frequência inventada")
        check(FrequencyScale.fm("120 FM") == nil, "Frequência fora da escala não posiciona o marcador")
        check(abs(FrequencyScale.position(94.7) - (94.7 - 87.5) / 20.5) < 0.000001, "Marcador usa a posição exata da frequência na escala")
        check(FrequencyScale.position(87.5) == 0 && FrequencyScale.position(108) == 1, "Extremos da faixa FM coincidem com a escala")
        failures += AutomationTests.run()
        print("\(failures == 0 ? "SELF_TEST_OK" : "SELF_TEST_FAILED"): \(failures) falhas")
        if failures > 0 { exit(1) }
    }
}
