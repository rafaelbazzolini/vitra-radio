import SwiftUI
import AppKit

struct ClassicRadioView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    private enum Page { case explore, catalog, podcasts, server, themes, automation, settings }
    @EnvironmentObject private var radio: RadioPlayer
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var servers: MusicServerStore
    @EnvironmentObject private var countries: CatalogCountries
    @State private var page: Page = .explore
    @StateObject private var catalog = RadioCatalog()
    @State private var search = ""
    @State private var radioSection: HomeRadioSection = .favorites
    private var favoritesOnly: Bool { radioSection == .favorites }

    private var stations: [Station] {
        (favoritesOnly ? radio.favoriteStations : radio.recentStations).filter {
            (search.isEmpty || "\($0.name) \($0.genre)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 224)
                Rectangle().fill(palette.line).frame(width: 1)
                if page == .catalog { CatalogView(catalog: catalog) }
                else if page == .podcasts { PodcastsView() }
                else if page == .server { MusicServerView(libraryOnly: true) }
                else if page == .settings { RadioSettingsView() }
                else if page == .themes { PlayerThemesView() }
                else if page == .automation { AutomationView() }
                else { mainContent }
            }
            Rectangle().fill(palette.line).frame(height: 1)
            transport
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 710)
        .onChange(of: countries.needsSetup) { value in if !value && radio.favoriteStations.isEmpty { page = .catalog } }
        .onChange(of: servers.activeProfile?.id) { value in if value == nil && page == .server { page = .settings } }
        .onAppear {
            if CommandLine.arguments.contains("--podcasts-preview") { page = .podcasts }
            if CommandLine.arguments.contains("--settings-preview") { page = .settings }
            if CommandLine.arguments.contains("--catalog-preview") { page = .catalog }
            if CommandLine.arguments.contains("--server-preview") { page = .server }
            if CommandLine.arguments.contains("--themes-preview") { page = .themes }
            if CommandLine.arguments.contains("--automation-preview") { page = .automation }
        }
    }

    private var sidebar: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(size: 35)
                VStack(alignment: .leading, spacing: 1) {
                    Text("vitra").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-1)
                    Text("R A D I O").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.muted)
                }
            }.padding(.bottom, 32)
            Text(L10n.tr("SUA FREQUÊNCIA")).font(.system(size: 9, weight: .bold)).tracking(1.8)
                .foregroundStyle(palette.muted).padding(.leading, 12).padding(.bottom, 13)
            navigationButton("Início", symbol: "house.fill", selected: page == .explore) { page = .explore }
            navigationButton("Todas as rádios", symbol: "dot.radiowaves.left.and.right", selected: page == .catalog) { page = .catalog }
            navigationButton("Podcasts", symbol: "mic.fill", selected: page == .podcasts) { page = .podcasts }
            if servers.activeProfile != nil {
                navigationButton("Minhas músicas", symbol: "music.note.list", selected: page == .server) { page = .server }
            }
            navigationButton("Ajustes", symbol: "gearshape", selected: page == .settings) { page = .settings }
            Rectangle().fill(palette.line).frame(height: 1).padding(.vertical, 14)
            HStack {
                Text(L10n.tr("SUAS RÁDIOS")).font(.system(size: 9, weight: .bold)).tracking(1.8)
                Spacer()
                Text(String(format: "%02d", radio.favoriteStations.count)).font(.system(size: 10, weight: .medium, design: .monospaced))
            }.foregroundStyle(palette.muted).padding(.horizontal, 12).padding(.bottom, 14)
            ForEach(Array(radio.favoriteStations.prefix(4))) { station in
                Button { radio.select(station) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(station.colors[0]).frame(width: 6, height: 6)
                        Text(station.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer()
                        if station == radio.selected && radio.active {
                            Equalizer(running: radio.state.isPlaying, color: palette.accent).frame(width: 16, height: 15)
                        }
                    }.foregroundStyle(station == radio.selected ? palette.text : palette.muted)
                        .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if radio.favoriteStations.isEmpty {
                Text(L10n.tr("Favorite uma rádio para vê-la aqui.")).font(.system(size: 11)).foregroundStyle(palette.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8).fixedSize(horizontal: false, vertical: true)
            }
            if radio.favoriteStations.count > 4 {
                Button(L10n.tr("Ver todas (\(radio.favoriteStations.count))")) { page = .explore; radioSection = .favorites }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 11) {
                Text(L10n.tr("Música por perto.")).font(.system(size: 13, weight: .semibold))
                Button { app.showMini() } label: {
                    HStack {
                        Text(L10n.tr("Abrir miniplayer")).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }.padding(.vertical, 10).padding(.horizontal, 12)
                        .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(palette.accent)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(L10n.tr("Abrir o player flutuante e recolher esta janela (⌘⇧M)"))
            }.padding(15).background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        }.padding(.horizontal, 20).padding(.top, 49).padding(.bottom, 21)
        }.scrollIndicators(.hidden).background(palette.sidebar)
    }

    private func navigationButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 19)
                Text(L10n.tr(title)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.9)
                Spacer()
                if selected { Capsule().fill(palette.accent).frame(width: 3, height: 17) }
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(selected ? palette.accent : palette.muted)
                .background(selected ? palette.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.tr("SINTONIZE O SEU MOMENTO")).font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(palette.muted)
                        Text(L10n.tr("O seu dia tem trilha."))
                            .font(.system(size: 29, weight: .semibold)).tracking(-1.1)
                    }
                    Spacer()
                    SupportProjectButton()
                    ThemeQuickMenu()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12))
                        TextField(L10n.tr("Buscar rádio"), text: $search).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 106)
                            .accessibilityLabel(L10n.tr("Buscar rádio por nome ou estilo"))
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }
                    }.foregroundStyle(palette.muted).padding(11)
                        .background(palette.surface, in: Capsule())
                }
                    .padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 25)
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero
                HStack(alignment: .firstTextBaseline) {
                    HomeRadioTabs(selection: $radioSection)
                    Spacer()
                    Text(L10n.tr("\(stations.count) EMISSORAS")).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(palette.muted)
                }
                if stations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: favoritesOnly ? "heart" : "clock.arrow.circlepath").font(.title2).foregroundStyle(palette.accent)
                        Text(search.isEmpty ? (favoritesOnly ? L10n.tr("Suas favoritas moram aqui.") : L10n.tr("Suas próximas descobertas aparecem aqui.")) : L10n.tr("Nenhuma rádio encontrada.")).font(.headline)
                        Text(search.isEmpty ? (favoritesOnly ? L10n.tr("Toque no coração de uma emissora para guardar.") : L10n.tr("As rádios que você ouvir ficam aqui, da mais recente para a mais antiga.")) : L10n.tr("Experimente buscar pelo nome ou pelo estilo."))
                            .font(.caption).foregroundStyle(palette.muted)
                    }.frame(maxWidth: .infinity).padding(25).background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 13) {
                        ForEach(stations) { StationCard(station: $0) }
                    }
                }
            }.padding(.horizontal, 30).padding(.bottom, 24)
        }.scrollIndicators(.hidden)
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    Circle().fill(radio.state.isPlaying ? palette.accent : radio.selected.colors[0]).frame(width: 5, height: 5)
                    Text(radio.state.isPlaying ? L10n.tr("NO AR AGORA") : L10n.tr("SUA PRÓXIMA COMPANHIA"))
                        .font(.system(size: 8, weight: .bold)).tracking(1.6)
                }.foregroundStyle(palette.accent)
                Text(L10n.tr(radio.selected.tagline)).font(.system(size: 30, weight: .medium)).tracking(-1)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300, alignment: .leading)
                Text(radio.selected.displayDescription).font(.system(size: 11)).foregroundStyle(palette.muted)
                    .lineSpacing(4).frame(maxWidth: 292, alignment: .leading)
                HStack(spacing: 12) {
                    Button { radio.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: radio.active ? "pause.fill" : "play.fill").font(.system(size: 10, weight: .bold))
                            Text(radio.active ? L10n.tr("Pausar rádio") : L10n.tr("Ouvir agora")).font(.system(size: 11, weight: .bold))
                        }.foregroundStyle(palette.onAccent).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(palette.accent, in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Text(radio.selected.displayName).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
                }.padding(.top, 1)
            }.padding(26)
            Spacer(minLength: 0)
            StationArtwork(station: radio.selected, hero: true).frame(width: 245, height: 250).clipped()
        }.frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0x232F25), Color(hex: 0x17221C)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.line).allowsHitTesting(false))
    }

    private var transport: some View {
        HStack(spacing: 18) {
            NowPlayingArtwork().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(radio.selected.displayName).font(.system(size: 13, weight: .semibold))
                PlaybackLabel().font(.system(size: 10))
            }.frame(width: 158, alignment: .leading)
            if radio.selected.isLive { FavoriteButton(station: radio.selected) }
            Spacer(minLength: 12)
            TransportButtons(playSize: 42)
            Spacer(minLength: 12)
            TimerMenu()
            AudioBalanceMenu()
            Rectangle().fill(palette.line).frame(width: 1, height: 24)
            Button { radio.muted.toggle() } label: {
                Image(systemName: radio.muted || radio.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 13)).frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.muted ? L10n.tr("Ativar som") : L10n.tr("Silenciar"))
            Slider(value: $radio.volume, in: 0...1).tint(palette.accent).frame(width: 88).accessibilityLabel("Volume")
            Button { app.showMini() } label: {
                Image(systemName: "pip.enter").font(.system(size: 17)).frame(width: 28, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help("Miniplayer (⌘⇧M)")
        }.padding(.horizontal, 25).frame(height: 86).background(Color(hex: 0x151B17))
    }
}

