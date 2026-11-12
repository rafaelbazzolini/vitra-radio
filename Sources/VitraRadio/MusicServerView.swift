import SwiftUI
import AppKit

struct MusicServerView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var servers: MusicServerStore
    @EnvironmentObject private var radio: RadioPlayer
    var configurationOnly = false
    var libraryOnly = false
    @State private var editing: MusicServerProfile?
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                if !libraryOnly {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("SUA BIBLIOTECA. EM QUALQUER LUGAR.")).font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(palette.muted)
                            Text(L10n.tr("Minhas Músicas")).font(.system(size: 29, weight: .semibold)).tracking(-1.1)
                            Text(L10n.tr("Ouça músicas de uma pasta do dispositivo ou conecte sua biblioteca online.")).font(.system(size: 12)).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Button { editing = newFolderProfile() } label: {
                            Label(L10n.tr("Adicionar"), systemImage: "plus").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 15).padding(.vertical, 11).foregroundStyle(palette.onAccent)
                                .background(palette.accent, in: Capsule()).contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    if servers.profiles.isEmpty { welcome }
                    else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 12)], spacing: 12) {
                            ForEach(servers.profiles) { profile in profileCard(profile) }
                        }
                    }
                }
                if let error = servers.error {
                    Label(L10n.tr(error), systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if servers.isWorking {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(L10n.tr("Conectando à sua biblioteca…")).font(.system(size: 12)).foregroundStyle(palette.muted) }
                        .frame(maxWidth: .infinity).padding(.vertical, 25)
                }
                if !configurationOnly, let profile = servers.activeProfile { library(profile) }
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
            .onAppear {
                if CommandLine.arguments.contains("--render-previews") && CommandLine.arguments.contains("--music-add-preview") {
                    var profile = newFolderProfile()
                    if CommandLine.arguments.contains("--music-network-preview") { profile.kind = .subsonic; profile.localFolder = false; profile.network = .tailscale }
                    editing = profile
                }
            }
            .sheet(item: $editing) { profile in MusicServerForm(profile: profile) }
    }

    private func newFolderProfile() -> MusicServerProfile {
        var profile = MusicServerProfile(); profile.kind = .folder; profile.network = .local; profile.localFolder = true
        return profile
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "externaldrive").font(.system(size: 36, weight: .light)).foregroundStyle(palette.accent)
            Text(L10n.tr("Sua coleção merece um lugar aqui.")).font(.system(size: 22, weight: .medium)).tracking(-0.6)
            Text(L10n.tr("Adicione uma pasta de músicas do seu dispositivo ou conecte um servidor. Seus arquivos permanecem onde estão, sem precisar copiar ou enviar."))
                .font(.system(size: 13)).foregroundStyle(palette.muted).lineSpacing(4)
            HStack(spacing: 18) {
                Label("Navidrome / Subsonic", systemImage: "music.note.list")
                Label("Jellyfin", systemImage: "play.rectangle")
                Label(L10n.tr("Pasta deste dispositivo"), systemImage: "folder")
            }.font(.system(size: 11)).foregroundStyle(palette.muted)
            Button(L10n.tr("Adicionar minhas músicas")) { editing = newFolderProfile() }
                .buttonStyle(.bordered).tint(palette.accent)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [palette.accent.opacity(0.13), palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }

    private func profileCard(_ profile: MusicServerProfile) -> some View {
        HStack(spacing: 11) {
            Button {
                if let previous = servers.activeProfile { radio.stopMusic(from: previous.id) }
                Task { await servers.connect(profile) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: profile.kind == .folder ? "folder" : "server.rack").font(.system(size: 23, weight: .light)).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                        Text(profile.isLocalFolder ? L10n.tr("Pasta deste dispositivo") : "\(profile.kind.title) · \(profile.network.title)").font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                        if servers.activeProfile?.id == profile.id { Text(L10n.tr("Conectado")).font(.system(size: 10)).foregroundStyle(palette.accent) }
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 15).padding(.leading, 15).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(servers.isWorking)
            Menu {
                Button(L10n.tr("Editar conexão")) { editing = profile }
                if servers.activeProfile?.id == profile.id {
                    Button(L10n.tr("Desconectar")) { radio.stopMusic(from: profile.id); servers.disconnect() }
                }
                Button(L10n.tr("Remover conexão"), role: .destructive) { radio.stopMusic(from: profile.id); servers.remove(profile) }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 30).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.trailing, 10)
        }.background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func library(_ profile: MusicServerProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(servers.currentAlbum?.title ?? L10n.tr("Sua biblioteca")).font(.system(size: 18, weight: .semibold))
                Text(servers.currentAlbum?.artist ?? profile.name).font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            Spacer()
            if servers.showingTracks && profile.kind != .folder {
                Button(L10n.tr("Ver álbuns")) { search = ""; servers.showAlbums() }.buttonStyle(.plain).foregroundStyle(palette.accent).font(.system(size: 12))
            }
        }
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
            TextField(L10n.tr("Buscar músicas na biblioteca…"), text: $search).textFieldStyle(.plain).font(.system(size: 13))
                .onSubmit { Task { await servers.search(search) } }
            Button(L10n.tr("Buscar")) { Task { await servers.search(search) } }.buttonStyle(.bordered).tint(palette.accent).disabled(servers.isWorking)
        }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 10))

        if servers.showingTracks {
            if servers.tracks.isEmpty && !servers.isWorking {
                Text(L10n.tr("Nenhuma faixa encontrada. Tente outro nome ou escolha outra pasta.")).font(.system(size: 12)).foregroundStyle(palette.muted).padding(.vertical, 20)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(servers.tracks.enumerated()), id: \.element.id) { index, track in
                    Button { servers.play(track, on: radio) } label: {
                        HStack(spacing: 13) {
                            Text(String(index + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.muted).frame(width: 24)
                            Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.text).lineLimit(1)
                                Text("\(track.artist)\(track.album.isEmpty ? "" : " · " + track.album)").font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                            }
                            Spacer()
                            if track.duration > 0 {
                                Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.muted)
                            }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Rectangle().fill(palette.line).frame(height: 1)
                }
            }
            Text(profile.kind == .folder ? L10n.tr("Até 5.000 arquivos por pasta. Para coleções maiores, use um servidor de música.") : L10n.tr("A busca mostra até 100 faixas por vez. Refine pelo nome para encontrar mais."))
                .font(.system(size: 10)).foregroundStyle(palette.muted)
        } else {
            if servers.albums.isEmpty && !servers.isWorking { Text(L10n.tr("Nenhum álbum disponível para esta conta.")).foregroundStyle(palette.muted).font(.system(size: 12)) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 16) {
                ForEach(servers.albums) { album in
                    Button { Task { await servers.openAlbum(album) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [palette.accent.opacity(0.25), palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "music.note").font(.system(size: 35, weight: .light)).foregroundStyle(palette.accent.opacity(0.75))
                            }.frame(height: 115)
                            Text(album.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                            Text(album.artist).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(servers.isWorking)
                }
            }
            if servers.hasMoreAlbums { Button(L10n.tr("Carregar mais álbuns")) { Task { await servers.loadMoreAlbums() } }.buttonStyle(.bordered).tint(palette.accent).disabled(servers.isWorking) }
        }
    }
}

