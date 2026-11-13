import Foundation

@MainActor enum OnlineMusicTests {
    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 } }
        let item = OnlineMusicItem(source: .archive, remoteID: "test-album", title: "Álbum", artist: "Artista")
        let json: [String: Any] = ["metadata": ["licenseurl": "https://creativecommons.org/licenses/by/4.0/"], "files": [
            ["name": "one.mp3", "title": "Música", "original": "one.flac"], ["name": "one.ogg", "original": "one.flac"],
            ["name": "private.mp3", "private": "true"], ["name": "../unsafe.mp3"], ["name": "image.jpg"]
        ]]
        do {
            let tracks = try OnlineMusicClient.archiveFiles(json, item: item)
            check(tracks.count == 1 && tracks[0].file == "one.mp3" && tracks[0].artist == "Artista", "Archive filtra arquivos privados, formatos repetidos e caminhos inseguros")
            do { _ = try OnlineMusicClient.archiveFiles(["is_dark": true, "files": []], item: item); check(false, "Archive bloqueia itens restritos") } catch { check(true, "Archive bloqueia itens restritos") }
            let jamendo: [String: Any] = ["headers": ["status": "success"], "results": [["id": "123", "name": "Music", "audio": "https://audio.example.test/stream", "audiodownload_allowed": false], ["id": "124", "audio": "javascript:bad"]]]
            let found = try OnlineMusicClient.jamendo(jamendo)
            check(found.count == 1 && found[0].remoteID == "123", "Jamendo aceita stream sem download e rejeita esquemas executáveis")
            let suite = "com.vitra.radio.online-tests.\(UUID().uuidString)"
            // Use the precise suite domain for cleanup.
            let isolated = UserDefaults(suiteName: suite)!
            defer { isolated.removePersistentDomain(forName: suite) }
            isolated.set(["radio-original"], forKey: "favorites")
            let store = OnlineMusicStore(preferences: isolated)
            let a = store.create(" Workout ")!, b = store.create("Study")!
            store.add(tracks[0], to: a); store.add(found[0], to: a); store.add(tracks[0], to: a); store.add(item, to: a)
            check(store.playlists[0].tracks.count == 2, "Playlists misturam fontes sem duplicar faixas ou adicionar álbuns inteiros")
            store.moveTrack(found[0], in: a, direction: -1); store.movePlaylist(b, direction: -1); store.rename(a, name: "My mix")
            let restored = OnlineMusicStore(preferences: isolated)
            check(restored.playlists.first?.id == b && restored.playlists.last?.name == "My mix" && restored.playlists.last?.tracks.first?.source == .jamendo, "Playlists preservam nome, fontes e ordem ao reabrir")
            check(isolated.stringArray(forKey: "favorites") == ["radio-original"] && !(String(data: isolated.data(forKey: "onlinePlaylists")!, encoding: .utf8)!.contains("audio.example.test")), "Playlists não alteram rádios nem persistem URLs temporárias de áudio")
            restored.remove(tracks[0], from: a); restored.delete(b)
            check(restored.playlists.count == 1 && restored.playlists[0].tracks.count == 1, "Playlists permitem remover músicas e excluir listas")
        } catch { check(false, "Parser e persistência de músicas online: \(error)") }
        check(OnlineMusicClient.quote("A \"B\" OR *:*") == "\"A \\\"B\\\" OR *:*\"", "Busca Archive escapa sintaxe fornecida pelo usuário")
        return failures
    }
    static func network() {
        Task { @MainActor in
            do {
                let client = OnlineMusicClient()
                let page = try await client.search(source: .archive, text: "", field: .all, genre: "jazz", page: 1, clientID: "")
                guard !page.items.isEmpty else { throw MusicServerError.message("Busca real vazia") }
                var chosen: OnlineMusicItem?
                for item in page.items.prefix(4) { if let files = try? await client.files(item), let first = files.first { chosen = first; break } }
                guard let track = chosen else { throw MusicServerError.message("Nenhuma faixa pública disponível") }
                let stream = try await client.stream(track, clientID: "")
                var request = URLRequest(url: stream); request.timeoutInterval = 25; request.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let response = response as? HTTPURLResponse, [200, 206].contains(response.statusCode) else { throw MusicServerError.message("Stream indisponível") }
                var count = 0; for try await _ in bytes { count += 1; if count >= 8192 { break } }
                guard count > 0 else { throw MusicServerError.message("Stream vazio") }
                print("ONLINE_MUSIC_NETWORK_OK: busca, álbum, resolução e áudio do Archive; \(count) bytes recebidos, sem arquivo de áudio salvo")
                exit(0)
            } catch { print("ONLINE_MUSIC_NETWORK_FAILED: \(error)"); exit(1) }
        }
    }
}
