import SwiftUI

struct AppPalette {
    var skin: PlayerSkin = .vitra
    var accentOverride: UInt32? = nil
    var onAccent: Color { skin.design.overridingAccent(accentOverride).onAccent }
    var background: Color { Color(hex: skin == .vitra ? 0x101411 : skin.design.background) }
    var sidebar: Color { Color(hex: skin == .vitra ? 0x151A17 : skin.design.background) }
    var surface: Color { Color(hex: skin == .vitra ? 0x1C231E : skin.design.panel) }
    var text: Color { skin.design.ink }
    var muted: Color { skin == .vitra ? Color(hex: 0x8D9A90) : skin.design.secondary }
    var accent: Color { skin.design.overridingAccent(accentOverride).highlight }
    var line: Color { text.opacity(0.10) }
}
private struct AppPaletteKey: EnvironmentKey { static let defaultValue = AppPalette() }
extension EnvironmentValues {
    var appPalette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}

struct RadioView: View {
    @EnvironmentObject private var app: AppController
    var body: some View {
        Group {
            if app.playerSkin == .vitra { ClassicRadioView() }
            else { ThemedRadioWindow(skin: app.playerSkin) }
        }.environment(\.appPalette, AppPalette(skin: app.playerSkin, accentOverride: app.accentColorHex))
            .environment(\.colorScheme, app.playerSkin == .studio ? .light : .dark)
            .tint(app.playerSkin.design.overridingAccent(app.accentColorHex).highlight)
    }
}

enum ThemePage: String, CaseIterable, Identifiable {
    case explore = "Início", catalog = "Todas as rádios", server = "Meu servidor", themes = "Temas", automation = "Automação"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .explore: return "house.fill"
        case .catalog: return "dot.radiowaves.left.and.right"
        case .server: return "server.rack"
        case .themes: return "paintpalette"
        case .automation: return "calendar.badge.clock"
        }
    }
}

