import AppKit

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: URL
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }

    func asset(_ name: String, maximum: Int) throws -> Asset {
        let matches = assets.filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first, asset.size > 0, asset.size <= maximum,
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.path == "/\(UpdateChecker.repository)/releases/download/\(tag_name)/\(name)" else {
            throw AppUpdateError(message: L10n.tr("O pacote macOS desta versão ainda não está disponível para atualização dentro do app."))
        }
        return asset
    }

    static func newer(from data: Data, current: String) throws -> AppRelease? {
        let release = try JSONDecoder().decode(AppRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              release.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { return nil }
        guard release.version.compare(current, options: .numeric) == .orderedDescending else { return nil }
        _ = try release.asset(UpdateInstaller.assetName, maximum: 150_000_000)
        _ = try release.asset("SHA256SUMS.txt", maximum: 100_000)
        return release
    }
}

enum UpdateCheckSchedule {
    static let interval: TimeInterval = 24 * 60 * 60
    static func isDue(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval || lastAttempt > now
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    nonisolated static let repository = "rafaelbazzolini/vitra-radio"
    @Published private(set) var available: AppRelease?
    @Published private(set) var checking = false
    @Published private(set) var installing = false
    @Published private(set) var detail: String?
    @Published private(set) var error: String?
    @Published private(set) var lastCheck: Date?
    @Published var dismissed = false
    @Published var checkOnLaunch: Bool {
        didSet { preferences.set(checkOnLaunch, forKey: "updatesCheckOnLaunch") }
    }
    @Published var checkDaily: Bool {
        didSet {
            preferences.set(checkDaily, forKey: "updatesCheckDaily")
            if started { checkDailyIfDue() }
        }
    }
    private let preferences: UserDefaults
    private var started = false
    private var timer: Timer?
    var beforeRestart: (() -> Void)?
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var bannerVisible: Bool { installing || !dismissed && (available != nil || detail != nil || error != nil) }

    init(preferences: UserDefaults) {
        self.preferences = preferences
        checkOnLaunch = preferences.object(forKey: "updatesCheckOnLaunch") as? Bool ?? true
        checkDaily = preferences.object(forKey: "updatesCheckDaily") as? Bool ?? true
        lastCheck = preferences.object(forKey: "updatesLastSuccessfulCheck") as? Date
        if let previousError = preferences.string(forKey: "updateInstallError") {
            error = L10n.tr("A atualização não foi concluída: ") + previousError
            preferences.removeObject(forKey: "updateInstallError")
        }
    }
    func previewAvailable() {
        let tag = "v0.2.0"
        available = AppRelease(tag_name: tag, draft: false, prerelease: false, assets: [])
    }

    func start() {
        guard !started else { return }
        started = true
        // Poll the persisted deadline so sleep/wake and preference changes are respected.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDailyIfDue() }
        }
        if checkOnLaunch { check() }
        else { checkDailyIfDue() }
    }
    func stop() { started = false; timer?.invalidate(); timer = nil }

    private func checkDailyIfDue() {
        guard checkDaily, UpdateCheckSchedule.isDue(
            lastAttempt: preferences.object(forKey: "updatesLastAttempt") as? Date, now: Date()) else { return }
        check()
    }

    func check(manual: Bool = false) {
        guard !checking, !installing else { return }
        preferences.set(Date(), forKey: "updatesLastAttempt")
        checking = true; if manual { error = nil }
        if manual { dismissed = false; detail = "Buscando atualizações…" }
        Task { @MainActor in
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("VitraRadio", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else {
                    throw AppUpdateError(message: L10n.tr("Não foi possível consultar as atualizações. Tente novamente em instantes."))
                }
                let release = try AppRelease.newer(from: data, current: currentVersion)
                lastCheck = Date()
                preferences.set(lastCheck, forKey: "updatesLastSuccessfulCheck")
                if release != nil || release?.tag_name != available?.tag_name { dismissed = false }
                available = release
                detail = release == nil ? (manual ? "Você está usando a versão mais recente." : nil) : nil
            } catch {
                if manual { self.error = error.localizedDescription; detail = nil }
            }
        }
    }

    func install() {
        guard let release = available, !installing, !checking else { return }
        installing = true; error = nil; dismissed = false; detail = "Baixando atualização…"
        Task { @MainActor in
            let fm = FileManager.default
            let workspace = fm.temporaryDirectory.appendingPathComponent("vitra-update-\(UUID().uuidString)", isDirectory: true)
            var prepared: UpdateInstallPlan?
            do {
                try fm.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let archive = try await download(release.asset(UpdateInstaller.assetName, maximum: 150_000_000), to: workspace)
                let sums = try await download(release.asset("SHA256SUMS.txt", maximum: 100_000), to: workspace)
                let checksums = try String(contentsOf: sums, encoding: .utf8)
                detail = "Verificando e preparando a atualização…"
                let target = Bundle.main.bundleURL.standardizedFileURL
                let plan = try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.prepare(archive: archive, checksums: checksums, version: release.version, target: target, workspace: workspace)
                }.value
                prepared = plan
                detail = "Reiniciando o Vitra Radio…"
                try UpdateInstaller.startHelper(plan)
                beforeRestart?()
                NSApp.terminate(nil)
            } catch {
                if let prepared { try? fm.removeItem(at: prepared.staged) }
                try? fm.removeItem(at: workspace)
                installing = false; detail = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func download(_ asset: AppRelease.Asset, to folder: URL) async throws -> URL {
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 180
        request.setValue("VitraRadio", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = response.url, url.scheme == "https", let host = url.host,
              host == "github.com" || host.hasSuffix(".githubusercontent.com"),
              try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == asset.size else {
            throw AppUpdateError(message: L10n.tr("O download não terminou corretamente. Tente novamente."))
        }
        let destination = folder.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
