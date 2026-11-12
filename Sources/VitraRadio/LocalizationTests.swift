import Foundation

@MainActor enum LocalizationTests {
    static func run() -> Int {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failures += 1 }
        }
        let domain = "com.vitra.radio.localization-tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        let previous = L10n.language
        defer { preferences.removePersistentDomain(forName: domain); L10n.language = previous }
        let localization = AppLocalization()
        localization.configure(preferences: preferences, preferred: ["en-US"])
        check(localization.language == .english && L10n.tr("Ajustes") == "Settings", "Primeira abertura sugere o idioma suportado do sistema")
        check(AppLanguage.suggested(["fr-FR", "pt-PT"]) == .portuguese && AppLanguage.suggested(["ja-JP"]) == .portuguese, "Região de português é reconhecida e idioma não suportado tem fallback")
        let countries = CatalogCountries(preferences: preferences, region: "BR")
        countries.toggle("US")
        check(countries.needsSetup && countries.codes == ["BR", "US"], "Idioma e seleção de países são independentes no primeiro acesso")
        countries.finishSetup()
        preferences.set("Rádio com nome original", forKey: "station")
        preferences.set("heritage", forKey: "playerSkin")
        preferences.set(["regra-pessoal"], forKey: "automationSentinel")
        let before = preferences.dictionaryRepresentation()
        localization.select(.portuguese)
        let restored = AppLocalization()
        restored.configure(preferences: preferences, preferred: ["en-GB"])
        check(restored.language == .portuguese && preferences.string(forKey: "interfaceLanguage") == "pt-BR", "Escolha pt-BR persiste e vence o idioma do sistema ao reabrir")
        restored.select(.english)
        let after = preferences.dictionaryRepresentation()
        check(before.filter { $0.key != "interfaceLanguage" } as NSDictionary == after.filter { $0.key != "interfaceLanguage" } as NSDictionary, "Trocar idioma preserva rádios, temas, automações e países")
        check(!CatalogCountries(preferences: preferences, region: "DE").needsSetup, "Trocar idioma não reabre a configuração inicial")
        check(L10n.tr("Ouvir \("Minha Rádio %@ especial")") == "Listen to Minha Rádio %@ especial", "Interpolação preserva nome de rádio, acentos e caracteres de formato")
        check(L10n.tr("Trocar tema · \("Heritage")") == "Change theme · Heritage", "Tradução interpola rótulos sem traduzir nomes próprios")
        check(CatalogCountries.name("BR") == "Brazil" && PlaybackState.playing.label == "Live", "País e status de reprodução acompanham o idioma")
        let rule = RadioAutomation(station: Station.Saved(Station.all[0]), weekdays: [2, 6])
        check(rule.daysLabel == "Mon · Fri" && rule.weekdays == [2, 6], "Dias traduzidos preservam os dias reais da automação")
        check(!L10n.english.isEmpty && L10n.english.allSatisfy { $0.key.components(separatedBy: "%@").count == $0.value.components(separatedBy: "%@").count }, "Catálogo inglês embarcado mantém todas as interpolações")
        check(Station.placeholder.displayName == "Choose your station", "Estado inicial sem rádio traduz sem alterar nomes de emissoras")
        check(Station.demo[0].displayName == Station.demo[0].name, "Nome próprio de rádio permanece original")
        let failure = PlaybackState.failed("Reconectando · \(2)/3")
        check(failure.label == "Reconnecting · 2/3", "Status dinâmico interpola a tentativa no idioma atual")
        restored.select(.portuguese)
        check(failure.label == "Reconectando · 2/3", "Status já existente muda de idioma sem repetir a operação")
        check(PlaybackState.playing.label == "Ao vivo" && L10n.tr("Ajustes") == "Ajustes", "Retornar ao português restaura os rótulos sem reiniciar")
        preferences.set("invalid", forKey: "interfaceLanguage")
        restored.configure(preferences: preferences, preferred: ["pt-BR"])
        check(restored.language == .portuguese, "Preferência inválida recupera um idioma suportado")
        return failures
    }
}
