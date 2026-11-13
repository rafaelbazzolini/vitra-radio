import AppKit
import SwiftUI
import Combine

// Os controles respondem já no primeiro clique, mesmo com outro app em foco.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

// A janela principal é persistente: o botão vermelho nunca destrói o player.
final class MainPlayerWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2, !styleMask.contains(.fullScreen),
           let contentView, event.locationInWindow.y >= contentView.bounds.maxY - 32,
           event.locationInWindow.x >= 85 {
            performZoom(nil)
            return
        }
        super.sendEvent(event)
    }
    override func close() { orderOut(nil) }
}

final class DockSidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Permite aproveitar a faixa vazia ao lado da Dock, fora do visibleFrame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let radio: RadioPlayer
    let servers: MusicServerStore
    let onlineMusic: OnlineMusicStore
    let podcasts: PodcastStore
    let countries: CatalogCountries
    let scheduler: RadioAutomationStore
    @Published var accentColorHex: UInt32? {
        didSet {
            if !preview {
                if let accentColorHex { preferences.set(Int(accentColorHex), forKey: "accentColorHex") }
                else { preferences.removeObject(forKey: "accentColorHex") }
            }
        }
    }
    @Published var vuStyle: VUStyle { didSet { if !preview { preferences.set(vuStyle.rawValue, forKey: "vuStyle") } } }
    @Published var playerSkin: PlayerSkin {
        didSet {
            if !preview { preferences.set(playerSkin.rawValue, forKey: "playerSkin") }
            applyWindowTheme()
        }
    }
    @Published var miniAppearance: MiniAppearance {
        didSet { if !preview { preferences.set(miniAppearance.rawValue, forKey: "miniAppearance") } }
    }
    @Published var miniVUStyle: VUStyle { didSet { if !preview { preferences.set(miniVUStyle.rawValue, forKey: "miniVUStyle") } } }
    @Published var compactMini: Bool
    @Published private(set) var miniSize: CGSize
    private var mainWindow: NSWindow!
    private var mini: DockSidePanel?
    let updateChecker: UpdateChecker
    private let animatedIcon = AnimatedAppIcon()
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private let preferences: UserDefaults
    private let preview: Bool
    private var automatedPlayback: (rule: UUID, intent: UUID)?
    private var exitRequested = false
    private var needsDockFit: Bool

    init(preferences: UserDefaults = .standard, preview: Bool = false) {
        self.preferences = preferences
        self.preview = preview
        AppLocalization.shared.configure(preferences: preferences, preferred: preview ? (CommandLine.arguments.contains("--english-preview") ? ["en"] : ["pt-BR"]) : Locale.preferredLanguages)
        self.updateChecker = UpdateChecker(preferences: preferences)
        self.podcasts = PodcastStore(preferences: preferences)
        self.onlineMusic = OnlineMusicStore(preferences: preferences)
        self.countries = CatalogCountries(preferences: preferences, preview: preview)
        self.scheduler = RadioAutomationStore(preferences: preferences)
        let savedAccent = preferences.object(forKey: "accentColorHex") as? NSNumber
        self.accentColorHex = savedAccent.flatMap { (0...0xFFFFFF).contains($0.int64Value) ? UInt32($0.int64Value) : nil }
        self.vuStyle = VUStyle(rawValue: preferences.string(forKey: "vuStyle") ?? "") ?? .off
        self.playerSkin = PlayerSkin(rawValue: preferences.string(forKey: "playerSkin") ?? "") ?? .vitra
        self.miniVUStyle = VUStyle(rawValue: preferences.string(forKey: "miniVUStyle") ?? "") ?? .off
        self.miniAppearance = MiniAppearance(rawValue: preferences.string(forKey: "miniAppearance") ?? "") ?? .solid
        self.needsDockFit = preferences.object(forKey: "miniWidth") == nil
        self.radio = RadioPlayer(preferences: preferences, updatesSystemMedia: !preview)
        self.servers = MusicServerStore(preferences: preferences, vault: preview ? MemoryMusicVault() : KeychainMusicVault())
        let isCompact = preferences.object(forKey: "compactMini") == nil || preferences.bool(forKey: "compactMini")
        compactMini = isCompact
        let defaultSize = isCompact ? CGSize(width: 280, height: 64) : CGSize(width: 326, height: 134)
        miniSize = MiniSizing.clamped(preferences.object(forKey: "miniWidth") == nil ? defaultSize : CGSize(width: preferences.double(forKey: "miniWidth"), height: preferences.double(forKey: "miniHeight")))
        super.init()
        radio.$podcastEpisode.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.makeMenu() } }.store(in: &subscriptions)
        radio.onPodcastProgress = { [weak podcasts] id, seconds, completed in podcasts?.record(id: id, seconds: seconds, completed: completed) }
        if preview && (CommandLine.arguments.contains("--online-music-preview") || CommandLine.arguments.contains("--online-playlists-preview")) { onlineMusic.preview() }
        if preview && CommandLine.arguments.contains("--podcasts-preview") { podcasts.preview(episodes: CommandLine.arguments.contains("--podcast-episodes-preview")) }
        AppLocalization.shared.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.statusItem != nil else { return }
                self.makeMenu()
                self.makeStatusItem()
                self.objectWillChange.send()
            }
        }.store(in: &subscriptions)
        if preview && CommandLine.arguments.contains("--updates-preview") { updateChecker.previewAvailable() }
        if preview && CommandLine.arguments.contains("--vu-preview") { vuStyle = .digital }
        if preview && CommandLine.arguments.contains("--vu-modern-preview") { vuStyle = .modern }
        if preview && CommandLine.arguments.contains("--vu-analog-preview") { vuStyle = .analog }
        if preview && CommandLine.arguments.contains("--automation-preview") {
            for (hour, station) in [(9, Station.all[0]), (14, Station.all[2]), (18, Station.all[3])] {
                _ = scheduler.save(RadioAutomation(station: Station.Saved(station), weekdays: [2,3,4,5,6], hour: hour, minute: 0))
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessInfo.processInfo.disableAutomaticTermination("Player de áudio na barra de menus")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        makeMenu()
        makeMainWindow()
        makeStatusItem()
        if !preview {
            scheduler.start(finish: { [weak self] rule in
                guard let self, self.automatedPlayback?.rule == rule.id,
                      self.automatedPlayback?.intent == self.radio.playbackIntentID else { return }
                self.radio.pause()
                self.automatedPlayback = nil
            }, canResume: { [weak self] rule in
                guard let self else { return false }
                return self.automatedPlayback?.rule == rule.id && self.automatedPlayback?.intent == self.radio.playbackIntentID
            }, fire: { [weak self] rule in
                guard let self, let station = rule.station.station else { return }
                self.radio.select(station)
                self.automatedPlayback = (rule.id, self.radio.playbackIntentID)
                self.recordLifecycle("automação aplicada: \(rule.station.name) [\(rule.periodLabel)]")
            })
        }
        if !preview {
            updateChecker.beforeRestart = { [weak self] in
                guard let self else { return }
                self.preferences.set(self.radio.state.isPlaying && self.radio.selected.isLive, forKey: "resumeAfterUpdate")
            }
            updateChecker.start()
            if preferences.bool(forKey: "resumeAfterUpdate") {
                preferences.removeObject(forKey: "resumeAfterUpdate")
                radio.play()
            }
        }
        recordLifecycle("iniciado")
        radio.$state.sink { [weak self] state in
            self?.statusItem?.button?.toolTip = "Vitra Radio · \(state.label)"
            guard let self else { return }
            if !self.preview { self.animatedIcon.setPlaying(state == .playing) }
        }.store(in: &subscriptions)
        radio.$alwaysOnTop.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updatePanelLevel() }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restoreMiniPosition() }
        }
        if !preview && preferences.bool(forKey: "miniVisible") { showMini(hidingMain: true) }
        else { showMain() }

        if CommandLine.arguments.contains("--server-preview") || CommandLine.arguments.contains("--themes-preview") || CommandLine.arguments.contains("--automation-preview") { showMain() }

        if preview {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if CommandLine.arguments.contains("--verify-language") { self.verifyLanguage() }
                else if CommandLine.arguments.contains("--verify-titlebar") { self.verifyTitlebar() }
                else if CommandLine.arguments.contains("--verify-theme-menu") { self.verifyThemeMenu() }
                else if CommandLine.arguments.contains("--verify-mini") { self.verifyMiniInteractions() }
                else { self.exportPreviews() }
            }
        }
    }

    private func verifyLanguage() {
        Task { @MainActor in
            @MainActor func themeButton(_ view: NSView?) -> NSButton? {
                guard let view else { return nil }
                if let button = view as? NSButton, ["Trocar tema", "Change theme"].contains(button.accessibilityLabel() ?? "") { return button }
                return view.subviews.lazy.compactMap { themeButton($0) }.first
            }
            @MainActor func hasMenu(_ title: String) -> Bool {
                @MainActor func contains(_ menu: NSMenu?) -> Bool {
                    menu?.items.contains { $0.title == title || contains($0.submenu) } ?? false
                }
                return contains(NSApp.mainMenu)
            }
            let initialStation = radio.selected.id
            let initialFavorites = radio.favorites
            let folder = ProcessInfo.processInfo.environment["VITRA_PREVIEW_DIR"] ?? NSTemporaryDirectory() + "vitra-language-verification"
            do {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                showMini(hidingMain: false)
                try? await Task.sleep(nanoseconds: 300_000_000)
                try snapshot(window: mainWindow, to: folder + "/portuguese.png")
                let portuguese = hasMenu("Sair do Vitra Radio") && themeButton(mainWindow.contentView)?.accessibilityLabel() == "Trocar tema"
                AppLocalization.shared.select(.english)
                try? await Task.sleep(nanoseconds: 500_000_000)
                try snapshot(window: mainWindow, to: folder + "/english.png")
                let english = hasMenu("Quit Vitra Radio") && themeButton(mainWindow.contentView)?.accessibilityLabel() == "Change theme"
                let changed = try Data(contentsOf: URL(fileURLWithPath: folder + "/portuguese.png")) != Data(contentsOf: URL(fileURLWithPath: folder + "/english.png"))
                AppLocalization.shared.select(.portuguese)
                try? await Task.sleep(nanoseconds: 300_000_000)
                let restored = hasMenu("Sair do Vitra Radio") && themeButton(mainWindow.contentView)?.accessibilityLabel() == "Trocar tema"
                let preserved = radio.selected.id == initialStation && radio.favorites == initialFavorites && radio.state == .idle && mini?.isVisible == true
                for (passed, label) in [(portuguese, "Interface e menus iniciam em português"), (english, "Seletor nativo e menus mudam para inglês sem reiniciar"), (changed, "Janela SwiftUI renderiza a tradução ao vivo"), (restored, "Menus e controles retornam ao português"), (preserved, "Troca preserva estação, favoritas, áudio e miniplayer")] {
                    print("\(passed ? "PASS" : "FAIL"): \(label)")
                }
                fflush(stdout)
                exit(portuguese && english && changed && restored && preserved ? 0 : 1)
            } catch { print("FAIL: \(error)"); fflush(stdout); exit(1) }
        }
    }

    private func verifyTitlebar() {
        mainWindow.setFrame(NSRect(x: 100, y: 100, width: 1060, height: 760), display: true)
        let original = mainWindow.frame
        func doubleClick() {
            let point = NSPoint(x: 250, y: mainWindow.contentView!.bounds.maxY - 14)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: mainWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
            mainWindow.sendEvent(event)
        }
        doubleClick()
        let maximized = mainWindow.frame != original
        doubleClick()
        let restored = mainWindow.frame == original
        print("\(maximized ? "PASS" : "FAIL"): duplo clique amplia a janela")
        print("\(restored ? "PASS" : "FAIL"): segundo duplo clique restaura o tamanho anterior")
        fflush(stdout)
        exit(maximized && restored ? 0 : 1)
    }

    private func verifyThemeMenu() {
        func findButton(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.accessibilityLabel() == "Trocar tema" { return button }
            return view.subviews.lazy.compactMap { findButton($0) }.first
        }
        guard playerSkin == .vitra, let content = mainWindow.contentView, let button = findButton(content) else {
            print("FAIL: botão nativo no tema padrão"); fflush(stdout); exit(1)
        }
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: content.superview)
        let hit = content.hitTest(point)
        let clickable = hit === button || hit?.isDescendant(of: button) == true
        if !clickable { print("HIT: button=\(button.frame) point=\(point) hit=\(String(describing: hit))") }
        final class MenuProbe: @unchecked Sendable { var panel: NSPopover? }
        let probe = MenuProbe()
        let observer = NotificationCenter.default.addObserver(forName: .init("VitraThemePickerOpened"), object: nil, queue: .main) { notification in
            probe.panel = notification.object as? NSPopover
        }
        button.performClick(nil)
        NotificationCenter.default.removeObserver(observer)
        let opened = probe.panel?.isShown == true
        (probe.panel?.delegate as? ThemePickerControlling)?.chooseTheme(PlayerSkin.allCases[1])
        let switched = playerSkin == PlayerSkin.allCases[1]
        print("\(clickable ? "PASS" : "FAIL"): clique alcança o seletor no tema padrão")
        print("\(opened ? "PASS" : "FAIL"): lista personalizada abriu")
        print("\(switched ? "PASS" : "FAIL"): escolha altera o tema")
        fflush(stdout)
        exit(clickable && opened && switched ? 0 : 1)
    }

    private func makeMainWindow() {
        mainWindow = MainPlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mainWindow.title = "Vitra Radio"
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.isReleasedWhenClosed = false
        mainWindow.backgroundColor = NSColor(red: 0.06, green: 0.08, blue: 0.065, alpha: 1)
        mainWindow.contentMinSize = NSSize(width: 1000, height: 710)
        mainWindow.contentView = ClickableHostingView(rootView: RadioView().environmentObject(onlineMusic).environmentObject(podcasts).defaultAppStorage(preferences).environment(\.locale, AppLocalization.shared.language.locale).environmentObject(countries).environmentObject(updateChecker).environmentObject(radio).environmentObject(self).environmentObject(servers).environmentObject(scheduler))
        mainWindow.delegate = self
        mainWindow.standardWindowButton(.closeButton)?.target = self
        mainWindow.standardWindowButton(.closeButton)?.action = #selector(hideMainWindow)
        applyWindowTheme()
        mainWindow.center()
        if !preview { mainWindow.setFrameAutosaveName("VitraRadioMain") }
    }

    private func applyWindowTheme() {
        guard let mainWindow else { return }
        mainWindow.appearance = NSAppearance(named: playerSkin == .studio ? .aqua : .darkAqua)
        mainWindow.backgroundColor = NSColor(AppPalette(skin: playerSkin).background)
    }

    func showMain() {
        mainWindow.deminiaturize(nil)
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMini(hidingMain: Bool = false) {
        if mini == nil {
            let panel = DockSidePanel(contentRect: NSRect(origin: .zero, size: miniSize), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let hosting = ClickableHostingView(rootView: MiniPlayerView().defaultAppStorage(preferences).environment(\.locale, AppLocalization.shared.language.locale).environmentObject(radio).environmentObject(self))
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.contentMinSize = MiniSizing.minimum
            panel.contentMaxSize = MiniSizing.maximum
            panel.delegate = self
            mini = panel
            restoreMiniPosition()
        }
        updatePanelLevel()
        if needsDockFit { needsDockFit = false; fitMiniToDock() }
        mini?.orderFrontRegardless()
        radio.miniVisible = true
        preferences.set(true, forKey: "miniVisible")
        if hidingMain { mainWindow.orderOut(nil) }
    }

    func hideMini() {
        mini?.orderOut(nil)
        radio.miniVisible = false
        preferences.set(false, forKey: "miniVisible")
    }

    func toggleCompactMini() {
        compactMini.toggle()
        preferences.set(compactMini, forKey: "compactMini")
        setMiniSize(compactMini ? CGSize(width: 280, height: 64) : CGSize(width: 326, height: 134))
    }

    func setMiniSize(_ size: CGSize, top: CGFloat? = nil) {
        let size = MiniSizing.clamped(size)
        miniSize = size
        if let mini {
            let origin = CGPoint(x: mini.frame.minX, y: top.map { $0 - size.height } ?? mini.frame.minY)
            mini.setFrame(CGRect(origin: origin, size: size), display: true)
            clampMiniToScreen()
        }
        saveMiniSize()
    }

    func fitMiniToDock() {
        guard let screen = mini?.screen ?? NSScreen.main else { return }
        compactMini = true
        preferences.set(true, forKey: "compactMini")
        setMiniSize(CGSize(width: max(260, miniSize.width), height: MiniSizing.dockHeight(on: screen)))
        let y = MiniSizing.dockFrame(on: screen)?.minY ?? screen.frame.minY + 8
        if let mini { mini.setFrameOrigin(CGPoint(x: mini.frame.minX, y: y)); clampMiniToScreen() }
    }

    private func saveMiniSize() {
        guard !preview else { return }
        preferences.set(miniSize.width, forKey: "miniWidth")
        preferences.set(miniSize.height, forKey: "miniHeight")
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        sender === mini ? MiniSizing.clamped(frameSize) : frameSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mini else { return }
        let size = MiniSizing.clamped(window.frame.size)
        if miniSize != size { miniSize = size }
        saveMiniSize()
    }

    func updatePanelLevel() { mini?.level = radio.alwaysOnTop ? .floating : .normal }

    func positionMini(right: Bool) {
        guard let mini, let screen = mini.screen ?? NSScreen.main else { return }
        let frame = screen.frame
        let visible = screen.visibleFrame
        // Com a Dock na lateral, respeita a borda disponível nesse lado.
        let left = visible.minX > frame.minX + 5 ? visible.minX : frame.minX
        let rightEdge = visible.maxX < frame.maxX - 5 ? visible.maxX : frame.maxX
        let x = right ? rightEdge - miniSize.width - 16 : left + 16
        mini.setFrameOrigin(CGPoint(x: x, y: frame.minY + 14))
        saveMiniPosition()
    }

    private func restoreMiniPosition() {
        guard mini != nil else { return }
        if preferences.object(forKey: "miniX") != nil {
            let origin = CGPoint(x: preferences.double(forKey: "miniX"), y: preferences.double(forKey: "miniY"))
            mini?.setFrameOrigin(MiniPlacement.clamped(origin, size: miniSize, screens: NSScreen.screens.map(\.frame)))
        } else { positionMini(right: true) }
    }

    private func clampMiniToScreen() {
        guard let mini else { return }
        mini.setFrameOrigin(MiniPlacement.clamped(mini.frame.origin, size: miniSize, screens: NSScreen.screens.map(\.frame)))
        saveMiniPosition()
    }

    private func saveMiniPosition() {
        guard !preview, let mini else { return }
        preferences.set(mini.frame.minX, forKey: "miniX")
        preferences.set(mini.frame.minY, forKey: "miniY")
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mini { saveMiniPosition() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Closing a window is handled separately. Every application quit request,
        // including Dock, logout, restart and shutdown, must be allowed to finish.
        recordLifecycle("encerramento autorizado explicit=\(exitRequested)")
        return .terminateNow
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuItem("Abrir Vitra Radio", action: #selector(openMain)))
        menu.addItem(menuItem("Mostrar miniplayer", action: #selector(openMini)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Sair do Vitra Radio", action: #selector(quit)))
        return menu
    }

    private func recordLifecycle(_ action: String) {
        guard !preview else { return }
        var events = preferences.stringArray(forKey: "lifecycleDiagnostics") ?? []
        events.append("\(Date().ISO8601Format()) pid=\(ProcessInfo.processInfo.processIdentifier) \(action) audio=\(radio.active) state=\(radio.state.label) mini=\(radio.miniVisible)")
        preferences.set(Array(events.suffix(30)), forKey: "lifecycleDiagnostics")
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordLifecycle("finalizando")
        saveMiniPosition()
        animatedIcon.stop()
        scheduler.stop()
        updateChecker.stop()
        radio.shutdown()
        servers.disconnect()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func makeStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: L10n.tr("Vitra Radio — abrir player"))
        item.button?.title = ""
        item.length = NSStatusItem.squareLength
        item.button?.image?.isTemplate = true
        item.button?.toolTip = L10n.tr("Vitra Radio · clique para abrir o player")
        let menu = NSMenu()
        menu.addItem(menuItem("Abrir Vitra Radio", action: #selector(openMain)))
        menu.addItem(menuItem("Mostrar miniplayer", action: #selector(openMini)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Reproduzir / Pausar", action: #selector(togglePlayback)))
        for (index, station) in Station.all.enumerated() {
            let entry = menuItem(station.name, action: #selector(selectStation(_:)))
            entry.tag = index
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Sair do Vitra Radio", action: #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let label = radio.isPodcast ? (title == "Rádio anterior" ? "Voltar 15 segundos" : title == "Próxima rádio" ? "Avançar 15 segundos" : title) : title
        let item = NSMenuItem(title: L10n.tr(label), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(menuItem("Sobre o Vitra Radio", action: #selector(about)))
        applicationMenu.addItem(.separator())
        let hide = NSMenuItem(title: L10n.tr("Ocultar Vitra Radio"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(hide)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem("Verificar atualizações…", action: #selector(checkUpdates)))
        applicationMenu.addItem(menuItem("Sair do Vitra Radio", action: #selector(quit), key: "q"))
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let playbackItem = NSMenuItem()
        playbackItem.title = L10n.tr("Reprodução")
        let playback = NSMenu(title: L10n.tr("Reprodução"))
        playback.addItem(menuItem("Reproduzir / Pausar", action: #selector(togglePlayback), key: "p"))
        playback.addItem(menuItem("Próxima rádio", action: #selector(nextStation), key: String(UnicodeScalar(NSRightArrowFunctionKey)!)))
        playback.addItem(menuItem("Rádio anterior", action: #selector(previousStation), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        playbackItem.submenu = playback
        mainMenu.addItem(playbackItem)

        // Menu Editar mantém atalhos nativos de busca, copiar e colar.
        let editItem = NSMenuItem()
        editItem.title = L10n.tr("Editar")
        let edit = NSMenu(title: L10n.tr("Editar"))
        for (title, selector, key) in [("Recortar", #selector(NSText.cut(_:)), "x"), ("Copiar", #selector(NSText.copy(_:)), "c"), ("Colar", #selector(NSText.paste(_:)), "v"), ("Selecionar tudo", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: L10n.tr(title), action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        windowItem.title = L10n.tr("Janela")
        let windowMenu = NSMenu(title: L10n.tr("Janela"))
        windowMenu.addItem(menuItem("Janela completa", action: #selector(openMain), key: "1"))
        let miniItem = menuItem("Miniplayer", action: #selector(openMini), key: "m")
        miniItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(miniItem)
        windowMenu.addItem(menuItem("Alternar tamanho do miniplayer", action: #selector(toggleMiniSize)))
        windowMenu.addItem(menuItem("Miniplayer à direita da Dock", action: #selector(moveMiniRight)))
        windowMenu.addItem(menuItem("Miniplayer à esquerda da Dock", action: #selector(moveMiniLeft)))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func hideMainWindow() {
        recordLifecycle("botão vermelho: ocultar janela")
        mainWindow.orderOut(nil)
    }
    @objc private func openMain() { showMain() }
    @objc private func openMini() { showMini() }
    @objc private func togglePlayback() { radio.toggle() }
    @objc private func nextStation() { radio.step(1) }
    @objc private func previousStation() { radio.step(-1) }
    @objc private func toggleMiniSize() { if mini == nil { showMini() }; toggleCompactMini() }
    @objc private func moveMiniRight() { showMini(); positionMini(right: true) }
    @objc private func moveMiniLeft() { showMini(); positionMini(right: false) }
    @objc private func selectStation(_ sender: NSMenuItem) { radio.select(Station.all[sender.tag]) }
    @objc private func checkUpdates() { showMain(); updateChecker.check(manual: true) }

    @objc private func quit() {
        exitRequested = true
        recordLifecycle("Sair solicitado")
        NSApp.terminate(nil)
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Vitra Radio", .applicationVersion: updateChecker.currentVersion,
            .credits: NSAttributedString(string: L10n.tr("Sua frequência. Seu espaço.\nBiblioteca privada no seu dispositivo.\n\nArraste o miniplayer pela alça pontilhada.\nClique com o botão direito para tamanho e posição.")),
            .version: "1"
        ])
    }

    private func verifyMiniInteractions() {
        showMain()
        showMini()
        guard let panel = mini else { exit(1) }
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            for child in view.subviews { if let match = find(type, in: child) { return match } }
            return nil
        }
        func gesture(_ view: NSView, delta: CGPoint) {
            let start = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
            NSApp.postEvent(event(.leftMouseDragged, end), atStart: false)
            NSApp.postEvent(event(.leftMouseUp, end), atStart: false)
            view.mouseDown(with: event(.leftMouseDown, start))
        }
        setMiniSize(CGSize(width: 280, height: 64))
        panel.setFrameOrigin(CGPoint(x: 100, y: 200))
        panel.contentView?.layoutSubtreeIfNeeded()
        check(mainWindow.isVisible && panel.isVisible, "Exibir miniplayer mantém a janela principal aberta")
        if let grip = find(DragHandle.HandleView.self, in: panel.contentView!) {
            gesture(grip, delta: CGPoint(x: 40, y: 30))
            check(abs(panel.frame.minX - 140) < 1 && abs(panel.frame.minY - 230) < 1, "Arraste nativo move o miniplayer")
        } else { check(false, "Alça de movimento presente") }
        if let handle = find(MiniResizeHandle.HandleView.self, in: panel.contentView!) {
            gesture(handle, delta: CGPoint(x: 80, y: 36))
            check(abs(panel.frame.minY - 230) < 1, "Redimensionar pelo canto superior preserva a base")
            check(panel.frame.size == CGSize(width: 360, height: 100), "Canto redimensiona livremente nos dois eixos")
            gesture(handle, delta: CGPoint(x: 1000, y: 1000))
            check(panel.frame.size == MiniSizing.maximum, "Arraste respeita o tamanho máximo")
            gesture(handle, delta: CGPoint(x: -1000, y: -1000))
            check(panel.frame.size == MiniSizing.minimum, "Arraste respeita o tamanho mínimo")
        } else { check(false, "Canto de redimensionamento presente") }
        showMini(hidingMain: true)
        check(panel.isVisible && NSApp.isRunning, "Ocultar a janela principal mantém o miniplayer e o app ativos")
        mainWindow.standardWindowButton(.closeButton)?.performClick(nil)
        check(!mainWindow.isVisible && panel.isVisible && NSApp.isRunning, "Fechar a janela preserva o miniplayer aberto")
        hideMini()
        showMain()
        mainWindow.standardWindowButton(.closeButton)?.performClick(nil)
        check(!mainWindow.isVisible && !panel.isVisible && NSApp.isRunning, "Fechar a janela com mini oculto mantém o app na barra de menus")
        check(!radio.miniVisible, "Fechar a janela não abre o miniplayer")
        check(!applicationShouldTerminateAfterLastWindowClosed(NSApp), "Fechar a última janela não encerra o app")
        check(applicationShouldTerminate(NSApp) == .terminateNow, "Encerrar pela Dock ou pelo macOS é permitido sem comando do menu interno")
        exitRequested = true
        check(applicationShouldTerminate(NSApp) == .terminateNow, "Sair explícito continua encerrando o aplicativo")
        print("MINI_INTERACTIONS_OK: \(failures) falhas")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    private func exportPreviews() {
        let folder = ProcessInfo.processInfo.environment["VITRA_PREVIEW_DIR"] ?? FileManager.default.currentDirectoryPath + "/dist/previews"
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try snapshot(window: mainWindow, to: folder + "/main.png")
            if let sheet = mainWindow.attachedSheet { try snapshot(window: sheet, to: folder + "/form.png") }
            showMini()
            mini?.contentView?.layoutSubtreeIfNeeded()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                do {
                    try self.snapshot(window: self.mini!, to: folder + "/mini-compact.png")
                    self.toggleCompactMini()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    try self.snapshot(window: self.mini!, to: folder + "/mini-expanded.png")
                    self.setMiniSize(CGSize(width: 280, height: 44))
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    try self.snapshot(window: self.mini!, to: folder + "/mini-44.png")
                    self.fitMiniToDock()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    try self.snapshot(window: self.mini!, to: folder + "/mini-dock.png")
                    for skin in PlayerSkin.allCases {
                        self.playerSkin = skin
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                        try self.snapshot(window: self.mainWindow, to: folder + "/app-\(skin.rawValue).png")
                        for height in [64, 160] {
                            self.setMiniSize(CGSize(width: 350, height: height))
                            try? await Task.sleep(nanoseconds: 1_100_000_000)
                            try self.snapshot(window: self.mini!, to: folder + "/skin-\(skin.rawValue)-\(height).png")
                        }
                    }
                    print("PREVIEW_OK: \(folder)")
                    fflush(stdout)
                    exit(0)
                } catch { fputs("PREVIEW_FAILED: \(error)\n", stderr); exit(1) }
            }
        } catch {
            fputs("PREVIEW_FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private func snapshot(window: NSWindow, to path: String) throws {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "VitraPreview", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "VitraPreview", code: 2) }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
