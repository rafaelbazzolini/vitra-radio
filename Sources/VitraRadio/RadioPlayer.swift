import AVFoundation
import Combine
import MediaPlayer
import AppKit

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var selected: Station
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var favorites: Set<String>
    @Published private(set) var recentStationIDs: [String]
    @Published private(set) var library: [Station]
    @Published var volume: Double {
        didSet {
            player.volume = Float(volume)
            preferences.set(volume, forKey: "volume")
        }
    }
    @Published var volumeBalancingEnabled: Bool {
        didSet { preferences.set(volumeBalancingEnabled, forKey: "volumeBalancingEnabled"); if wantsPlayback && selected.isLive { connect() } }
    }
    @Published private(set) var volumeBalanceStatus = "Aguardando reprodução"
    private var balanceTask: Task<Void, Never>?
    @Published var muted = false { didSet { player.isMuted = muted } }
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var remainingMinutes = 0
    @Published var miniVisible = false
    @Published var alwaysOnTop: Bool {
        didSet { preferences.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }

    private let preferences: UserDefaults
    let audioLevels = AudioMeterLevels()
    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var remoteTokens: [(MPRemoteCommand, Any)] = []
    private var timeout: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private(set) var playbackIntentID = UUID()
    private var wantsPlayback = false
    private var attempt = 0
    private var generation = 0
    private var lastFailure = ""
    private var musicQueue: [Station] = []
    private var resumePosition = 0.0
    private let updatesSystemMedia: Bool

    init(preferences: UserDefaults = .standard, updatesSystemMedia: Bool = true) {
        self.preferences = preferences
        self.updatesSystemMedia = updatesSystemMedia
        volumeBalancingEnabled = preferences.object(forKey: "volumeBalancingEnabled") == nil || preferences.bool(forKey: "volumeBalancingEnabled")
        let records = preferences.data(forKey: "savedStations").flatMap { try? JSONDecoder().decode([Station.Saved].self, from: $0) } ?? []
        var known = Set(Station.all.map(\.id))
        let saved = records.compactMap(\.station).filter { known.insert($0.id).inserted }
        let restoredLibrary = Station.all + saved
        recentStationIDs = preferences.stringArray(forKey: "recentStationIDs") ?? []
        library = restoredLibrary
        selected = restoredLibrary.first { $0.id == preferences.string(forKey: "station") } ?? Station.placeholder
        favorites = Set(preferences.stringArray(forKey: "favorites") ?? Station.all.map(\.id))
        volume = preferences.object(forKey: "volume") == nil ? 0.55 : min(1, max(0, preferences.double(forKey: "volume")))
        alwaysOnTop = preferences.object(forKey: "alwaysOnTop") == nil || preferences.bool(forKey: "alwaysOnTop")
        player.volume = Float(volume)
        // Transmissões contínuas não têm um final para pré-carregar. Inicia assim
        // que há áudio, em vez de aguardar a estimativa de buffer do AVPlayer.
        player.automaticallyWaitsToMinimizeStalling = false
        if updatesSystemMedia { configureRemoteCommands() }
    }

    var active: Bool { wantsPlayback }
    var failed: Bool { if case .failed = state { return true }; return false }
    var hasPlaybackProgress: Bool {
        let seconds = player.currentTime().seconds
        return player.currentItem?.status == .readyToPlay && seconds.isFinite && seconds > 0.2
    }
    var diagnosticSummary: String {
        let item = player.currentItem
        let errors = item?.errorLog()?.events.suffix(2).map { "\($0.errorStatusCode): \($0.errorComment ?? "")" }.joined(separator: "; ") ?? ""
        return "item=\(item?.status.rawValue ?? -1) player=\(player.timeControlStatus.rawValue) waiting=\(player.reasonForWaitingToPlay?.rawValue ?? "nil") error=\(String(describing: item?.error ?? player.error)) log=\(errors) previous=\(lastFailure)"
    }

    func select(_ station: Station) {
        playbackIntentID = UUID()
        musicQueue = []
        resumePosition = 0
        let station = remember(station)
        if station.id == selected.id && wantsPlayback { return }
        selected = station
        preferences.set(station.id, forKey: "station")
        play()
    }

    func toggle() { wantsPlayback ? pause() : play() }

    func play() {
        guard selected.id != Station.placeholder.id else { return }
        playbackIntentID = UUID()
        wantsPlayback = true
        if selected.isLive {
            recentStationIDs.removeAll { $0 == selected.id }
            recentStationIDs.insert(selected.id, at: 0)
            recentStationIDs = Array(recentStationIDs.prefix(30))
            preferences.set(recentStationIDs, forKey: "recentStationIDs")
        }
        attempt = 0
        lastFailure = ""
        retryTask?.cancel()
        connect()
    }

    func pause() {
        playbackIntentID = UUID()
        if !selected.isLive {
            let seconds = player.currentTime().seconds
            if seconds.isFinite && seconds >= 0 { resumePosition = seconds }
        }
        wantsPlayback = false
        generation += 1
        timeout?.cancel()
        retryTask?.cancel()
        releaseItem()
        state = .paused
        updateSystemMedia()
    }

    func step(_ direction: Int) {
        if !musicQueue.isEmpty {
            let current = musicQueue.firstIndex(where: { $0.id == selected.id }) ?? 0
            playMusic(queue: musicQueue, index: (current + direction + musicQueue.count) % musicQueue.count)
            return
        }
        let queue = favoriteStations.isEmpty ? library : favoriteStations
        let index = queue.firstIndex(where: { $0.id == selected.id })
        let next = index.map { ($0 + direction + queue.count) % queue.count } ?? (direction < 0 ? queue.count - 1 : 0)
        select(queue[next])
    }

    var recentStations: [Station] { recentStationIDs.compactMap { id in library.first { $0.id == id && $0.isLive } } }
    var favoriteStations: [Station] { library.filter { favorites.contains($0.id) } }

    func canonical(_ station: Station) -> Station {
        library.first { $0.id == station.id || $0.stream == station.stream } ?? station
    }

    func isFavorite(_ station: Station) -> Bool { favorites.contains(canonical(station).id) }

    @discardableResult
    func remember(_ station: Station) -> Station {
        guard station.isLive else { return station }
        let station = canonical(station)
        if !library.contains(where: { $0.id == station.id }) {
            library.append(station)
            let records = library.filter { !Station.all.map(\.id).contains($0.id) }.map(Station.Saved.init)
            if let data = try? JSONEncoder().encode(records) { preferences.set(data, forKey: "savedStations") }
        }
        return station
    }

    func toggleFavorite(_ station: Station) {
        guard station.isLive else { return }
        let station = remember(station)
        if favorites.contains(station.id) { favorites.remove(station.id) } else { favorites.insert(station.id) }
        preferences.set(Array(favorites), forKey: "favorites")
    }

    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes, minutes > 0 else {
            sleepDeadline = nil
            remainingMinutes = 0
            return
        }
        let deadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepDeadline = deadline
        remainingMinutes = minutes
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    self.pause()
                    self.sleepDeadline = nil
                    self.remainingMinutes = 0
                    return
                }
                self.remainingMinutes = Int(ceil(remaining / 60))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func shutdown() {
        pause()
        sleepTask?.cancel()
        for (command, token) in remoteTokens { command.removeTarget(token) }
        remoteTokens.removeAll()
        if updatesSystemMedia { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func playMusic(queue: [Station], index: Int) {
        guard queue.indices.contains(index), !queue[index].isLive else { return }
        musicQueue = queue
        resumePosition = 0
        selected = queue[index]
        // URLs autenticadas e arquivos locais nunca entram nas preferências de rádios.
        play()
    }

    func stopMusic(from serverID: UUID) {
        guard selected.id.hasPrefix("music-\(serverID.uuidString)-") else { return }
        pause(); musicQueue = []; selected = library.first ?? Station.placeholder
    }

    private func releaseItem() {
        balanceTask?.cancel(); balanceTask = nil
        volumeBalanceStatus = "Aguardando reprodução"
        itemObservation = nil
        playbackObservation = nil
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func connect() {
        guard wantsPlayback else { return }
        generation += 1
        let currentGeneration = generation
        timeout?.cancel()
        releaseItem()
        state = .connecting
        updateSystemMedia()
        // HTTP-only options make local AVURLAssets fail while loading audio tracks.
        let options: [String: Any]? = selected.stream.isFileURL ? nil : [AVURLAssetHTTPUserAgentKey: "VitraRadio/1.0", AVURLAssetPreferPreciseDurationAndTimingKey: false]
        let asset = AVURLAsset(url: selected.stream, options: options)
        // O inicializador padrão carrega "duration", que pode nunca concluir
        // em uma rádio MP3 sem fim. Só precisamos saber se é reproduzível.
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: selected.isLive ? ["playable"] : ["playable", "duration"])
        item.preferredForwardBufferDuration = 1
        scheduleTimeout(generation: currentGeneration)
        configureVolumeBalance(for: item) { [weak self] in
            guard let self, self.generation == currentGeneration, self.wantsPlayback else { return }
            self.attachPlaybackItem(item, generation: currentGeneration)
        }
    }

    private func attachPlaybackItem(_ item: AVPlayerItem, generation currentGeneration: Int) {
        player.replaceCurrentItem(with: item)

        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration, self.wantsPlayback else { return }
                let status = self.player.currentItem?.status
                if status == .failed { self.connectionFailed(generation: currentGeneration) }
                else if status == .readyToPlay {
                    self.startPreparedPlayback(generation: currentGeneration)
                }
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration, self.wantsPlayback else { return }
                let status = self.player.timeControlStatus
                if status == .playing && self.player.currentItem?.status == .readyToPlay {
                    self.markPlaying()
                } else if status == .waitingToPlayAtSpecifiedRate {
                    self.state = .connecting
                    self.scheduleTimeout(generation: currentGeneration)
                }
            }
        }
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                let ended = notification.name == AVPlayerItem.didPlayToEndTimeNotification
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    if ended && !self.selected.isLive {
                        if let index = self.musicQueue.firstIndex(where: { $0.id == self.selected.id }), index + 1 < self.musicQueue.count {
                            self.playMusic(queue: self.musicQueue, index: index + 1)
                        } else { self.pause(); self.resumePosition = 0 }
                    } else { self.connectionFailed(generation: currentGeneration, error: error) }
                }
            })
        }
        scheduleTimeout(generation: currentGeneration)
        if selected.isLive { player.playImmediately(atRate: 1) }
    }

    private func configureVolumeBalance(for newItem: AVPlayerItem? = nil, completion: (() -> Void)? = nil) {
        balanceTask?.cancel()
        guard let item = newItem ?? player.currentItem else { return }
        let expectedGeneration = generation
        let normalize = selected.isLive && volumeBalancingEnabled
        let isHLS = selected.stream.pathExtension.lowercased() == "m3u8"
        if #available(macOS 27.0, *), isHLS {
            item.audioMix = AudioBalanceTap.makeMix(meter: audioLevels, normalize: normalize)
            volumeBalanceStatus = item.audioMix == nil ? "Medição indisponível nesta transmissão" : "Processamento de áudio configurado"
            completion?()
        } else if isHLS {
            volumeBalanceStatus = "HLS requer macOS 27 para medição e equilíbrio automático"
            completion?()
        } else {
            volumeBalanceStatus = "Preparando medição do áudio"
            balanceTask = Task { [weak self, weak item] in
                guard let item else { return }
                do {
                    let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                    guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
                    if let track = tracks.first {
                        // Files and direct streams need their real track ID, including on macOS 27.
                        item.audioMix = AudioBalanceTap.makeMix(trackID: track.trackID, meter: self.audioLevels, normalize: self.selected.isLive && self.volumeBalancingEnabled)
                    } else if #available(macOS 27.0, *) {
                        item.audioMix = AudioBalanceTap.makeMix(meter: self.audioLevels, normalize: self.selected.isLive && self.volumeBalancingEnabled)
                    }
                    self.volumeBalanceStatus = item.audioMix == nil ? "Medição indisponível nesta transmissão" : "Processamento de áudio configurado"
                    completion?()
                } catch {
                    guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
                    if #available(macOS 27.0, *) {
                        item.audioMix = AudioBalanceTap.makeMix(meter: self.audioLevels, normalize: self.selected.isLive && self.volumeBalancingEnabled)
                    }
                    self.volumeBalanceStatus = item.audioMix == nil ? "Medição indisponível nesta transmissão" : "Processamento de áudio configurado"
                    completion?()
                }
            }
        }
    }

    private func startPreparedPlayback(generation expectedGeneration: Int) {
        if !selected.isLive && resumePosition > 0 {
            let position = resumePosition
            resumePosition = 0
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == expectedGeneration, self.wantsPlayback else { return }
                    self.player.playImmediately(atRate: 1)
                    if self.player.timeControlStatus == .playing { self.markPlaying() }
                }
            }
        } else {
            player.playImmediately(atRate: 1)
            if player.timeControlStatus == .playing { markPlaying() }
        }
    }

    private func markPlaying() {
        timeout?.cancel()
        attempt = 0
        state = .playing
        updateSystemMedia()
    }

    private func scheduleTimeout(generation: Int) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self, self.state != .playing else { return }
            self.connectionFailed(generation: generation)
        }
    }

    private func connectionFailed(generation failedGeneration: Int, error: NSError? = nil) {
        guard wantsPlayback, generation == failedGeneration else { return }
        if !selected.isLive {
            let seconds = player.currentTime().seconds
            if seconds.isFinite && seconds > 0 { resumePosition = seconds }
        }
        lastFailure = "status \(player.currentItem?.status.rawValue ?? -1), \(String(describing: error ?? player.currentItem?.error ?? player.error)), \(player.currentItem?.errorLog()?.events.last?.errorComment ?? "sem erro reportado")"
        generation += 1
        timeout?.cancel()
        releaseItem()
        if error?.code == -66681 {
            wantsPlayback = false
            state = .failed("Saída de áudio indisponível")
        } else if attempt < 3 {
            attempt += 1
            state = .failed("Reconectando · \(attempt)/3")
            let delay = UInt64(attempt * 3) * 1_000_000_000
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self?.connect()
            }
        } else {
            wantsPlayback = false
            state = .failed("Sem conexão · tente novamente")
        }
        updateSystemMedia()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let actions: [(MPRemoteCommand, (RadioPlayer) -> Void)] = [
            (center.playCommand, { $0.play() }), (center.pauseCommand, { $0.pause() }),
            (center.togglePlayPauseCommand, { $0.toggle() }),
            (center.nextTrackCommand, { $0.step(1) }), (center.previousTrackCommand, { $0.step(-1) })
        ]
        for (command, action) in actions {
            command.isEnabled = true
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in if let self { action(self) } }
                return .success
            }
            remoteTokens.append((command, token))
        }
    }

    private func updateSystemMedia() {
        guard updatesSystemMedia else { return }
        if state == .idle { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: selected.name,
            MPMediaItemPropertyArtist: "\(selected.genre) · Vitra Radio",
            MPNowPlayingInfoPropertyIsLiveStream: selected.isLive,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = state.isPlaying ? .playing : (wantsPlayback ? .interrupted : .paused)
    }
}
