import AppKit

@MainActor
final class MusicServerStore: ObservableObject {
    @Published private(set) var profiles: [MusicServerProfile]
    @Published private(set) var activeProfile: MusicServerProfile?
    @Published private(set) var albums: [MusicAlbum] = []
    @Published private(set) var tracks: [MusicTrack] = []
    @Published private(set) var currentAlbum: MusicAlbum?
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var hasMoreAlbums = false
    @Published private(set) var showingTracks = false
    private let preferences: UserDefaults
    private let vault: MusicCredentialVault
    private let makeClient: (MusicServerProfile, MusicCredential) -> MusicServerClient
    private var client: MusicServerClient?
    private var folderURL: URL?
    private var folderTracks: [MusicTrack] = []
    private var generation = UUID()
    private var albumOffset = 0

    init(preferences: UserDefaults = .standard, vault: MusicCredentialVault = KeychainMusicVault(),
         makeClient: @escaping (MusicServerProfile, MusicCredential) -> MusicServerClient = { MusicServerClient(profile: $0, credential: $1) }) {
        self.preferences = preferences
        self.vault = vault
        self.makeClient = makeClient
        profiles = preferences.data(forKey: "musicServers").flatMap { try? JSONDecoder().decode([MusicServerProfile].self, from: $0) } ?? []
    }

    func test(_ profile: MusicServerProfile, password: String) async throws {
        _ = try await validatedCredential(profile, password: password)
    }

    func saveAndConnect(_ profile: MusicServerProfile, password: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true; error = nil
        do {
            var profile = profile
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { profile.name = profile.kind.title }
            let credential = try await validatedCredential(profile, password: password)
            if profile.kind != .folder { try vault.save(credential, id: profile.id) }
            else { try vault.delete(profile.id) }
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
            else { profiles.append(profile) }
            persist()
            isWorking = false
            await connect(profile)
            return true
        } catch {
            self.error = MusicServerError.userMessage(error); isWorking = false
            return false
        }
    }

    func connect(_ profile: MusicServerProfile) async {
        guard !isWorking else { return }
        disconnect()
        let token = generation
        isWorking = true; error = nil
        do {
            if profile.kind == .folder {
                let url = try resolveFolder(profile)
                _ = url.startAccessingSecurityScopedResource()
                folderURL = url
                let files = try await Self.scanFolder(url)
                guard token == generation else { return }
                folderTracks = files; tracks = files; showingTracks = true
                activeProfile = profile
            } else {
                guard let credential = try vault.load(profile.id) else { throw MusicServerError.message("Configure novamente o servidor para informar suas credenciais.") }
                let client = makeClient(profile, credential)
                let page = try await client.albums()
                guard token == generation else { return }
                self.client = client; activeProfile = profile
                albums = page.items; albumOffset = page.items.count; hasMoreAlbums = page.hasMore
            }
            isWorking = false
        } catch {
            guard token == generation else { return }
            folderURL?.stopAccessingSecurityScopedResource(); folderURL = nil
            self.error = MusicServerError.userMessage(error); isWorking = false
        }
    }

    func disconnect() {
        generation = UUID()
        folderURL?.stopAccessingSecurityScopedResource(); folderURL = nil
        client = nil; activeProfile = nil; albums = []; tracks = []; folderTracks = []
        currentAlbum = nil; hasMoreAlbums = false; showingTracks = false; isWorking = false; error = nil
    }

    func remove(_ profile: MusicServerProfile) {
        do {
            try vault.delete(profile.id)
            if activeProfile?.id == profile.id { disconnect() }
            profiles.removeAll { $0.id == profile.id }; persist()
        } catch { self.error = MusicServerError.userMessage(error) }
    }

    func openAlbum(_ album: MusicAlbum) async {
        guard let client, !isWorking else { return }
        let token = generation
        isWorking = true; error = nil
        do {
            let items = try await client.tracks(album: album)
            guard token == generation else { return }
            tracks = items; currentAlbum = album; showingTracks = true; isWorking = false
        } catch {
            if token == generation { self.error = MusicServerError.userMessage(error); isWorking = false }
        }
    }