struct StationCard: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let station: Station
    @EnvironmentObject private var radio: RadioPlayer
    @State private var hovering = false
    private var selected: Bool { radio.selected.id == radio.canonical(station).id }

    var body: some View {
        HStack(spacing: 13) {
            Button { radio.select(station) } label: {
                HStack(spacing: 13) {
                    StationArtwork(station: station).frame(width: 65, height: 65).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(station.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                        Text(station.displayGenre).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                        Text(station.frequency).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.8)
                            .foregroundStyle(selected ? palette.accent : palette.muted.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(L10n.tr("Ouvir \(station.name)"))
            VStack(spacing: 15) {
                FavoriteButton(station: station)
                if selected && radio.active {
                    Equalizer(running: radio.state.isPlaying, color: palette.accent).frame(width: 17, height: 13)
                        .accessibilityLabel(L10n.tr(radio.state.label))
                } else {
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(hovering ? palette.accent : palette.muted.opacity(0.5))
                        .allowsHitTesting(false)
                }
            }
        }.padding(14)
            .background(hovering ? Color(hex: 0x252E26) : palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? palette.accent.opacity(0.38) : palette.line).allowsHitTesting(false))
            .onHover { hovering = $0 }
    }
}

struct BrandMark: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    var size: CGFloat = 35
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31).fill(palette.accent)
            HStack(spacing: size * 0.065) {
                ForEach(Array([0.24, 0.47, 0.64, 0.38, 0.23].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(palette.background).frame(width: size * 0.075, height: size * height)
                }
            }
        }.frame(width: size, height: size)
    }
}

