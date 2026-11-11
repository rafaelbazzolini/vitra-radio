import Foundation

// Teste de integração opt-in: usa o mesmo RadioPlayer da interface, sem som.
enum PlaybackVerification {
    @MainActor static func start() {
        Task { @MainActor in
            let domain = "com.vitra.radio.playback-test.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: domain)!
            preferences.set(0.0, forKey: "volume")
            let radio = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
            var failures = 0
            for station in Station.all {
                print("TEST: \(station.name)")
                fflush(stdout)
                radio.select(station)
                let deadline = Date().addingTimeInterval(35)
                while Date() < deadline && !(radio.state == .playing && radio.hasPlaybackProgress) {
                    if !radio.active && radio.failed { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                if radio.state == .playing && radio.hasPlaybackProgress {
                    print("PASS: \(station.name) iniciou reprodução real via AVPlayer, volume 0")
                    radio.select(station)
                    if radio.state != .playing {
                        failures += 1
                        print("FAIL: tocar na mesma rádio reiniciou o stream")
                    }
                } else {
                    failures += 1
                    print("FAIL: \(station.name): \(radio.state.label) · \(radio.diagnosticSummary)")
                }
                fflush(stdout)
                radio.pause()
                try? await Task.sleep(nanoseconds: 350_000_000)
                if radio.state != .paused || radio.active {
                    failures += 1
                    print("FAIL: pausa não permaneceu estável")
                }
            }
            // Requisições antigas não podem sobrescrever a estação escolhida nem a pausa.
            radio.select(Station.all[0])
            radio.select(Station.all[2])
            radio.pause()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if radio.selected.id == "atlantida" && radio.state == .paused && !radio.active {
                print("PASS: troca rápida e pausa descartam callbacks antigos")
            } else {
                failures += 1
                print("FAIL: estado alterado por requisição antiga")
            }
            radio.shutdown()
            preferences.removePersistentDomain(forName: domain)
            print("PLAYBACK_VERIFICATION_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
}
