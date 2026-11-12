import SwiftUI

// Add a descriptor here to introduce another skin without changing playback.
enum PlayerSkin: String, CaseIterable, Identifiable {
    case vitra, receiver, studio, heritage, digital
    var id: String { rawValue }
    var design: SkinDesign {
        switch self {
        case .vitra: return SkinDesign(name: "Vitra Padrão", subtitle: "Layout original, com barra lateral e cards de rádios.", category: "ESSENCIAL", background: 0x141D16, panel: 0x233026, accent: 0xC3F47A, text: 0xF1F4EC, muted: 0xA0B09F, radius: 18, mono: false)
        case .receiver: return SkinDesign(name: "Receiver", subtitle: "Receptor contemporâneo, display e memórias de estação.", category: "RECEPTOR", background: 0x141D16, panel: 0x233026, accent: 0xC3F47A, text: 0xF1F4EC, muted: 0xA0B09F, radius: 18, mono: false)
        case .studio: return SkinDesign(name: "Studio", subtitle: "Alumínio fosco, contraste suave e precisão.", category: "MODERNO", background: 0xAEBBC5, panel: 0xCDD6DE, accent: 0x245A8A, text: 0x202D3B, muted: 0x58697B, radius: 16, mono: false)
        case .heritage: return SkinDesign(name: "Heritage", subtitle: "Madeira, âmbar e o charme do rádio de mesa.", category: "ANALÓGICO", background: 0x493122, panel: 0x241F19, accent: 0xF4C779, text: 0xF9E9C8, muted: 0xCFB895, radius: 13, mono: false)
        case .digital: return SkinDesign(name: "Signal 90", subtitle: "Display luminoso. Uma memória dos anos 90.", category: "DIGITAL", background: 0x202630, panel: 0x101A20, accent: 0x72E6CD, text: 0xD4F8EE, muted: 0x94B5B2, radius: 7, mono: true)
        }
    }
}

struct SkinDesign {
    let name: String
    let subtitle: String
    let category: String
    let background: UInt32
    let panel: UInt32
    let accent: UInt32
    let text: UInt32
    let muted: UInt32
    let radius: CGFloat
    let mono: Bool
    var ink: Color { Color(hex: text) }
    var highlight: Color { Color(hex: accent) }
    var secondary: Color { Color(hex: muted) }
}

struct SkinSurface: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let skin: PlayerSkin
    var appearance: MiniAppearance = .solid
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    var body: some View {
        ZStack {
            if appearance == .glass && !reduceTransparency { NativeMiniGlass() }
            Color(hex: design.background).opacity(reduceTransparency || appearance == .solid ? 1 : skin == .studio ? 0.72 : appearance == .glass ? 0.32 : 0.20)
            if appearance != .transparent || reduceTransparency {
                LinearGradient(colors: [.white.opacity(skin == .studio ? 0.06 : 0.08), .clear, .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if skin == .heritage {
                    Canvas { context, size in
                        for line in stride(from: CGFloat(3), to: size.height, by: 4) {
                            var path = Path(); path.move(to: CGPoint(x: 0, y: line)); path.addLine(to: CGPoint(x: size.width, y: line + 2))
                            context.stroke(path, with: .color(.black.opacity(0.09)), lineWidth: 1)
                        }
                    }
                }
            }
        }.allowsHitTesting(false)
    }
}

struct RadioDial: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skin: PlayerSkin
    var frequency: Double? = nil
    var showsLabels = false
    @State private var needlePosition = 0.0
    private var color: Color { skin.design.overridingAccent(palette.accentOverride).highlight }
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 2)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for index in 0...41 {
                        let value = FrequencyScale.lower + Double(index) * 0.5
                        let x = 1 + width * FrequencyScale.position(value)
                        let major = value.truncatingRemainder(dividingBy: 2) == 0
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: major ? 10 : 4))
                        context.stroke(path, with: .color(color.opacity(major ? 0.7 : 0.3)), lineWidth: 1)
                    }
                }
                if showsLabels {
                    ForEach([88, 92, 96, 100, 104, 108], id: \.self) { value in
                        Text(L10n.tr(String(value))).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(skin.design.secondary)
                            .position(x: 1 + width * FrequencyScale.position(Double(value)), y: 25)
                    }
                }
                if frequency != nil {
                    Rectangle().fill(color.opacity(0.16)).frame(width: 9, height: 15).blur(radius: 3)
                        .offset(x: width * needlePosition - 3.5, y: -2)
                    RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 15)
                        .offset(x: width * needlePosition, y: -2)
                }
            }
        }.frame(height: showsLabels ? 34 : 13)
            .onAppear { tune() }
            .onChange(of: frequency) { _ in tune() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(frequency.map { String(format: "Sintonia FM: %.1f megahertz", $0) } ?? "Rádio sem frequência FM informada")
    }
    private func tune() {
        guard let frequency else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.85)) {
            needlePosition = FrequencyScale.position(frequency)
        }
    }
}

