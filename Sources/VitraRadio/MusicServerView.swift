import SwiftUI
import AppKit

struct MusicServerView: View {
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var servers: MusicServerStore
    @EnvironmentObject private var radio: RadioPlayer
    @State private var editing: MusicServerProfile?
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SUA BIBLIOTECA. EM QUALQUER LUGAR.").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(palette.muted)
                        Text("Meu servidor.").font(.system(size: 29, weight: .semibold)).tracking(-1.1)
                        Text("Conecte sua música por Tailscale, rede local ou internet.").font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Button { editing = MusicServerProfile() } label: {
                        Label("Adicionar", systemImage: "plus").font(.system(size: 12, weight: .semibold))
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
                if let error = servers.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if servers.isWorking {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Conectando à sua biblioteca…").font(.system(size: 12)).foregroundStyle(palette.muted) }
                        .frame(maxWidth: .infinity).padding(.vertical, 25)
                }
                if let profile = servers.activeProfile { library(profile) }
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
            .sheet(item: $editing) { profile in MusicServerForm(profile: profile) }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "externaldrive").font(.system(size: 36, weight: .light)).foregroundStyle(palette.accent)
            Text("Sua coleção merece um lugar aqui.").font(.system(size: 22, weight: .medium)).tracking(-0.6)
            Text("Escolha o serviço, informe o endereço e teste a conexão. Cada pessoa configura o próprio servidor; suas credenciais ficam no Chaves do macOS.")
                .font(.system(size: 13)).foregroundStyle(palette.muted).lineSpacing(4)
            HStack(spacing: 18) {
                Label("Navidrome / Subsonic", systemImage: "music.note.list")
                Label("Jellyfin", systemImage: "play.rectangle")
                Label("Pasta / NAS", systemImage: "folder")
            }.font(.system(size: 11)).foregroundStyle(palette.muted)
            Button("Configurar meu servidor") { editing = MusicServerProfile() }
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
                        Text("\(profile.kind.title) · \(profile.network.title)").font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                        if servers.activeProfile?.id == profile.id { Text("Conectado").font(.system(size: 10)).foregroundStyle(palette.accent) }
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 15).padding(.leading, 15).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(servers.isWorking)
            Menu {
                Button("Editar conexão") { editing = profile }
                if servers.activeProfile?.id == profile.id {
                    Button("Desconectar") { radio.stopMusic(from: profile.id); servers.disconnect() }
                }
                Button("Remover conexão", role: .destructive) { radio.stopMusic(from: profile.id); servers.remove(profile) }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 30).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.trailing, 10)
        }.background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func library(_ profile: MusicServerProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(servers.currentAlbum?.title ?? "Sua biblioteca").font(.system(size: 18, weight: .semibold))
                Text(servers.currentAlbum?.artist ?? profile.name).font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            Spacer()
            if servers.showingTracks && profile.kind != .folder {
                Button("Ver álbuns") { search = ""; servers.showAlbums() }.buttonStyle(.plain).foregroundStyle(palette.accent).font(.system(size: 12))
            }
        }
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
            TextField("Buscar músicas na biblioteca…", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                .onSubmit { Task { await servers.search(search) } }
            Button("Buscar") { Task { await servers.search(search) } }.buttonStyle(.bordered).tint(palette.accent).disabled(servers.isWorking)
        }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 10))

        if servers.showingTracks {
            if servers.tracks.isEmpty && !servers.isWorking {
                Text("Nenhuma faixa encontrada. Tente outro nome ou escolha outra pasta.").font(.system(size: 12)).foregroundStyle(palette.muted).padding(.vertical, 20)
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
            Text(profile.kind == .folder ? "Até 5.000 arquivos por pasta. Para coleções maiores, use um servidor de música." : "A busca mostra até 100 faixas por vez. Refine pelo nome para encontrar mais.")
                .font(.system(size: 10)).foregroundStyle(palette.muted)
        } else {
            if servers.albums.isEmpty && !servers.isWorking { Text("Nenhum álbum disponível para esta conta.").foregroundStyle(palette.muted).font(.system(size: 12)) }
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
            if servers.hasMoreAlbums { Button("Carregar mais álbuns") { Task { await servers.loadMoreAlbums() } }.buttonStyle(.bordered).tint(palette.accent).disabled(servers.isWorking) }
        }
    }
}