struct ThemedRadioWindow: View {
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var radio: RadioPlayer
    @StateObject private var catalog = RadioCatalog()
    @State private var page: ThemePage = .explore
    @State private var search = ""
    @State private var radioSection: HomeRadioSection = .favorites
    let skin: PlayerSkin
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    private var stations: [Station] {
        (radioSection == .favorites ? radio.favoriteStations : radio.recentStations).filter { search.isEmpty || "\($0.name) \($0.genre)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            titlebar
            HStack(spacing: 7) { ForEach(ThemePage.allCases) { tab in navigation(tab) }; Spacer() }
                .padding(.horizontal, 22).padding(.vertical, 9)
            workspace
            footer
        }.background { SkinSurface(skin: skin) }.foregroundStyle(design.ink)
            .preferredColorScheme(skin == .studio ? .light : .dark)
            .frame(minWidth: 1000, minHeight: 710)
            .onAppear {
                if CommandLine.arguments.contains("--automation-preview") { page = .automation }
                if CommandLine.arguments.contains("--themes-preview") { page = .themes }
                if CommandLine.arguments.contains("--server-preview") { page = .server }
                if CommandLine.arguments.contains("--catalog-preview") { page = .catalog }
            }
    }
    private var titlebar: some View {
        HStack(spacing: 14) {
            Text("vitra").font(.system(size: 24, weight: .bold, design: skin == .heritage ? .serif : .rounded))
            Text(design.name.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(design.highlight)
            Spacer()
            if skin == .digital { Text("NETWORK AUDIO RECEIVER / 01").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(design.secondary) }
            ThemeQuickMenu()
            VUStyleMenu()
            Button { app.showMini() } label: { Label("Miniplayer", systemImage: "pip").font(.system(size: 11, weight: .semibold)).padding(8).contentShape(Rectangle()) }.buttonStyle(.plain)
        }.padding(.horizontal, 26).padding(.top, 37).padding(.bottom, 17)
            .background(design.ink.opacity(skin == .studio ? 0.025 : 0.04))
    }
    private func navigation(_ tab: ThemePage) -> some View {
        Button { page = tab } label: {
            Label(tab.rawValue, systemImage: tab.icon).font(.system(size: 11, weight: .semibold, design: design.mono ? .monospaced : .default))
                .padding(.horizontal, 12).padding(.vertical, 10).frame(alignment: .leading)
                .foregroundStyle(page == tab ? design.highlight : design.secondary)
                .background(page == tab ? Color(hex: design.panel) : .clear, in: RoundedRectangle(cornerRadius: skin == .digital ? 3 : 8))
                .overlay(RoundedRectangle(cornerRadius: skin == .digital ? 3 : 8).strokeBorder(page == tab ? design.highlight.opacity(0.35) : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var workspace: some View {
        switch page {
        case .catalog: CatalogView(catalog: catalog).background(Color(hex: design.panel).opacity(0.35))
        case .server: MusicServerView().background(Color(hex: design.panel).opacity(0.35))
        case .automation: AutomationView().background(Color(hex: design.panel).opacity(0.35))
        case .themes: PlayerThemesView().background(Color(hex: design.panel).opacity(0.35))
        case .explore:
            ScrollView {
                VStack(spacing: 20) {
                    ReceiverConsole(skin: skin)
                    presets
                }.padding(skin == .studio ? 23 : 26)
            }.scrollIndicators(.hidden)
        }
    }
    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HomeRadioTabs(selection: $radioSection)
                Spacer()
                TextField("Buscar", text: $search).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 95).padding(8).background(Color(hex: design.panel), in: RoundedRectangle(cornerRadius: 5))
            }.foregroundStyle(design.secondary)
            if stations.isEmpty { Text(search.isEmpty ? (radioSection == .favorites ? "Adicione favoritas pelo coração de cada rádio." : "As rádios que você ouvir aparecerão aqui, em ordem de reprodução.") : "Nenhuma rádio encontrada.").font(.system(size: 12)).foregroundStyle(design.secondary).padding(.vertical, 20) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 9) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    HStack(spacing: 0) {
                        Button { radio.select(station) } label: {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(design.highlight).frame(width: 23)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(station.name).font(.system(size: 13, weight: .semibold, design: design.mono ? .monospaced : .default)).foregroundStyle(design.ink).lineLimit(1)
                                    Text(station.frequency + " · " + station.genre).font(.system(size: 9)).foregroundStyle(design.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 3)
                                Image(systemName: station == radio.selected && radio.active ? "waveform" : "play.fill").font(.system(size: 11)).foregroundStyle(design.highlight)
                            }.padding(13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        FavoriteButton(station: station).padding(.trailing, 12)
                    }.background(Color(hex: design.panel).opacity(station == radio.selected ? 1 : 0.58), in: RoundedRectangle(cornerRadius: skin == .digital ? 3 : 9))
                        .overlay(RoundedRectangle(cornerRadius: skin == .digital ? 3 : 9).strokeBorder(design.highlight.opacity(station == radio.selected ? 0.5 : 0.08)).allowsHitTesting(false))
                }
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 15) {
            Circle().fill(radio.state.isPlaying ? design.highlight : design.secondary).frame(width: 5, height: 5)
            Text(radio.selected.name).font(.system(size: 11, weight: .semibold))
            Text(radio.state.label).font(.system(size: 10)).foregroundStyle(design.secondary)
            Spacer()
            TimerMenu()
            AudioBalanceMenu()
            Button { radio.muted.toggle() } label: { Image(systemName: radio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).help("Silenciar")
            Slider(value: $radio.volume, in: 0...1).frame(width: 110).accessibilityLabel("Volume")
        }.foregroundStyle(design.ink).padding(.horizontal, 26).padding(.vertical, 13).background(Color(hex: design.panel).opacity(0.65))
    }
}

struct ReceiverConsole: View {
    @EnvironmentObject private var app: AppController
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    let skin: PlayerSkin
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    var body: some View {
        HStack(spacing: 16) {
            if app.vuStyle != .off { LiveVUMeter(style: app.vuStyle, right: false) }
            console.frame(maxWidth: .infinity)
            if app.vuStyle != .off { LiveVUMeter(style: app.vuStyle, right: true) }
        }.padding(16).background { SkinSurface(skin: skin) }
            .clipShape(RoundedRectangle(cornerRadius: design.radius))
            .overlay(RoundedRectangle(cornerRadius: design.radius).strokeBorder(design.highlight.opacity(0.25)).allowsHitTesting(false))
    }
    private var console: some View {
        VStack(spacing: 18) {
            HStack {
                Text(skin == .heritage ? "VITRA • HIGH FIDELITY" : skin == .digital ? "SIGNAL / DIGITAL TUNER" : "STUDIO / RECEIVER").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.8)
                Spacer()
                Text(radio.state.isPlaying ? "● STEREO" : "STANDBY").font(.system(size: 9, weight: .semibold, design: .monospaced))
            }.foregroundStyle(design.secondary)
            HStack(spacing: 22) {
                if skin == .heritage && app.vuStyle == .off { speaker.frame(width: 105) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 20) {
                        Text(radio.selected.isLive ? radio.selected.frequency : "LIBRARY").font(.system(size: skin == .digital ? 34 : 38, weight: .light, design: skin == .heritage ? .serif : .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
                        Spacer()
                        if app.vuStyle == .off { Equalizer(running: radio.state.isPlaying, color: design.highlight).frame(width: 45, height: 24) }
                    }.foregroundStyle(design.highlight)
                    Text(radio.selected.name).font(.system(size: 21, weight: .semibold, design: design.mono ? .monospaced : skin == .heritage ? .serif : .default)).lineLimit(1)
                    Text(radio.selected.genre).font(.system(size: 11)).foregroundStyle(design.secondary).lineLimit(1)
                    RadioDial(skin: skin, frequency: radio.selected.isLive ? FrequencyScale.fm(radio.selected.frequency) : nil, showsLabels: skin == .heritage).padding(.top, 4)
                }.padding(23).background(Color(hex: design.panel), in: RoundedRectangle(cornerRadius: skin == .digital ? 3 : 12))
                    .overlay(RoundedRectangle(cornerRadius: skin == .digital ? 3 : 12).strokeBorder(design.highlight.opacity(0.22)).allowsHitTesting(false))
                if skin == .heritage && app.vuStyle == .off { speaker.frame(width: 105) }
            }
            HStack(spacing: 22) {
                Button { radio.muted.toggle() } label: { Label(radio.muted ? "MUDO" : "SOM", systemImage: radio.muted ? "speaker.slash" : "speaker.wave.2").font(.system(size: 9, weight: .bold)).frame(width: 64, height: 32).background(Color(hex: design.panel), in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle()) }.buttonStyle(.plain)
                Spacer(minLength: 0)
                TransportButtons(playSize: 48, spacing: skin == .digital ? 20 : 30)
                Spacer(minLength: 0)
                if radio.selected.isLive { FavoriteButton(station: radio.selected).frame(width: 64) }
                else { Color.clear.frame(width: 64, height: 1) }
            }.foregroundStyle(design.highlight)
        }.padding(7)
    }
    private var speaker: some View {
        Canvas { context, size in
            for y in stride(from: CGFloat(3), to: size.height, by: 5) {
                for x in stride(from: CGFloat(3), to: size.width, by: 5) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.black.opacity(0.6)))
                }
            }
        }.frame(height: 155).background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}