struct MusicServerForm: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var servers: MusicServerStore
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MusicServerProfile
    @State private var localSource: Bool
    @State private var serverKind: MusicServerKind
    @State private var password = ""
    @State private var folderName = ""
    @State private var testing = false
    @State private var message: String?
    @State private var success = false

    init(profile: MusicServerProfile) {
        _draft = State(initialValue: profile)
        _localSource = State(initialValue: profile.isLocalFolder)
        _serverKind = State(initialValue: profile.isLocalFolder ? .subsonic : profile.kind)
    }

    private var configuredProfile: MusicServerProfile {
        var profile = draft
        profile.localFolder = localSource
        profile.kind = localSource ? .folder : serverKind
        if localSource {
            profile.address = ""; profile.username = ""; profile.network = .local
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { profile.name = L10n.tr("Minha biblioteca") }
        }
        return profile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("Conectar minha música")).font(.system(size: 23, weight: .semibold)).tracking(-0.7)
                    Text(L10n.tr("Configure uma vez. Sua biblioteca fica por perto.")).font(.system(size: 12)).foregroundStyle(palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(testing || servers.isWorking)
            }
            HStack(spacing: 10) {
                sourceTab("Pasta deste dispositivo", icon: "folder", local: true)
                sourceTab("Servidor de música", icon: "server.rack", local: false)
            }.disabled(testing || servers.isWorking)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    field("Nome da biblioteca") { TextField(L10n.tr("Minha biblioteca"), text: $draft.name) }
                    if !localSource {
                        field("Tipo de servidor") { Picker(L10n.tr("Tipo de servidor"), selection: $serverKind) { ForEach(MusicServerKind.allCases) { Text(L10n.tr($0.title)).tag($0) } }.labelsHidden() }
                        field("Como você acessa?") {
                            Picker(L10n.tr("Rede"), selection: $draft.network) { ForEach(MusicNetwork.allCases) { Text(L10n.tr($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                        }
                        Text(L10n.tr(draft.network.help)).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if localSource || serverKind == .folder {
                        if !localSource {
                            field("Endereço da pasta na rede (opcional)") {
                                HStack {
                                    TextField("smb://meu-servidor/Musicas", text: $draft.address)
                                    Button(L10n.tr("Abrir no Finder")) { openSMB() }.buttonStyle(VitraButtonStyle())
                                }
                            }
                        }
                        field("Pasta de música") {
                            HStack {
                                Text(folderName.isEmpty ? (draft.folderBookmark == nil ? L10n.tr("Nenhuma pasta selecionada") : L10n.tr("Pasta salva nesta conexão")) : folderName)
                                    .font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button(L10n.tr("Escolher pasta…")) { chooseFolder() }.buttonStyle(VitraButtonStyle())
                            }
                        }
                        Text(localSource ? L10n.tr("Escolha uma pasta deste dispositivo. Suas músicas aparecem aqui sem copiar os arquivos. A pasta precisa continuar disponível para tocar.") : L10n.tr("Para uma pasta em outro computador ou dispositivo de armazenamento, abra a conexão no Finder e depois escolha a pasta conectada. O macOS cuida do login.")).font(.system(size: 11)).foregroundStyle(palette.muted)
                    } else {
                        field("Endereço do servidor") { TextField(L10n.tr(addressPlaceholder), text: $draft.address) }
                        Text(L10n.tr("Inclua a porta e, se houver, o caminho do serviço. Não use a página de login ou /web.")).font(.system(size: 11)).foregroundStyle(palette.muted)
                        field("Usuário") { TextField(L10n.tr("Seu usuário no servidor"), text: $draft.username) }
                        field("Senha") { SecureField(servers.profiles.contains(where: { $0.id == draft.id }) ? L10n.tr("Deixe em branco para manter a credencial salva") : L10n.tr("Sua senha no servidor"), text: $password) }
                        Label(L10n.tr("Credenciais guardadas no Chaves do macOS."), systemImage: "lock").font(.system(size: 11)).foregroundStyle(palette.muted)
                    }
                    if let message {
                        Label(L10n.tr(message), systemImage: success ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(success ? palette.accent : .orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.textFieldStyle(.roundedBorder).controlSize(.large).disabled(testing || servers.isWorking)
            }.scrollIndicators(.hidden)
            HStack(spacing: 12) {
                Button(L10n.tr("Cancelar")) { dismiss() }.buttonStyle(.plain).foregroundStyle(palette.muted).disabled(testing || servers.isWorking)
                Spacer()
                if testing || servers.isWorking { ProgressView().controlSize(.small) }
                Button(localSource ? L10n.tr("Verificar pasta") : L10n.tr("Testar conexão")) { testConnection() }.buttonStyle(VitraButtonStyle()).disabled(testing || servers.isWorking)
                Button(L10n.tr("Salvar e abrir")) {
                    Task {
                        if servers.activeProfile?.id == draft.id { radio.stopMusic(from: draft.id) }
                        if await servers.saveAndConnect(configuredProfile, password: password) { password = ""; dismiss() }
                        else { success = false; message = servers.error }
                    }
                }.buttonStyle(VitraButtonStyle(prominent: true)).disabled(testing || servers.isWorking)
            }
        }.padding(27).frame(width: 575, height: localSource ? 455 : 665).background(palette.background).foregroundStyle(palette.text).preferredColorScheme(palette.skin == .studio ? .light : .dark)
            .interactiveDismissDisabled(testing || servers.isWorking)
            .onChange(of: draft) { _ in message = nil }
            .onChange(of: password) { _ in message = nil }
            .onChange(of: serverKind) { _ in message = nil }
    }

    private func sourceTab(_ title: String, icon: String, local: Bool) -> some View {
        Button { localSource = local; message = nil } label: {
            Label(L10n.tr(title), systemImage: icon)
                .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(localSource == local ? palette.accent : palette.muted)
                .background(localSource == local ? palette.accent.opacity(0.13) : palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(localSource == local ? palette.accent.opacity(0.5) : palette.line))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(localSource == local ? .isSelected : [])
    }

    private var addressPlaceholder: String {
        if draft.network == .internet { return "https://musica.exemplo.com" }
        return serverKind == .jellyfin ? "http://meu-servidor:8096" : "http://meu-servidor:4533"
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(L10n.tr(title)).font(.system(size: 12, weight: .medium)); content() }
    }
    private func testConnection() {
        testing = true; message = nil
        Task {
            do { try await servers.test(configuredProfile, password: password); success = true; message = "Conexão validada. Você já pode salvar e abrir a biblioteca." }
            catch { success = false; message = MusicServerError.userMessage(error) }
            testing = false
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("Usar esta pasta")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                draft.folderBookmark = bookmark; folderName = url.path; message = nil
            } catch { message = "Não foi possível guardar o acesso à pasta. Tente escolher novamente."; success = false }
        }
    }
    private func openSMB() {
        guard let url = URL(string: draft.address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "smb", url.host != nil,
              url.user == nil, url.password == nil else { message = "Use smb://servidor/compartilhamento, sem senha no endereço."; success = false; return }
        NSWorkspace.shared.open(url)
    }
}