    func search(_ query: String) async {
        guard let profile = activeProfile, !isWorking else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.kind == .folder {
            tracks = text.isEmpty ? folderTracks : folderTracks.filter { "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(text) }
            showingTracks = true; return
        }
        if text.isEmpty { showAlbums(); return }
        guard let client else { return }
        let token = generation
        isWorking = true; error = nil
        do {
            let items = try await client.tracks(search: text)
            guard token == generation else { return }
            tracks = items; currentAlbum = nil; showingTracks = true; isWorking = false
        } catch {
            if token == generation { self.error = MusicServerError.userMessage(error); isWorking = false }
        }
    }

    func showAlbums() { tracks = []; currentAlbum = nil; showingTracks = false; error = nil }

    func loadMoreAlbums() async {
        guard let client, !isWorking, hasMoreAlbums else { return }
        let token = generation
        isWorking = true; error = nil
        do {
            let page = try await client.albums(offset: albumOffset)
            guard token == generation else { return }
            let ids = Set(albums.map(\.id))
            albums += page.items.filter { !ids.contains($0.id) }
            albumOffset += page.items.count; hasMoreAlbums = page.hasMore; isWorking = false
        } catch {
            if token == generation { self.error = MusicServerError.userMessage(error); isWorking = false }
        }
    }

    func play(_ track: MusicTrack, on radio: RadioPlayer) {
        guard let profile = activeProfile else { return }
        do {
            let builder = client ?? makeClient(profile, MusicCredential())
            let queue = try tracks.map { try builder.playbackStation($0) }
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
            radio.playMusic(queue: queue, index: index)
        } catch { self.error = MusicServerError.userMessage(error) }
    }

    private func validatedCredential(_ profile: MusicServerProfile, password: String) async throws -> MusicCredential {
        if profile.kind == .folder {
            let url = try resolveFolder(profile)
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  FileManager.default.isReadableFile(atPath: url.path) else { throw MusicServerError.message("A pasta não está disponível. Monte o compartilhamento no Finder e escolha a pasta novamente.") }
            return MusicCredential()
        }
        _ = try profile.baseURL()
        let previous = profiles.first { $0.id == profile.id }
        let reusable = previous?.address == profile.address && previous?.username == profile.username && previous?.kind == profile.kind
        let stored = reusable ? try vault.load(profile.id) : nil
        return try await makeClient(profile, stored ?? MusicCredential()).authenticated(password: password)
    }

    private func persist() { if let data = try? JSONEncoder().encode(profiles) { preferences.set(data, forKey: "musicServers") } }

    private func resolveFolder(_ profile: MusicServerProfile) throws -> URL {
        guard let bookmark = profile.folderBookmark else { throw MusicServerError.message("Escolha uma pasta de música no Mac ou em um compartilhamento montado no Finder.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { throw MusicServerError.message("O acesso salvo à pasta expirou. Edite o servidor e selecione a pasta novamente.") }
        return url
    }

    private static func scanFolder(_ url: URL) async throws -> [MusicTrack] {
        try await Task.detached(priority: .userInitiated) {
            try Self.scanFiles(url)
        }.value
    }

    nonisolated private static func scanFiles(_ url: URL) throws -> [MusicTrack] {
            let extensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "mp4"]
            guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                throw MusicServerError.message("Não foi possível ler essa pasta.")
            }
            var tracks: [MusicTrack] = []
            for case let file as URL in files {
                try Task.checkCancellation()
                guard extensions.contains(file.pathExtension.lowercased()),
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                tracks.append(MusicTrack(id: file.path, title: file.deletingPathExtension().lastPathComponent,
                                         artist: "Arquivo local", album: file.deletingLastPathComponent().lastPathComponent, duration: 0, fileURL: file))
                if tracks.count >= 5000 { break }
            }
            return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
