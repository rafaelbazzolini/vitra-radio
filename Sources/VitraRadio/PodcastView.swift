import SwiftUI

struct PodcastsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var radio: RadioPlayer
    @EnvironmentObject private var countries: CatalogCountries
    @State private var query = ""
    @State private var section = "search"
    @State private var country = ""
    @State private var language = ""
    @State private var showingRSS = false
    private var searchID: String { [query, country.isEmpty ? (countries.codes.first ?? countries.suggested) : country, language, section].joined(separator: "|") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.tr("BOAS HISTÓRIAS. NO SEU TEMPO.")).font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(palette.muted)
                        Text("Podcasts.").font(.system(size: 29, weight: .semibold)).tracking(-1)
                        Text(L10n.tr("Descubra programas, escolha um episódio e continue de onde parou.")).font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Button { showingRSS = true } label: { Label(L10n.tr("Adicionar RSS"), systemImage: "plus.circle").padding(3) }.buttonStyle(VitraButtonStyle())
                }
                if radio.isPodcast { PodcastPlaybackBar() }
                if let feed = store.opened { episodes(feed) }
                else {
                    HStack(spacing: 8) {
                        sectionButton("search", title: "Descobrir", icon: "magnifyingglass")
                        sectionButton("favorites", title: "Favoritos", icon: "heart.fill")
                        sectionButton("continue", title: "Continuar", icon: "play.circle")
                    }
                    if section == "search" { searchControls }
                    if let error = store.error { errorView(error) }
                    if store.loading || store.searching { HStack { ProgressView().controlSize(.small); Text(L10n.tr(store.loading ? "Carregando episódios…" : "Buscando podcasts…")) }.font(.system(size: 12)).padding(.vertical, 20) }
                    else if section == "continue" {
                        if let episode = store.lastEpisode, let show = store.lastShow {
                            Text(show.title).font(.headline)
                            episodeRow(episode, show: show)
                            Button(L10n.tr("Ver todos os episódios")) { Task { await store.open(show) } }.buttonStyle(VitraButtonStyle())
                        } else { empty("Seu próximo episódio começa aqui.", detail: "Os episódios que você ouvir ficam disponíveis para continuar depois.") }
                    } else {
                        let shows = section == "favorites" ? store.favorites : store.results
                        if shows.isEmpty {
                            empty(section == "favorites" ? "Guarde seus podcasts favoritos." : (query.isEmpty ? "O que você quer ouvir hoje?" : "Nenhum podcast encontrado."),
                                  detail: section == "favorites" ? "Use o coração de um programa para encontrá-lo aqui." : (query.isEmpty ? "Busque pelo nome ou assunto, ou adicione o endereço RSS de um podcast." : "Experimente outro nome, país ou idioma."))
                        } else {
                            Text(L10n.tr(section == "favorites" ? "Seus podcasts" : "Resultados da busca")).font(.system(size: 17, weight: .semibold))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(shows) { show in showCard(show) }
                            }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Text(L10n.tr("Busca no catálogo Apple Podcasts · reprodução pelo RSS do autor.")).font(.system(size: 10))
                    Link("Apple Podcasts", destination: URL(string: "https://podcasts.apple.com/")!).font(.system(size: 10))
                }.foregroundStyle(palette.muted).tint(palette.muted)
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 28)
        }.scrollIndicators(.hidden).foregroundStyle(palette.text)
            .task(id: searchID) {
                guard !CommandLine.arguments.contains("--podcasts-preview"), section == "search", store.opened == nil else { return }
                await store.search(query, country: country.isEmpty ? (countries.codes.first ?? countries.suggested) : country, language: language)
            }
            .sheet(isPresented: $showingRSS) { PodcastRSSForm().frame(width: 540, height: 330) }
    }
    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField(L10n.tr("Buscar podcast por nome ou assunto…"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(14).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 18) {
                Picker(L10n.tr("País do catálogo"), selection: $country) {
                    Text(CatalogCountries.name(countries.codes.first ?? countries.suggested)).tag("")
                    ForEach(CatalogCountries.allCodes.filter { $0 != (countries.codes.first ?? countries.suggested) }.sorted { CatalogCountries.name($0) < CatalogCountries.name($1) }, id: \.self) { code in Text(CatalogCountries.name(code)).tag(code) }
                }.frame(maxWidth: 300)
                Picker(L10n.tr("Idioma do RSS"), selection: $language) {
                    Text(L10n.tr("Todos")).tag("")
                    Text("Português").tag("pt")
                    Text("English").tag("en")
                }.frame(maxWidth: 230)
            }.font(.system(size: 11))
            if !language.isEmpty { Text(L10n.tr("O filtro consulta o idioma declarado no RSS e pode levar alguns segundos. Feeds sem idioma informado não entram neste filtro.")).font(.system(size: 10)).foregroundStyle(palette.muted) }
        }
    }
    private func sectionButton(_ value: String, title: String, icon: String) -> some View {
        Button { section = value } label: {
            Label(L10n.tr(title), systemImage: icon).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
                .foregroundStyle(section == value ? palette.onAccent : palette.muted)
                .background(section == value ? palette.accent : palette.surface, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain)
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle").font(.system(size: 42, weight: .light)).foregroundStyle(palette.accent)
            Text(L10n.tr(title)).font(.system(size: 20, weight: .semibold))
            Text(L10n.tr(detail)).font(.system(size: 12)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 50)
    }
    private func errorView(_ error: String) -> some View {
        Label(L10n.tr(error), systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).padding(12)
    }
    private func heart(_ show: PodcastShow) -> some View {
        let saved = store.favorites.contains { $0.id == show.id }
        return Button { store.toggle(show) } label: {
            Image(systemName: saved ? "heart.fill" : "heart").foregroundStyle(saved ? palette.accent : palette.muted).frame(width: 34, height: 38).contentShape(Rectangle())
        }.buttonStyle(.plain).help(saved ? L10n.tr("Remover podcast dos favoritos") : L10n.tr("Favoritar podcast"))
    }
    private func showCard(_ show: PodcastShow) -> some View {
        HStack(spacing: 0) {
            Button { Task { await store.open(show) } } label: {
                HStack(spacing: 13) {
                    PodcastArtwork(url: show.artwork).frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(show.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Text(show.author).font(.system(size: 11)).foregroundStyle(palette.muted).lineLimit(2)
                        Text(L10n.tr("Ver episódios")).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.accent)
                    }
                    Spacer(minLength: 0)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            heart(show).padding(.trailing, 9)
        }.background(palette.surface, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.line))
    }
    private func episodes(_ feed: PodcastFeed) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { store.close() } label: { Label(L10n.tr("Voltar aos podcasts"), systemImage: "chevron.left") }.buttonStyle(VitraButtonStyle(compact: true))
            HStack(alignment: .top, spacing: 20) {
                PodcastArtwork(url: feed.show.artwork).frame(width: 115, height: 115)
                VStack(alignment: .leading, spacing: 8) {
                    Text(feed.show.title).font(.system(size: 24, weight: .semibold))
                    Text(feed.show.author).font(.system(size: 13)).foregroundStyle(palette.muted)
                    Text(feed.show.summary).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(5)
                }
                Spacer(minLength: 0)
                heart(feed.show)
            }.padding(20).background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
            Text(L10n.tr("\(feed.episodes.count) episódios disponíveis no RSS")).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.muted)
            LazyVStack(spacing: 10) { ForEach(feed.episodes) { episode in episodeRow(episode, show: feed.show) } }
        }
    }
    private func episodeRow(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = radio.podcastEpisode?.id == episode.id
        let position = store.position(episode)
        return HStack(alignment: .top, spacing: 15) {
            Button {
                if current { radio.toggle() }
                else { store.remember(episode: episode, show: show); radio.playPodcast(episode, show: show, position: position) }
            } label: {
                Image(systemName: current && radio.active ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.onAccent).frame(width: 44, height: 44).background(palette.accent, in: Circle()).contentShape(Circle())
            }.buttonStyle(.plain).help(current && radio.active ? L10n.tr("Pausar") : L10n.tr("Ouvir episódio"))
            VStack(alignment: .leading, spacing: 7) {
                Text(episode.title).font(.system(size: 14, weight: .semibold))
                HStack(spacing: 12) {
                    if let date = episode.published { Text(date.formatted(.dateTime.locale(localization.language.locale).day().month(.abbreviated).year())) }
                    if episode.duration > 0 { Text(PodcastPlaybackBar.time(episode.duration)) }
                    if store.progress[episode.id]?.completed == true { Label(L10n.tr("Concluído"), systemImage: "checkmark.circle.fill").foregroundStyle(palette.accent) }
                    else if position > 0 { Text(L10n.tr("Retomar em \(PodcastPlaybackBar.time(position))")).foregroundStyle(palette.accent) }
                }.font(.system(size: 10)).foregroundStyle(palette.muted)
                Text(episode.summary).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(17).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? palette.accent.opacity(0.5) : palette.line))
    }
}