struct StationArtwork: View {
    @ObservedObject private var localization = AppLocalization.shared
    let station: Station
    var hero = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: station.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if hero {
                    ForEach(0..<10) { i in
                        Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
                            .frame(width: side * (0.50 + Double(i) * 0.12), height: side * (0.50 + Double(i) * 0.12))
                            .offset(x: side * 0.24, y: side * 0.03)
                    }
                    Circle().fill(Color(hex: 0x11271C).opacity(0.88)).frame(width: side * 0.70, height: side * 0.70)
                        .overlay {
                            ForEach(0..<6) { i in
                                Circle().stroke(station.colors[0].opacity(0.10), lineWidth: 1)
                                    .padding(CGFloat(i * 7 + 10))
                            }
                        }.rotationEffect(.degrees(-20)).offset(x: side * 0.18)
                    Circle().fill(station.colors[0]).frame(width: side * 0.23, height: side * 0.23)
                        .overlay(Image(systemName: station.symbol).font(.system(size: side * 0.09, weight: .medium)).foregroundStyle(Color(hex: 0x193B29)))
                        .offset(x: side * 0.18)
                    VStack {
                        HStack { Text("VR / 0\((Station.all.firstIndex(of: station) ?? 0) + 1)").tracking(2); Spacer() }
                        Spacer()
                        HStack { Text(station.frequency).tracking(1.5); Spacer(); Image(systemName: "arrow.up.right") }
                    }.font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(Color.black.opacity(0.6)).padding(20)
                } else {
                    ForEach(0..<4) { index in
                        Circle().stroke(Color.white.opacity(0.13), lineWidth: side * 0.015)
                            .frame(width: side * (0.64 + Double(index) * 0.3))
                            .offset(x: side * 0.27, y: side * 0.20)
                    }
                    Image(systemName: station.symbol).font(.system(size: side * 0.37, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.70))
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct Equalizer: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let running: Bool
    var color: Color = Color(hex: 0xC3F47A)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !running || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4) { index in
                        let value = running ? 0.28 + abs(sin(time * 3.5 + Double(index) * 1.7)) * 0.72 : 0.24
                        Capsule().fill(color).frame(width: max(2, (geo.size.width - 6) / 4), height: geo.size.height * value)
                    }
                }.frame(height: geo.size.height)
            }
        }.accessibilityHidden(true)
    }
}

