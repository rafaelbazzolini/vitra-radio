import SwiftUI
import AppKit

struct ThemeQuickMenu: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var app: AppController
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "paintpalette").foregroundStyle(palette.accent)
            Text(L10n.tr("Tema")).fontWeight(.semibold)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.muted)
        }.font(.system(size: 11)).foregroundStyle(palette.text).padding(.horizontal, 12).padding(.vertical, 11)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.line).allowsHitTesting(false))
            .overlay(NativeThemeMenu(selected: app.playerSkin, palette: palette) { app.playerSkin = $0 }.frame(maxWidth: .infinity, maxHeight: .infinity))
            .fixedSize().help(L10n.tr("Trocar tema · \(app.playerSkin.design.name)"))
    }
}

// An AppKit control owns both the click and popup lifetime, including inside a SwiftUI ScrollView.
private struct NativeThemeMenu: NSViewRepresentable {
    @ObservedObject private var localization = AppLocalization.shared
    let selected: PlayerSkin
    let palette: AppPalette
    let choose: (PlayerSkin) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.setAccessibilityLabel(L10n.tr("Trocar tema"))
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.setAccessibilityLabel(L10n.tr("Trocar tema"))
        button.setAccessibilityValue(selected.design.name)
    }
    final class Coordinator: NSObject, NSPopoverDelegate, ThemePickerControlling {
        var parent: NativeThemeMenu
        private var popover: NSPopover?
        init(_ parent: NativeThemeMenu) { self.parent = parent }
        @objc func open(_ sender: NSButton) {
            if popover?.isShown == true { popover?.close(); return }
            let panel = NSPopover()
            panel.behavior = .transient
            panel.delegate = self
            panel.appearance = NSAppearance(named: parent.selected == .studio ? .aqua : .darkAqua)
            panel.contentViewController = NSHostingController(rootView: ThemePickerList(selected: parent.selected, choose: { [weak self] in self?.chooseTheme($0) }).environment(\.appPalette, parent.palette))
            popover = panel
            panel.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NotificationCenter.default.post(name: .init("VitraThemePickerOpened"), object: panel)
        }
        func chooseTheme(_ theme: PlayerSkin) {
            popover?.close()
            parent.choose(theme)
        }
    }
}

protocol ThemePickerControlling: AnyObject { func chooseTheme(_ theme: PlayerSkin) }

private struct ThemePickerList: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let selected: PlayerSkin
    let choose: (PlayerSkin) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.tr("Escolher tema")).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7)
            ForEach(PlayerSkin.allCases) { theme in
                Button { choose(theme) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(theme.design.highlight).frame(width: 10, height: 10)
                        Text(L10n.tr(theme.design.name)).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if selected == theme { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                    }.padding(10).frame(maxWidth: .infinity)
                        .background(selected == theme ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(8).frame(width: 230).foregroundStyle(palette.text).background(palette.background)
    }
}

enum HomeRadioSection: String, CaseIterable {
    case favorites = "Favoritas", recent = "Recentes", podcastFavorites = "Podcasts favoritos", podcastRecents = "Podcasts recentes"
    var isPodcast: Bool { self == .podcastFavorites || self == .podcastRecents }
}

struct HomeRadioTabs: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @Binding var selection: HomeRadioSection
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
            ForEach(HomeRadioSection.allCases, id: \.self) { section in
                Button { selection = section } label: {
                    Label(L10n.tr(section.rawValue), systemImage: section == .favorites ? "heart.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(selection == section ? palette.accent : palette.muted)
                        .background(selection == section ? palette.accent.opacity(0.12) : palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selection == section ? palette.accent.opacity(0.4) : palette.line).allowsHitTesting(false))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        }
    }
}

struct HomePodcasts: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.appPalette) private var palette
    let section: HomeRadioSection
    let search: String
    let open: () -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if section == .podcastFavorites {
                ForEach(store.favorites.filter { search.isEmpty || "\($0.title) \($0.author)".localizedCaseInsensitiveContains(search) }) { show in
                    card(show.title, subtitle: show.author, icon: "podcasts") { open(); Task { await store.open(show) } }
                }
            } else {
                ForEach(store.recents.filter { search.isEmpty || "\($0.show.title) \($0.episode.title)".localizedCaseInsensitiveContains(search) }) { item in
                    card(item.episode.title, subtitle: item.show.title, icon: "play.circle.fill") {
                        store.remember(episode: item.episode, show: item.show)
                        radio.playPodcast(item.episode, show: item.show, position: store.position(item.episode))
                    }
                }
            }
        }
        if section == .podcastFavorites ? store.favorites.isEmpty : store.recents.isEmpty {
            Text(L10n.tr(section == .podcastFavorites ? "Favorite podcasts para encontrá-los aqui." : "Os episódios que você ouvir aparecerão aqui."))
                .foregroundStyle(palette.muted).padding(.vertical, 20)
        }
    }
    private func card(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon == "podcasts" ? "mic.fill" : icon).font(.title2).foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