struct SkinDisplay: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let skin: PlayerSkin
    let title: String
    let status: String
    var expanded: Bool = false
    var frequency: Double? = nil
    var miniVU = false
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 7 : 3) {
            Text(title).font(.system(size: expanded ? 16 : 11, weight: .semibold, design: design.mono ? .monospaced : skin == .heritage ? .serif : .default)).lineLimit(1)
            Text(L10n.tr(status)).font(.system(size: expanded ? 9 : 8, weight: .medium, design: design.mono ? .monospaced : .default)).foregroundStyle(design.secondary).lineLimit(1)
            if expanded { RadioDial(skin: skin, frequency: frequency) }
        }.foregroundStyle(design.ink).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, expanded ? 12 : 7).padding(.vertical, expanded ? 10 : 5)
            .background { if miniVU { MiniVUBackground() } }
            .background(Color(hex: design.panel).opacity(0.78), in: RoundedRectangle(cornerRadius: skin == .digital ? 3 : 7))
            .overlay(RoundedRectangle(cornerRadius: skin == .digital ? 3 : 7).strokeBorder(design.highlight.opacity(0.15)).allowsHitTesting(false))
    }
}

struct SkinnedMiniPlayer: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var radio: RadioPlayer
    let skin: PlayerSkin
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    private var expanded: Bool { app.miniSize.height >= 110 }
    var body: some View {
        VStack(spacing: expanded ? 8 : 0) {
            if expanded {
                HStack(spacing: 8) {
                    DragHandle().frame(width: 18, height: 18)
                    Text("VITRA / \(design.name.uppercased())").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                    Spacer()
                    options
                }.foregroundStyle(design.secondary)
            }
            HStack(spacing: 6) {
                if !expanded { DragHandle().frame(width: 16, height: 26) }
                SkinDisplay(skin: skin, title: radio.selected.displayName, status: radio.state.isPlaying ? (radio.selected.isLive ? "AO VIVO · STEREO" : "REPRODUZINDO") : radio.state.label, expanded: expanded && app.miniSize.height >= 145, frequency: radio.selected.isLive ? FrequencyScale.fm(radio.selected.frequency) : nil, miniVU: true)
                    .layoutPriority(1)
                if !expanded { controls; options }
                else if app.miniSize.width >= 310 {
                    Image(systemName: skin == .heritage ? "hifispeaker.fill" : "waveform").font(.system(size: 27)).foregroundStyle(design.highlight.opacity(0.6)).frame(width: 38)
                }
            }
            if expanded {
                HStack {
                    Text(skin == .heritage ? "FM / AM" : "STEREO").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(design.secondary)
                    Spacer(minLength: 5)
                    controls
                    Spacer(minLength: 5)
                    Button { app.showMain() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10)).frame(width: 24, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(design.ink).help(L10n.tr("Abrir Vitra Radio"))
                }
            }
        }.padding(.horizontal, expanded ? 13 : 8).padding(.vertical, expanded ? 10 : 4)
            .frame(width: app.miniSize.width, height: app.miniSize.height)
            .background { SkinSurface(skin: skin, appearance: app.miniAppearance) }
            .clipShape(RoundedRectangle(cornerRadius: design.radius))
            .overlay(RoundedRectangle(cornerRadius: design.radius).strokeBorder(design.highlight.opacity(skin == .heritage ? 0.30 : 0.18)).allowsHitTesting(false))
            .environment(\.colorScheme, skin == .studio ? .light : .dark)
            .contextMenu { MiniContextMenu() }
    }
    private var controls: some View {
        HStack(spacing: 3) {
            control("backward.end.fill", help: "Rádio favorita anterior") { radio.step(-1) }
            Button { radio.toggle() } label: {
                Image(systemName: radio.active ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(design.onAccent)
                    .frame(width: 29, height: 29).background(design.highlight, in: RoundedRectangle(cornerRadius: skin == .digital ? 4 : 15)).contentShape(Rectangle())
            }.buttonStyle(.plain).help(radio.active ? L10n.tr("Pausar") : L10n.tr("Reproduzir"))
            control("forward.end.fill", help: "Próxima rádio favorita") { radio.step(1) }
        }
    }
    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10)).frame(width: 22, height: 29).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(design.ink).help(L10n.tr(help))
    }
    private var options: some View {
        Menu { MiniContextMenu() } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).frame(width: 20, height: 24).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(design.ink).help(L10n.tr("Temas e opções"))
    }
}

