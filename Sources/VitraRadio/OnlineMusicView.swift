import SwiftUI

struct MusicLibraryView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @State private var tab = CommandLine.arguments.contains("--online-playlists-preview") ? "Minhas playlists" : CommandLine.arguments.contains("--online-music-preview") ? "Descobrir músicas" : "Sua biblioteca"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(["Sua biblioteca", "Descobrir músicas", "Minhas playlists"], id: \.self) { item in
                    Button { tab = item } label: {
                        Text(L10n.tr(item)).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
                            .foregroundStyle(tab == item ? palette.onAccent : palette.text)
                            .background(tab == item ? palette.accent : palette.surface, in: Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 12)
            if tab == "Sua biblioteca" { MusicServerView() }
            else { OnlineMusicView(playlistsOnly: tab == "Minhas playlists") }
        }
    }
}

struct OnlineMusicView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var store: OnlineMusicStore
    @EnvironmentObject private var radio: RadioPlayer
    let playlistsOnly: Bool
    @State private var source: OnlineMusicSource = .archive
    @State private var field: OnlineMusicField = .all
    @State private var genre = ""
    @State private var search = ""
    @State private var selectedPlaylist: UUID?
    @State private var editingID: UUID?
    @State private var playlistName = ""
    @State private var naming = false
    @State private var addItem: OnlineMusicItem?
    @State private var deleteID: UUID?
    private var playlist: OnlinePlaylist? { store.playlists.first { $0.id == selectedPlaylist } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr(playlistsOnly ? "Minhas playlists" : "Descobrir músicas")).font(.system(size: 28, weight: .semibold))
                        Text(L10n.tr("Ouça online. Suas playlists ficam neste dispositivo.")).font(.caption).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Button { editingID = nil; playlistName = ""; naming = true } label: { Label(L10n.tr("Nova playlist"), systemImage: "plus") }.buttonStyle(VitraButtonStyle())
                }
                if playlistsOnly { playlistContent }
                else {
                    searchForm
                    if let opened = store.opened {
                        HStack {
                            Button { store.close() } label: { Label(L10n.tr("Voltar aos resultados"), systemImage: "chevron.left") }.buttonStyle(.plain)
                            Text(opened.title).font(.headline).lineLimit(2)
                            Spacer()
                            Link(L10n.tr("Ver na fonte"), destination: opened.page)
                        }.foregroundStyle(palette.accent)
                    }
                    if !store.working && (store.opened == nil ? store.results : store.tracks).isEmpty {
                        Text(L10n.tr("Busque por música, artista ou categoria. No Internet Archive, abra um álbum para ver as faixas."))
                            .foregroundStyle(palette.muted).font(.callout).padding(.vertical, 25)
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(store.opened == nil ? store.results : store.tracks) { item in
                            musicRow(item, queue: store.opened == nil ? store.results : store.tracks)
                        }
                    }
                    if store.opened == nil && store.hasMore { Button(L10n.tr("Carregar mais")) { Task { await store.more() } }.buttonStyle(VitraButtonStyle()).disabled(store.working) }
                }
                if store.working || store.resolving { ProgressView().controlSize(.small).accessibilityLabel(L10n.tr("Carregando…")) }
                if let error = store.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(palette.accent) }
                Text(L10n.tr("Disponibilidade, autoria e categorias dependem dos dados da fonte. Nenhum arquivo de áudio é salvo para uso offline."))
                    .font(.caption).foregroundStyle(palette.muted)
            }.padding(30)
        }
        .sheet(isPresented: $naming) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.tr(editingID == nil ? "Nova playlist" : "Renomear playlist")).font(.title2)
                TextField(L10n.tr("Nome da playlist"), text: $playlistName).textFieldStyle(.roundedBorder).onSubmit(saveName)
                HStack { Button(L10n.tr("Cancelar")) { naming = false }; Spacer(); Button(L10n.tr("Salvar"), action: saveName).buttonStyle(VitraButtonStyle()).disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(25).frame(width: 400).background(palette.background)
        }
        .sheet(item: $addItem) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("Adicionar à playlist")).font(.title2)
                Text(item.title).foregroundStyle(palette.muted)
                ScrollView { VStack(spacing: 8) { ForEach(store.playlists) { list in
                    Button { store.add(item, to: list.id); addItem = nil } label: { Label(list.name, systemImage: "music.note.list").frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle()) }.buttonStyle(.plain)
                } } }.frame(maxHeight: 260)
                if store.playlists.isEmpty { Text(L10n.tr("Crie uma playlist para guardar suas músicas.")) }
                TextField(L10n.tr("Nome da nova playlist"), text: $playlistName).textFieldStyle(.roundedBorder)
                HStack { Button(L10n.tr("Cancelar")) { addItem = nil }; Spacer(); Button(L10n.tr("Criar e adicionar")) { if let id = store.create(playlistName) { store.add(item, to: id); addItem = nil } }.disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(25).frame(width: 430).background(palette.background)
        }
        .alert(L10n.tr("Excluir playlist?"), isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button(L10n.tr("Cancelar"), role: .cancel) { deleteID = nil }
            Button(L10n.tr("Excluir"), role: .destructive) { if let id = deleteID { store.delete(id); if selectedPlaylist == id { selectedPlaylist = nil } }; deleteID = nil }
        } message: { Text(L10n.tr("As faixas não serão removidas das fontes.")) }
        .onChange(of: source) { _ in store.clearSearch(); if source == .jamendo && field == .composer { field = .all } }
    }
    private func saveName() {
        if let id = editingID { store.rename(id, name: playlistName) } else { selectedPlaylist = store.create(playlistName) }
        naming = false
    }
    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Menu {
                    ForEach(OnlineMusicSource.allCases, id: \.self) { item in
                        Button { source = item } label: { Label(item.rawValue, systemImage: source == item ? "checkmark" : "globe") }
                    }
                } label: { Label(source.rawValue, systemImage: "globe").font(.system(size: 12, weight: .semibold)).padding(12).frame(width: 200).background(palette.surface, in: RoundedRectangle(cornerRadius: 12)) }
                .menuStyle(.borderlessButton).fixedSize().help(L10n.tr("Fonte"))
                Menu {
                    ForEach(OnlineMusicField.allCases.filter { source != .jamendo || $0 != .composer }, id: \.self) { item in
                        Button { field = item } label: { Label(L10n.tr(item.rawValue), systemImage: field == item ? "checkmark" : "magnifyingglass") }
                    }
                } label: { Label(L10n.tr(field.rawValue), systemImage: "line.3.horizontal.decrease.circle").font(.system(size: 12, weight: .semibold)).padding(12).frame(width: 190).background(palette.surface, in: RoundedRectangle(cornerRadius: 12)) }
                .menuStyle(.borderlessButton).fixedSize().help(L10n.tr("Pesquisar por"))
                Spacer()
            }
            HStack(spacing: 10) {
                TextField(L10n.tr("Música, artista ou compositor…"), text: $search).textFieldStyle(.plain).onSubmit(runSearch)
                Button(L10n.tr("Buscar"), action: runSearch).buttonStyle(VitraButtonStyle()).disabled(store.working)
            }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(OnlineMusicClient.genres, id: \.self) { item in
                    Button { genre = item; runSearch() } label: {
                        Text(OnlineMusicClient.genreTitle(item)).font(.caption).padding(.horizontal, 12).padding(.vertical, 9)
                            .background(genre == item ? palette.accent.opacity(0.15) : palette.surface, in: Capsule()).foregroundStyle(genre == item ? palette.accent : palette.muted)
                    }.buttonStyle(.plain)
                } }
            }
            if source == .jamendo {
                DisclosureGroup(L10n.tr("Conexão Jamendo")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("O Jamendo precisa de um Client ID de aplicativo. O filtro Compositor está disponível apenas no Internet Archive; ele depende dos metadados publicados."))
                        TextField("Client ID", text: $store.clientID).textFieldStyle(.roundedBorder)
                        Link(L10n.tr("Portal de desenvolvedores Jamendo"), destination: URL(string: "https://devportal.jamendo.com/")!)
                    }.font(.caption).padding(.vertical, 8)
                }
            } else {
                Text(L10n.tr("O Archive pesquisa registros de músicas e álbuns. Cantor / artista usa o campo de autoria; Compositor depende dos metadados publicados."))
                    .font(.caption).foregroundStyle(palette.muted)
            }
        }
    }
    private func runSearch() { Task { await store.search(source: source, text: search, field: field, genre: genre) } }
    @ViewBuilder private var playlistContent: some View {
        if store.playlists.isEmpty { Text(L10n.tr("Crie uma playlist e adicione músicas dos resultados da busca." )).foregroundStyle(palette.muted).padding(.vertical, 30) }
        ForEach(store.playlists) { list in
            HStack {
                Button { selectedPlaylist = list.id } label: {
                    HStack { Image(systemName: "music.note.list"); Text(list.name).fontWeight(.semibold); Text("\(list.tracks.count)").foregroundStyle(palette.muted); Spacer() }.padding(15).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    Button(L10n.tr("Renomear playlist")) { editingID = list.id; playlistName = list.name; naming = true }
                    Button(L10n.tr("Mover para cima")) { store.movePlaylist(list.id, direction: -1) }
                    Button(L10n.tr("Mover para baixo")) { store.movePlaylist(list.id, direction: 1) }
                    Button(L10n.tr("Excluir"), role: .destructive) { deleteID = list.id }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30) }.menuStyle(.borderlessButton).fixedSize().padding(.trailing, 12)
            }.background(selectedPlaylist == list.id ? palette.accent.opacity(0.12) : palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        if let list = playlist {
            HStack { Text(list.name).font(.title2); Spacer(); Button { if let first = list.tracks.first { Task { await store.play(first, queue: list.tracks, on: radio) } } } label: { Label(L10n.tr("Ouvir playlist"), systemImage: "play.fill") }.buttonStyle(VitraButtonStyle()).disabled(list.tracks.isEmpty || store.resolving) }
            LazyVStack(spacing: 10) { ForEach(list.tracks) { musicRow($0, queue: list.tracks, playlistID: list.id) } }
            if list.tracks.isEmpty { Text(L10n.tr("Esta playlist ainda não tem músicas." )).foregroundStyle(palette.muted) }
        }
    }
    private func musicRow(_ item: OnlineMusicItem, queue: [OnlineMusicItem], playlistID: UUID? = nil) -> some View {
        HStack(spacing: 12) {
            Button {
                if item.isCollection { Task { await store.open(item) } }
                else { Task { await store.play(item, queue: queue.filter { !$0.isCollection }, on: radio) } }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.isCollection ? "square.stack" : "play.circle.fill").font(.title2).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline).lineLimit(2)
                        Text([item.artist, item.album].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(palette.muted).lineLimit(2)
                        Text(item.source.rawValue + (item.isCollection ? " · " + L10n.tr("Ver faixas") : "")).font(.caption2).foregroundStyle(palette.accent)
                    }; Spacer(minLength: 0)
                }.padding(15).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(store.resolving)
            if !item.isCollection {
                Menu {
                    Button(L10n.tr("Adicionar à playlist")) { playlistName = ""; addItem = item }
                    if let id = playlistID {
                        Button(L10n.tr("Mover para cima")) { store.moveTrack(item, in: id, direction: -1) }
                        Button(L10n.tr("Mover para baixo")) { store.moveTrack(item, in: id, direction: 1) }
                        Button(L10n.tr("Remover da playlist")) { store.remove(item, from: id) }
                    }
                    Link(L10n.tr("Ver na fonte"), destination: item.page)
                    if let license = OnlineMusicClient.url(item.license) { Link(L10n.tr("Licença"), destination: license) }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30) }.menuStyle(.borderlessButton).fixedSize().padding(.trailing, 12)
            }
        }.background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