struct FavoriteButton: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let station: Station
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        Button { radio.toggleFavorite(station) } label: {
            Image(systemName: radio.isFavorite(station) ? "heart.fill" : "heart")
                .font(.system(size: 12)).foregroundStyle(radio.isFavorite(station) ? palette.accent : palette.muted)
                .frame(width: 23, height: 23).contentShape(Rectangle())
        }.buttonStyle(.plain).help(radio.isFavorite(station) ? L10n.tr("Remover \(station.name) das favoritas") : L10n.tr("Favoritar \(station.name)"))
            .accessibilityLabel(radio.isFavorite(station) ? L10n.tr("Remover \(station.name) das favoritas") : L10n.tr("Favoritar \(station.name)"))
    }
}

struct PlaybackLabel: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        HStack(spacing: 5) {
            if radio.state.isBusy { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 9, height: 9) }
            else { Circle().fill(radio.failed ? Color.orange : (radio.state.isPlaying ? palette.accent : palette.muted)).frame(width: 4, height: 4) }
            Text(radio.state.isPlaying && !radio.selected.isLive ? L10n.tr("Reproduzindo") : radio.state.label).lineLimit(1)
        }.foregroundStyle(radio.failed ? Color.orange : palette.muted)
            .accessibilityElement(children: .combine)
    }
}

struct TransportButtons: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    var playSize: CGFloat = 40
    var spacing: CGFloat = 19
    var body: some View {
        HStack(spacing: spacing) {
            Button { radio.step(-1) } label: {
                Image(systemName: radio.isPodcast ? "gobackward.15" : "backward.end.fill").font(.system(size: playSize * 0.31))
                    .frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.isPodcast ? L10n.tr("Voltar 15 segundos") : L10n.tr("Rádio anterior (⌘←)")).accessibilityLabel(radio.isPodcast ? L10n.tr("Voltar 15 segundos") : L10n.tr("Rádio anterior"))
            Button { radio.toggle() } label: {
                ZStack {
                    Circle().fill(palette.accent)
                    Image(systemName: radio.active ? "pause.fill" : "play.fill")
                        .font(.system(size: playSize * 0.34, weight: .semibold)).offset(x: radio.active ? 0 : 1)
                        .foregroundStyle(palette.onAccent)
                }.frame(width: playSize, height: playSize).contentShape(Circle())
            }.buttonStyle(.plain).help(radio.isPodcast ? (radio.active ? L10n.tr("Pausar episódio") : L10n.tr("Ouvir episódio")) : (radio.active ? L10n.tr("Pausar (⌘P)") : L10n.tr("Ouvir ao vivo (⌘P)")))
                .accessibilityLabel(radio.isPodcast ? (radio.active ? L10n.tr("Pausar episódio") : L10n.tr("Ouvir episódio")) : (radio.active ? L10n.tr("Pausar rádio") : L10n.tr("Reproduzir rádio")))
            Button { radio.step(1) } label: {
                Image(systemName: radio.isPodcast ? "goforward.15" : "forward.end.fill").font(.system(size: playSize * 0.31))
                    .frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.isPodcast ? L10n.tr("Avançar 15 segundos") : L10n.tr("Próxima rádio (⌘→)")).accessibilityLabel(radio.isPodcast ? L10n.tr("Avançar 15 segundos") : L10n.tr("Próxima rádio"))
        }
    }
}

