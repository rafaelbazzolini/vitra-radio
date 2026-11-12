import AVFoundation

@MainActor enum PodcastTests {
    static let rss = """
    <?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Podcast de teste</title><itunes:author>Autora original</itunes:author><language>pt-BR</language><description><![CDATA[<p>Ciência &amp; cultura.</p>]]></description><itunes:image href="/cover.png"/>
    <item><title>Episódio &amp; música</title><guid isPermaLink="false">unique-1</guid><enclosure url="/episode.mp3" type="audio/mpeg" length="100"/><itunes:duration>01:02:03</itunes:duration><pubDate>Tue, 10 Nov 2026 14:00:00 +0000</pubDate><description><![CDATA[<b>Descrição</b> segura.]]></description></item>
    <item><title>Duplicado</title><guid>unique-1</guid><enclosure url="/other.mp3" type="audio/mpeg"/></item>
    <item><title>Outro</title><enclosure url="https://example.invalid/two.m4a" type="audio/mp4"/><itunes:duration>120</itunes:duration></item>
    <item><title>Não áudio</title><enclosure url="https://example.invalid/video.mp4" type="video/mp4"/></item>
    <item><title>Local indevido</title><enclosure url="file:///private/secret" type="audio/mpeg"/></item>
    </channel></rss>
    """
    static func run() -> Int {
        var failures = 0
        func check(_ condition: Bool, _ label: String) { print("\(condition ? "PASS" : "FAIL"): \(label)"); if !condition { failures += 1 } }
        let base = URL(string: "https://example.invalid/feed.xml")!
        do {
            let feed = try PodcastRSSParser.parse(Data(rss.utf8), url: base)
            check(feed.show.title == "Podcast de teste" && feed.language == "pt-BR" && feed.show.author == "Autora original", "RSS extrai programa, autoria e idioma sem traduzir conteúdo")
            check(feed.episodes.count == 2 && feed.episodes[0].duration == 3723 && feed.episodes[1].duration == 120, "RSS filtra enclosures, remove GUID repetido e interpreta duração")
            check(feed.episodes[0].audio.absoluteString == "https://example.invalid/episode.mp3" && feed.show.artwork?.absoluteString == "https://example.invalid/cover.png", "URLs relativas de capa e áudio usam a URL final do feed")
            check(feed.episodes[0].summary == "Descrição segura." && feed.show.summary == "Ciência & cultura.", "Descrições RSS são texto seguro sem execução de HTML")
            let redirected = try PodcastRSSParser.parse(Data(rss.utf8), url: URL(string: "https://cdn.example.invalid/new/feed.xml")!, identity: base)
            check(redirected.episodes[0].id == feed.episodes[0].id && redirected.episodes[1].id == feed.episodes[1].id, "GUID e enclosure absoluto mantêm progresso após redirecionamento do RSS")
            let atom = """
            <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en"><title>Atom show</title><entry><id>episode-1</id><title>Atom episode</title><published>2026-11-10T14:00:00Z</published><link rel="enclosure" type="audio/mpeg" href="https://example.invalid/atom.mp3"/><summary>Good story</summary></entry></feed>
            """
            let parsed = try PodcastRSSParser.parse(Data(atom.utf8), url: base)
            check(parsed.language == "en" && parsed.episodes.count == 1 && parsed.episodes[0].published != nil, "Atom extrai idioma, enclosure e data ISO")
            let domain = "com.vitra.radio.podcast-tests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: domain)!
            defer { preferences.removePersistentDomain(forName: domain) }
            preferences.set(["radio-original"], forKey: "favorites")
            let store = PodcastStore(preferences: preferences)
            store.toggle(feed.show); store.toggle(feed.show); store.toggle(feed.show)
            let episode = feed.episodes[0]
            store.remember(episode: episode, show: feed.show); store.record(id: episode.id, seconds: 123, completed: false)
            let restored = PodcastStore(preferences: preferences)
            check(restored.favorites.count == 1 && restored.lastEpisode == episode && restored.position(episode) == 123, "Favoritos, último episódio e posição persistem sem duplicar programas")
            check(preferences.stringArray(forKey: "favorites") == ["radio-original"], "Podcasts não alteram favoritas de rádios")
            restored.record(id: episode.id, seconds: .nan, completed: false)
            check(restored.position(episode) == 123, "Posições inválidas não corrompem o progresso")
            restored.record(id: episode.id, seconds: 3723, completed: true)
            check(restored.position(episode) == 0 && restored.progress[episode.id]?.completed == true, "Episódio concluído recomeça do início")
            let radio = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
            radio.step(1) // Empty production library is permitted.
            radio.shutdown()
            let entries = try PodcastClient.decodeDirectory(Data("""
            {"results":[{"collectionName":"Show","feedUrl":"https://example.invalid/rss"},{"collectionName":"Duplicate","feedUrl":"https://example.invalid/rss"},{"collectionName":"Unsafe","feedUrl":"file:///tmp/a"}]}
            """.utf8))
            check(entries.count == 1, "Busca aceita somente feeds HTTP(S) e elimina duplicatas")
        } catch { check(false, "Fixture RSS/Atom: \(error)") }
        for invalid in ["<html>not a podcast</html>", "<rss><channel></rss>", "<!DOCTYPE rss [<!ENTITY test 'boom'>]><rss><channel><title>&test;</title></channel></rss>"] {
            check((try? PodcastRSSParser.parse(Data(invalid.utf8), url: base)) == nil, "RSS inválido ou com DTD é rejeitado")
        }
        let utf16 = "<!DOCTYPE rss [<!ENTITY test 'boom'>]><rss><channel><title>&test;</title></channel></rss>".data(using: .utf16)!
        check((try? PodcastRSSParser.parse(utf16, url: base)) == nil, "Declaração de entidade em XML UTF-16 também é rejeitada")
        check(PodcastURLs.web("https://user:secret@example.invalid/rss") == nil && PodcastURLs.web("javascript:alert(1)") == nil, "RSS rejeita credenciais em URL e esquemas executáveis")
        check(PodcastRSSParser.duration("-5") == 0 && PodcastRSSParser.duration("nan") == 0, "Duração inválida tem fallback seguro")
        return failures
    }
    private static func writeSilence(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        for _ in 0..<70 { try file.write(from: buffer) }
    }
    static func playback() {
        Task { @MainActor in
            let domain = "com.vitra.radio.podcast-playback.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: domain)!
            preferences.set(0, forKey: "volume")
            let radio = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
            let store = PodcastStore(preferences: preferences)
            radio.onPodcastProgress = { store.record(id: $0, seconds: $1, completed: $2) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("vitra-podcast-\(UUID().uuidString).wav")
            var failures = 0
            func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 }; fflush(stdout) }
            do {
                try writeSilence(file)
                let show = PodcastShow(title: "Podcast de teste", author: "Fixture", feed: URL(string: "https://example.invalid/rss")!)
                let episode = PodcastEpisode(id: "playback-fixture", title: "Episódio local de teste", audio: file, duration: 5)
                store.remember(episode: episode, show: show)
                radio.playPodcast(episode, show: show, position: 12)
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline && (!radio.state.isPlaying || radio.elapsed < 12) { try? await Task.sleep(nanoseconds: 100_000_000) }
                print("PLAYBACK: \(radio.diagnosticSummary) elapsed=\(radio.elapsed) duration=\(radio.duration)")
                check(radio.state.isPlaying && radio.elapsed >= 12 && radio.elapsed < 17, "AVPlayer retoma posição salva mesmo com duração errada no RSS, com saída silenciosa")
                let beforePlay = radio.elapsed
                radio.play()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                check(radio.state.isPlaying && radio.elapsed >= beforePlay, "Comando Play repetido não reinicia o episódio nem apaga sua posição")
                let start = radio.elapsed
                radio.step(1)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                check(radio.elapsed >= start + 14 && radio.elapsed < start + 19, "Avançar do player/miniplayer pula 15 segundos no episódio")
                radio.pause(); radio.seekPodcast(to: 8)
                check(!radio.active && radio.elapsed == 8 && store.position(episode) == 8, "Seek pausado salva posição e não inicia áudio")
                radio.play()
                let resumeDeadline = Date().addingTimeInterval(8)
                while Date() < resumeDeadline && !radio.state.isPlaying { try? await Task.sleep(nanoseconds: 100_000_000) }
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                check(radio.state.isPlaying && radio.elapsed >= 8 && radio.elapsed < 13, "Play depois de seek pausado retoma a nova posição")
                radio.step(-1)
                try? await Task.sleep(nanoseconds: 400_000_000)
                radio.pause()
                check(store.position(episode) < 3, "Voltar 15 segundos respeita o início do episódio")
                radio.play(); try? await Task.sleep(nanoseconds: 1_000_000_000)
                radio.seekPodcast(to: 69)
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                check(store.progress[episode.id]?.completed == true && !radio.active, "Fim real do episódio marca concluído e para sem mudar para uma rádio")
                check(radio.library.allSatisfy { !$0.id.hasPrefix("podcast-") }, "Episódios não entram no catálogo de rádios")
                radio.shutdown(); try? FileManager.default.removeItem(at: file); preferences.removePersistentDomain(forName: domain)
                print("PODCAST_PLAYBACK_\(failures == 0 ? "OK" : "FAILED")"); fflush(stdout); exit(failures == 0 ? 0 : 1)
            } catch { radio.shutdown(); try? FileManager.default.removeItem(at: file); preferences.removePersistentDomain(forName: domain); print("PODCAST_PLAYBACK_FAILED: \(error)"); fflush(stdout); exit(1) }
        }
    }
    static func network() {
        Task {
            do {
                let client = PodcastClient()
                let shows = try await client.search("astronomy", country: "US")
                guard let show = shows.first(where: { $0.feed.scheme == "https" }) else { throw PodcastFailure(message: "Busca sem resultado com RSS HTTPS") }
                print("PASS: catálogo público retorna podcasts com RSS · \(show.feed.absoluteString)"); fflush(stdout)
                let feed = try await client.feed(show)
                guard !feed.episodes.isEmpty, feed.episodes.allSatisfy({ PodcastURLs.web($0.audio.absoluteString) != nil }) else { throw PodcastFailure(message: "RSS real sem episódios válidos") }
                print("PASS: RSS real retorna \(feed.episodes.count) episódios com enclosures válidos"); print("PODCAST_NETWORK_OK"); fflush(stdout); exit(0)
            } catch { print("PODCAST_NETWORK_FAILED: \(error)"); fflush(stdout); exit(1) }
        }
    }
}