struct SkinPreview: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    let skin: PlayerSkin
    private var design: SkinDesign { skin.design.overridingAccent(palette.accentOverride) }
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("VITRA / \(design.name.uppercased())").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                Spacer()
                Image(systemName: "ellipsis")
            }.foregroundStyle(design.secondary)
            HStack(spacing: 12) {
                SkinDisplay(skin: skin, title: "Sua frequência", status: "AO VIVO · STEREO", expanded: true, frequency: 94.7)
                Image(systemName: skin == .heritage ? "hifispeaker.fill" : "waveform").font(.system(size: 25)).foregroundStyle(design.highlight)
            }
            HStack(spacing: 18) {
                Text(skin == .heritage ? "FM / AM" : "STEREO").font(.system(size: 7, weight: .bold, design: .monospaced))
                Spacer()
                Image(systemName: "backward.end.fill"); Image(systemName: "play.circle.fill").font(.system(size: 23)); Image(systemName: "forward.end.fill")
            }.font(.system(size: 10)).foregroundStyle(design.highlight)
        }.padding(15).frame(height: 153).background { SkinSurface(skin: skin) }
            .clipShape(RoundedRectangle(cornerRadius: design.radius))
            .overlay(RoundedRectangle(cornerRadius: design.radius).strokeBorder(design.highlight.opacity(0.2)))
            .allowsHitTesting(false)
    }
}

struct PlayerThemesView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var app: AppController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.tr("UM PLAYER. VÁRIAS PERSONALIDADES.")).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(palette.muted)
                        Text(L10n.tr("Vista sua frequência.")).font(.system(size: 29, weight: .semibold)).tracking(-1)
                        Text(L10n.tr("O app inteiro se transforma. Do rádio de mesa ao digital.")).font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Button { app.showMini() } label: { Label(L10n.tr("Abrir miniplayer"), systemImage: "pip") }.buttonStyle(VitraButtonStyle())
                }
                AccentPicker()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(PlayerSkin.allCases) { skin in
                        Button { app.playerSkin = skin } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                if skin == .vitra { ClassicThemePreview() }
                                else { SkinPreview(skin: skin) }
                                HStack {
                                    Text(L10n.tr(skin.design.name)).font(.system(size: 17, weight: .semibold))
                                    Spacer()
                                    if app.playerSkin == skin { Label(L10n.tr("Em uso"), systemImage: "checkmark.circle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.accent) }
                                    else { Text(L10n.tr(skin.design.category)).font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(palette.muted) }
                                }
                                Text(L10n.tr(skin.design.subtitle)).font(.system(size: 11)).foregroundStyle(palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(14).background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(app.playerSkin == skin ? palette.accent.opacity(0.65) : palette.line))
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }
                Text(L10n.tr("A skin muda a janela principal, a navegação, os displays e o miniplayer. Transparência e Liquid Glass continuam disponíveis no miniplayer. Sua escolha fica salva neste Mac.")).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
    }
}