struct TimerMenu: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        Menu {
            Text(L10n.tr("Desligar automaticamente"))
            ForEach([15, 30, 60, 120], id: \.self) { minutes in
                Button(L10n.tr("Em \(minutes) minutos")) { radio.setSleep(minutes: minutes) }
            }
            Divider()
            Button(L10n.tr("Cancelar timer")) { radio.setSleep(minutes: nil) }.disabled(radio.sleepDeadline == nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: radio.sleepDeadline == nil ? "moon" : "moon.zzz.fill")
                if radio.sleepDeadline != nil { Text("\(radio.remainingMinutes)m").font(.system(size: 10, design: .monospaced)) }
            }.font(.system(size: 13)).foregroundStyle(radio.sleepDeadline == nil ? palette.muted : palette.accent)
        }.menuStyle(.borderlessButton).fixedSize().help(L10n.tr("Timer para desligar a rádio"))
    }
}

struct MiniPlayerView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var app: AppController
    var body: some View {
        Group {
            if app.playerSkin != .vitra { SkinnedMiniPlayer(skin: app.playerSkin) }
            else if app.miniSize.height < 100 { SlimMiniPlayerView() }
            else { RegularMiniPlayerView() }
        }.overlay(alignment: .topTrailing) {
            MiniResizeHandle { size, _ in app.setMiniSize(size) }
                .frame(width: 22, height: 22)
                .help(L10n.tr("Arraste o canto para ajustar largura e altura"))
        }.environment(\.locale, localization.language.locale).environment(\.appPalette, AppPalette(skin: app.playerSkin, accentOverride: app.accentColorHex))
    }
}

struct SlimMiniPlayerView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    @EnvironmentObject private var app: AppController
    var body: some View {
        HStack(spacing: 6) {
            DragHandle().frame(width: 18, height: 28).help(L10n.tr("Mover miniplayer"))
            if app.miniSize.width >= 280 {
            NowPlayingArtwork().frame(width: min(40, app.miniSize.height - 14), height: min(40, app.miniSize.height - 14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(radio.selected.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                PlaybackLabel().font(.system(size: 8))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).background { MiniVUBackground() }.layoutPriority(1)
            Button { radio.step(-1) } label: {
                Image(systemName: radio.isPodcast ? "gobackward.15" : "backward.end.fill").font(.system(size: 10)).frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.isPodcast ? L10n.tr("Voltar 15 segundos") : L10n.tr("Rádio favorita anterior ou faixa anterior"))
            Button { radio.toggle() } label: {
                Image(systemName: radio.active ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.onAccent).frame(width: 30, height: 30)
                    .background(palette.accent, in: Circle()).contentShape(Circle())
            }.buttonStyle(.plain).help(radio.active ? L10n.tr("Pausar") : L10n.tr("Reproduzir"))
            Button { radio.step(1) } label: {
                Image(systemName: radio.isPodcast ? "goforward.15" : "forward.end.fill").font(.system(size: 10)).frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.isPodcast ? L10n.tr("Avançar 15 segundos") : L10n.tr("Próxima faixa ou rádio"))
            Menu { MiniContextMenu() } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).frame(width: 20, height: 28).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.tr("Tamanho, Dock e opções"))
        }.padding(.horizontal, 9).frame(width: app.miniSize.width, height: app.miniSize.height)
            .background { MiniPlayerBackground(appearance: app.miniAppearance) }
            .clipShape(RoundedRectangle(cornerRadius: min(18, app.miniSize.height * 0.27)))
            .overlay(RoundedRectangle(cornerRadius: min(18, app.miniSize.height * 0.27)).strokeBorder(Color.white.opacity(0.13)).allowsHitTesting(false))
            .foregroundStyle(palette.text).preferredColorScheme(.dark)
            .contextMenu { MiniContextMenu() }
    }
}