struct PodcastArtwork: View {
    @Environment(\.appPalette) private var palette
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { LinearGradient(colors: [palette.accent.opacity(0.55), palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(palette.text) }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
struct PodcastPlaybackBar: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.appPalette) private var palette
    @State private var scrubbing = false
    @State private var seek = 0.0
    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 7 * 86400))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(radio.selected.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                TransportButtons(playSize: 34)
            }
            HStack {
                Text(Self.time(scrubbing ? seek : radio.elapsed)).monospacedDigit()
                Slider(value: Binding(get: { scrubbing ? seek : min(radio.elapsed, max(1, radio.duration)) }, set: { seek = $0 }), in: 0...max(1, radio.duration), onEditingChanged: { editing in
                    if editing { seek = radio.elapsed; scrubbing = true }
                    else { scrubbing = false; radio.seekPodcast(to: seek) }
                })
                    .disabled(radio.duration <= 0 || radio.state.isBusy).accessibilityLabel(L10n.tr("Posição do episódio"))
                Text(Self.time(radio.duration)).monospacedDigit()
            }.font(.system(size: 10)).foregroundStyle(palette.muted)
        }.padding(15).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct PodcastRSSForm: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("Adicionar podcast por RSS")).font(.system(size: 23, weight: .semibold))
            Text(L10n.tr("Cole o endereço do feed RSS, não a página do programa. Sem conta ou assinatura do Vitra.")).font(.system(size: 12)).foregroundStyle(palette.muted)
            TextField("https://…/feed.xml", text: $address).textFieldStyle(.plain).padding(13).background(palette.surface, in: RoundedRectangle(cornerRadius: 10)).onSubmit { load() }
            if let error = validation ?? store.error { Text(L10n.tr(error)).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            HStack {
                Button(L10n.tr("Cancelar")) { dismiss() }.buttonStyle(VitraButtonStyle()).disabled(store.loading)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Button(L10n.tr("Abrir podcast")) { load() }.buttonStyle(VitraButtonStyle(prominent: true)).disabled(store.loading)
            }
        }.padding(28).foregroundStyle(palette.text).background(palette.background)
    }
    private func load() {
        guard !store.loading else { return }
        guard let url = PodcastURLs.web(address) else { validation = "Informe um endereço RSS com http:// ou https://, sem usuário ou senha na URL."; return }
        validation = nil
        Task { await store.open(PodcastShow(title: "Podcast", author: "", feed: url)); if store.opened != nil { dismiss() } }
    }
}

struct NowPlayingArtwork: View {
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        if radio.isPodcast { PodcastArtwork(url: radio.podcastArtwork) }
        else { StationArtwork(station: radio.selected) }
    }
}