struct MusicServerForm: View {
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var servers: MusicServerStore
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MusicServerProfile
    @State private var password = ""
    @State private var folderName = ""
    @State private var testing = false
    @State private var message: String?
    @State private var success = false

    init(profile: MusicServerProfile) { _draft = State(initialValue: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Conectar minha música").font(.system(size: 23, weight: .semibold)).tracking(-0.7)
                    Text("Configure uma vez. Sua biblioteca fica por perto.").font(.system(size: 12)).foregroundStyle(palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(testing || servers.isWorking)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    field("Nome da conexão") { TextField("Minha biblioteca", text: $draft.name) }
                    field("Tipo de servidor") { Picker("Tipo de servidor", selection: $draft.kind) { ForEach(MusicServerKind.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                    field("Como você acessa?") {
                        Picker("Rede", selection: $draft.network) { ForEach(MusicNetwork.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                    }
                    Text(draft.network.help).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    if draft.kind == .folder {
                        field("Compartilhamento SMB (opcional)") {
                            HStack {
                                TextField("smb://meu-servidor/Musicas", text: $draft.address)
                                Button("Abrir no Finder") { openSMB() }.buttonStyle(.bordered)
                            }
                        }
                        field("Pasta de música") {
                            HStack {
                                Text(folderName.isEmpty ? (draft.folderBookmark == nil ? "Nenhuma pasta selecionada" : "Pasta salva nesta conexão") : folderName)
                                    .font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button("Escolher pasta…") { chooseFolder() }.buttonStyle(.bordered)
                            }
                        }
                        Text("Se for um NAS, conecte-o pelo Finder e escolha a pasta montada. A autenticação SMB é feita pelo macOS.").font(.system(size: 11)).foregroundStyle(palette.muted)
                    } else {
                        field("Endereço do servidor") { TextField(addressPlaceholder, text: $draft.address) }
                        Text("Inclua a porta e, se houver, o caminho do serviço. Não use a página de login ou /web.").font(.system(size: 11)).foregroundStyle(palette.muted)
                        field("Usuário") { TextField("Seu usuário no servidor", text: $draft.username) }
                        field("Senha") { SecureField(servers.profiles.contains(where: { $0.id == draft.id }) ? "Deixe em branco para manter a credencial salva" : "Sua senha no servidor", text: $password) }
                        Label("Credenciais guardadas no Chaves do macOS.", systemImage: "lock").font(.system(size: 11)).foregroundStyle(palette.muted)
                    }
                    if let message {
                        Label(message, systemImage: success ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(success ? palette.accent : .orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.textFieldStyle(.roundedBorder).controlSize(.large).disabled(testing || servers.isWorking)
            }.scrollIndicators(.hidden)
            HStack(spacing: 12) {
                Button("Cancelar") { dismiss() }.buttonStyle(.plain).foregroundStyle(palette.muted).disabled(testing || servers.isWorking)
                Spacer()
                if testing || servers.isWorking { ProgressView().controlSize(.small) }
                Button("Testar conexão") { testConnection() }.buttonStyle(.bordered).disabled(testing || servers.isWorking)
                Button("Salvar e abrir") {
                    Task {
                        if servers.activeProfile?.id == draft.id { radio.stopMusic(from: draft.id) }
                        if await servers.saveAndConnect(draft, password: password) { password = ""; dismiss() }
                        else { success = false; message = servers.error }
                    }
                }.buttonStyle(.borderedProminent).tint(palette.accent).foregroundStyle(palette.onAccent).disabled(testing || servers.isWorking)
            }
        }.padding(27).frame(width: 575, height: 665).background(palette.background).foregroundStyle(palette.text).preferredColorScheme(palette.skin == .studio ? .light : .dark)
            .interactiveDismissDisabled(testing || servers.isWorking)
            .onChange(of: draft) { _ in message = nil }
            .onChange(of: password) { _ in message = nil }
    }

    private var addressPlaceholder: String {
        if draft.network == .internet { return "https://musica.exemplo.com" }
        return draft.kind == .jellyfin ? "http://meu-servidor:8096" : "http://meu-servidor:4533"
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 12, weight: .medium)); content() }
    }
    private func testConnection() {
        testing = true; message = nil
        Task {
            do { try await servers.test(draft, password: password); success = true; message = "Conexão validada. Você já pode salvar e abrir a biblioteca." }
            catch { success = false; message = MusicServerError.userMessage(error) }
            testing = false
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta pasta"
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