struct MiniContextMenu: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var radio: RadioPlayer
    @EnvironmentObject private var app: AppController
    var body: some View {
        Button(L10n.tr("Abrir Vitra Radio")) { app.showMain() }
        Button(L10n.tr("Ajustar à altura da Dock")) { app.fitMiniToDock() }
        Menu(L10n.tr("Tema do player")) {
            ForEach(PlayerSkin.allCases) { skin in
                Button { app.playerSkin = skin } label: {
                    if app.playerSkin == skin { Label(L10n.tr(skin.design.name), systemImage: "checkmark") }
                    else { Text(L10n.tr(skin.design.name)) }
                }
            }
        }
        Menu(L10n.tr("Aparência")) {
            ForEach(MiniAppearance.allCases) { appearance in
                Button { app.miniAppearance = appearance } label: {
                    if app.miniAppearance == appearance { Label(L10n.tr(appearance.title), systemImage: "checkmark") }
                    else { Text(L10n.tr(appearance.title)) }
                }
            }
        }
        Menu(L10n.tr("Altura do miniplayer")) {
            ForEach([44, 52, 60, 68, 76, 86, 110, 134], id: \.self) { height in
                Button("\(height) pt") { app.setMiniSize(CGSize(width: app.miniSize.width, height: CGFloat(height))) }
            }
        }
        Button(app.compactMini ? L10n.tr("Expandir controles") : L10n.tr("Usar formato compacto")) { app.toggleCompactMini() }
        Button(radio.alwaysOnTop ? L10n.tr("Desafixar do topo") : L10n.tr("Manter sobre as janelas")) { radio.alwaysOnTop.toggle(); app.updatePanelLevel() }
        Toggle(L10n.tr("Equilibrar volume entre rádios"), isOn: $radio.volumeBalancingEnabled)
        Menu("Volume") {
            ForEach([0, 25, 50, 75, 100], id: \.self) { volume in Button("\(volume)%") { radio.volume = Double(volume) / 100 } }
        }
        Divider()
        Menu(L10n.tr("Posicionar junto à Dock")) {
            Button(L10n.tr("Canto inferior direito")) { app.positionMini(right: true) }
            Button(L10n.tr("Canto inferior esquerdo")) { app.positionMini(right: false) }
        }
        Menu(L10n.tr("Trocar rádio")) {
            ForEach(radio.favoriteStations.isEmpty ? radio.library : radio.favoriteStations) { station in Button(station.name) { radio.select(station) } }
        }
        Menu(L10n.tr("Desligar em…")) {
            ForEach([15, 30, 60, 120], id: \.self) { minutes in Button(L10n.tr("\(minutes) minutos")) { radio.setSleep(minutes: minutes) } }
            Button(L10n.tr("Cancelar timer")) { radio.setSleep(minutes: nil) }
        }
        Divider()
        Button(L10n.tr("Ocultar miniplayer")) { app.hideMini() }
    }
}

