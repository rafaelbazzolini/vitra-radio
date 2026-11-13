import Foundation

@MainActor enum RadioMoodTests {
    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 } }
        let domain = "com.vitra.radio.mood-tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set([String](), forKey: "favorites")
        let player = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        let station = RadioMood.suggestions[0].1
        check(player.hasMood(.workout, station: station), "Sugestões de treino têm categoria inicial")
        player.toggleMood(.work, station: station)
        check(player.hasMood(.work, station: station) && player.hasMood(.workout, station: station), "Uma rádio aceita várias categorias")
        check(player.moodStations(.workout).filter { $0.stream == station.stream }.count == 1, "Rádio vinculada não duplica a sugestão")
        player.toggleMood(.workout, station: station)
        let restored = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
        check(restored.hasMood(.work, station: station) && !restored.hasMood(.workout, station: station), "Vínculos e remoção de sugestões persistem")
        check(restored.favorites.isEmpty, "Categorias não adicionam favoritas automaticamente")
        player.shutdown(); restored.shutdown()
        return failures
    }
}
