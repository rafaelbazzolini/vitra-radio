import AVFoundation

@MainActor enum AudioBalanceVerification {
    static func verifyPlayerMeter() {
        Task { @MainActor in
            let domain = "com.vitra.radio.player-meter.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: domain)!
            let hls = CommandLine.arguments.contains("--verify-player-meter-hls")
            // HLS may skip audio rendering at exactly zero volume. -100 dB keeps the test effectively inaudible.
            preferences.set(hls ? 0.00001 : 0.0, forKey: "volume")
            let player = RadioPlayer(preferences: preferences, updatesSystemMedia: false)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("vitra-meter-\(UUID().uuidString).wav")
            defer { player.shutdown(); preferences.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
            do {
                try writeTone(file, amplitude: 0.5, stereo: true, frequency: 125, rightFrequency: 4000)
                let baseline = AVPlayer(url: file)
                baseline.volume = 0
                baseline.play()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard baseline.currentItem?.status == .readyToPlay else { throw AppUpdateError(message: "O arquivo de teste não iniciou a reprodução de referência.") }
                baseline.pause(); baseline.replaceCurrentItem(with: nil)
                let stream = hls ? URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/a1/prog_index.m3u8")! : file
                player.select(Station(id: "meter-fixture", name: "Teste de medição", frequency: "WEB", genre: "Teste", tagline: "", description: "", stream: stream, colors: Station.catalogColors, symbol: "waveform"))
                var measured = false
                let deadline = Date().addingTimeInterval(hls ? 20 : 8)
                while Date() < deadline {
                    let levels = player.audioLevels.read()
                    if player.state.isPlaying && (hls ? player.audioLevels.hasRecentSamples : levels.0 > 0.01 && levels.1 > 0.001) { measured = true; break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                print("\(measured ? "PASS" : "FAIL"): AVPlayer alimenta o medidor real durante reprodução (\(hls ? "HLS em volume mínimo" : "arquivo, saída zero"))")
                if !measured { print(player.diagnosticSummary); print("METER_STATUS: \(player.volumeBalanceStatus) fresh=\(player.audioLevels.hasRecentSamples) levels=\(player.audioLevels.read())") }
                player.pause()
                try? await Task.sleep(nanoseconds: 400_000_000)
                var music = Station(id: "music-meter-fixture", name: "Faixa de teste", frequency: "", genre: "Teste", tagline: "", description: "", stream: file, colors: Station.catalogColors, symbol: "music.note")
                music.isLive = false
                player.playMusic(queue: [music], index: 0)
                var musicMeasured = false
                let musicDeadline = Date().addingTimeInterval(8)
                while Date() < musicDeadline {
                    let levels = player.audioLevels.read()
                    if player.state.isPlaying && levels.0 > 0.3 && levels.1 > 0.03 { musicMeasured = true; break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                print("\(musicMeasured ? "PASS" : "FAIL"): Faixa de música alimenta o VU sem normalização de rádio")
                measured = measured && musicMeasured
                print("PLAYER_METER_\(measured ? "OK" : "FAILED")")
                player.shutdown(); preferences.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file)
                fflush(stdout); exit(measured ? 0 : 1)
            } catch { print("PLAYER_METER_FAILED: \(error)"); fflush(stdout); exit(1) }
        }
    }

    static func start() {
        Task {
            var failures = 0
            func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 }; fflush(stdout) }
            do {
                let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/audio-balance-tests")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let quiet = folder.appendingPathComponent("quiet.wav"), loud = folder.appendingPathComponent("loud.wav")
                try writeTone(quiet, amplitude: 0.07)
                try writeTone(loud, amplitude: 0.7)
                let a = try await read(quiet), b = try await read(loud)
                check(a.samples > 0 && b.samples > 0, "Tap nativo processa PCM pelo AVAssetReader sem saída de áudio")
                let difference = abs(20 * log10(max(a.rms, 0.000001) / max(b.rms, 0.000001)))
                check(difference < 2, "Fontes com 20 dB de diferença convergem para menos de 2 dB")
                check(a.peak <= 0.941 && b.peak <= 0.941, "Processamento mantém os picos abaixo do limite")
                check(a.rms > 0.09 && b.rms < 0.15, "Rádio baixa recebe ganho e rádio alta é atenuada")
                let stereo = folder.appendingPathComponent("stereo.wav")
                try writeTone(stereo, amplitude: 0.7, stereo: true)
                let meter = AudioMeterLevels()
                let measured = try await read(stereo, meter: meter, normalize: false, stereo: true)
                let levels = meter.read()
                check(levels.0 > 0.45 && levels.0 < 0.55 && levels.1 > 0.045 && levels.1 < 0.055, "VU mede canais reais independentes com 20 dB de diferença")
                check(measured.peak > 0.69, "VU não normaliza nem atenua o áudio com equilíbrio desativado")
                try writeTone(stereo, amplitude: 0, stereo: true)
                _ = try await read(stereo, meter: meter, normalize: false, stereo: true)
                check(meter.read().0 == 0 && meter.read().1 == 0, "VU zera com amostras de silêncio")
                try writeTone(stereo, amplitude: 0.5, stereo: true, frequency: 125, rightFrequency: 4000)
                _ = try await read(stereo, meter: meter, normalize: false, stereo: true)
                let leftBands = meter.spectrum(right: false), rightBands = meter.spectrum(right: true)
                check(leftBands.indices.max(by: { leftBands[$0] < leftBands[$1] }) == 1, "Espectro esquerdo identifica o tom real de 125 Hz")
                check(rightBands.indices.max(by: { rightBands[$0] < rightBands[$1] }) == 6, "Espectro direito identifica 4 kHz independentemente do canal esquerdo")
                check(leftBands[1] > leftBands[6] * 5 && rightBands[6] > rightBands[1] * 5, "Colunas separam graves e agudos sem repetir o volume geral")
                let dsp = AudioBalanceDSP()
                for _ in 0..<1000 { _ = dsp.gains(sumSquares: 0, sampleCount: 480, peak: 0, seconds: 0.01) }
                check(dsp.gain == 1, "Silêncio não provoca aumento de ganho")
                for _ in 0..<2000 { _ = dsp.gains(sumSquares: 0.00001, sampleCount: 480, peak: 0.001, seconds: 0.01) }
                check(dsp.gain <= 3, "Ruído muito baixo não é amplificado sem limite")
                let limiter = AudioBalanceDSP()
                let gains = limiter.gains(sumSquares: 1000, sampleCount: 480, peak: 2, seconds: 0.01)
                check(max(gains.0, gains.1) * 2 <= AudioBalanceDSP.ceiling + 0.000001, "Pico súbito recebe proteção imediata")
            } catch { check(false, "Verificação de áudio: \(error)") }
            print("AUDIO_BALANCE_VERIFICATION: \(failures) falhas; processamento offline, sem afirmar reprodução audível")
            fflush(stdout); exit(failures == 0 ? 0 : 1)
        }
    }
    private static func writeTone(_ url: URL, amplitude: Float, stereo: Bool = false, frequency: Double = 440, rightFrequency: Double? = nil) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: stereo ? 2 : 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var offset = 0
        while offset < 48_000 * 16 {
            let frames = min(1024, 48_000 * 16 - offset)
            buffer.frameLength = AVAudioFrameCount(frames)
            for index in 0..<frames {
                let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(offset + index) / 48_000))
                buffer.floatChannelData![0][index] = value
                if stereo { buffer.floatChannelData![1][index] = amplitude * 0.1 * Float(sin(2 * Double.pi * (rightFrequency ?? frequency) * Double(offset + index) / 48_000)) }
            }
            try file.write(from: buffer); offset += frames
        }
    }
    private static func read(_ url: URL, meter: AudioMeterLevels? = nil, normalize: Bool = true, stereo: Bool = false) async throws -> (rms: Double, peak: Double, samples: Int) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: stereo ? 2 : 1]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        guard let track = tracks.first, let mix = AudioBalanceTap.makeMix(trackID: track.trackID, meter: meter, normalize: normalize) else { throw NSError(domain: "AudioBalance", code: 1) }
        output.audioMix = mix
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "AudioBalance", code: 2) }
        var sum = 0.0, peak = 0.0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: bytes / 4)
            let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
            guard status == noErr else { throw NSError(domain: "AudioBalance", code: Int(status)) }
            let settled = CMSampleBufferGetPresentationTimeStamp(sample).seconds >= 12
            for value in samples { peak = max(peak, Double(abs(value))); if settled { sum += Double(value) * Double(value); count += 1 } }
        }
        guard reader.status == .completed, count > 0 else { throw reader.error ?? NSError(domain: "AudioBalance", code: 3) }
        return (sqrt(sum / Double(count)), peak, count)
    }
}