struct RegularMiniPlayerView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    @EnvironmentObject private var app: AppController
    private var showDetails: Bool { !app.compactMini && app.miniSize.height >= 134 }

    var body: some View {
        VStack(spacing: showDetails ? 12 : 7) {
            HStack(spacing: 7) {
                DragHandle().frame(width: 22, height: 22).help(L10n.tr("Arraste para posicionar ao lado da Dock"))
                Text("VITRA RADIO").font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(palette.muted)
                Spacer()
                if showDetails { TimerMenu() }
                Button { radio.alwaysOnTop.toggle(); app.updatePanelLevel() } label: {
                    Image(systemName: radio.alwaysOnTop ? "pin.fill" : "pin").font(.system(size: 9))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(radio.alwaysOnTop ? palette.accent : palette.muted).help(L10n.tr("Manter sobre outras janelas"))
                Button { app.showMain() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).foregroundStyle(palette.muted).help(L10n.tr("Abrir janela completa"))
                Button { app.hideMini() } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).foregroundStyle(palette.muted).help(L10n.tr("Ocultar miniplayer; a rádio continua tocando"))
            }
            HStack(spacing: 9) {
                NowPlayingArtwork().frame(width: showDetails ? 43 : 35, height: showDetails ? 43 : 35)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(radio.selected.displayName).font(.system(size: showDetails ? 13 : 11, weight: .semibold)).lineLimit(1)
                    PlaybackLabel().font(.system(size: 8))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).background { MiniVUBackground() }
                if !showDetails {
            Button { radio.step(-1) } label: {
                Image(systemName: radio.isPodcast ? "gobackward.15" : "backward.end.fill").font(.system(size: 10)).frame(width: 24, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.muted).help(radio.isPodcast ? L10n.tr("Voltar 15 segundos") : L10n.tr("Rádio favorita anterior ou faixa anterior"))
                    Button { radio.toggle() } label: {
                        Image(systemName: radio.active ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.onAccent).frame(width: 31, height: 31).background(palette.accent, in: Circle())
                            .contentShape(Circle())
                    }.buttonStyle(.plain).help(radio.active ? L10n.tr("Pausar") : L10n.tr("Reproduzir"))
                    Button { radio.step(1) } label: {
                        Image(systemName: radio.isPodcast ? "goforward.15" : "forward.end.fill").font(.system(size: 10)).frame(width: 24, height: 31).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain).foregroundStyle(palette.muted).help(L10n.tr("Próxima rádio"))
                } else {
                    TransportButtons(playSize: 32, spacing: 5)
                }
            }
            if showDetails {
                HStack(spacing: 9) {
                    Button { radio.muted.toggle() } label: {
                        Image(systemName: radio.muted ? "speaker.slash" : "speaker.wave.2").font(.system(size: 9))
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(palette.muted).help(L10n.tr("Silenciar ou ativar som"))
                    Slider(value: $radio.volume, in: 0...1).controlSize(.mini).tint(palette.accent).accessibilityLabel("Volume")
                    Equalizer(running: radio.state.isPlaying).frame(width: 16, height: 10)
                }
            }
        }.padding(showDetails ? 14 : 12)
            .frame(width: app.miniSize.width, height: app.miniSize.height)
            .background { MiniPlayerBackground(appearance: app.miniAppearance) }
            .clipShape(RoundedRectangle(cornerRadius: app.compactMini ? 17 : 20))
            .overlay(RoundedRectangle(cornerRadius: app.compactMini ? 17 : 20).strokeBorder(Color.white.opacity(0.13)).allowsHitTesting(false))
            .foregroundStyle(palette.text).preferredColorScheme(.dark)
            .contextMenu { MiniContextMenu() }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    @ObservedObject private var localization = AppLocalization.shared
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct DragHandle: NSViewRepresentable {
    @ObservedObject private var localization = AppLocalization.shared
    class HandleView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let origin = window.frame.origin
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let current = window.convertPoint(toScreen: next.locationInWindow)
                let proposed = CGPoint(x: origin.x + current.x - point.x, y: origin.y + current.y - point.y)
                window.setFrameOrigin(MiniPlacement.clamped(proposed, size: window.frame.size, screens: NSScreen.screens.map(\.frame)))
            }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 0.55, alpha: 0.7).setFill()
            for x in [4.0, 8.0] { for y in [4.0, 8.0, 12.0] { NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill() } }
        }
    }
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}


enum MiniAppearance: String, CaseIterable, Identifiable {
    case solid, glass, transparent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Sólido"
        case .glass: return "Liquid Glass"
        case .transparent: return "Transparente"
        }
    }
}

struct MiniPlayerBackground: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let appearance: MiniAppearance
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency || appearance == .solid {
                Color(hex: 0x141D16)
            } else if appearance == .glass {
                NativeMiniGlass().allowsHitTesting(false)
                LinearGradient(colors: [.white.opacity(0.09), .clear, palette.accent.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color(hex: 0x101411).opacity(0.22)
            }
        }.allowsHitTesting(false)
    }
}

struct NativeMiniGlass: NSViewRepresentable {
    @ObservedObject private var localization = AppLocalization.shared
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .clear
            view.cornerRadius = 18
            return view
        }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
