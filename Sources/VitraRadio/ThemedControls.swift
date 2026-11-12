import SwiftUI

struct VitraButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var enabled
    var prominent = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 11 : 12, weight: .semibold))
            .padding(.horizontal, compact ? 10 : 17).padding(.vertical, compact ? 7 : 12)
            .foregroundStyle(prominent ? palette.onAccent : palette.text)
            .background(prominent ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: compact ? 7 : 10))
            .overlay(RoundedRectangle(cornerRadius: compact ? 7 : 10).strokeBorder(prominent ? .clear : palette.line))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ClassicThemePreview: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    private var previewAccent: Color { Color(hex: palette.accentOverride ?? PlayerSkin.vitra.design.accent) }
    private var previewInk: Color { AccentColors.ink(on: palette.accentOverride ?? PlayerSkin.vitra.design.accent) }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) { Image(systemName: "waveform").foregroundStyle(previewAccent); Text("vitra").fontWeight(.bold) }.font(.system(size: 10))
                    ForEach(["Início", "Todas as rádios", "Favoritas", "Meu servidor", "Temas"], id: \.self) { text in
                        Text(L10n.tr(text)).font(.system(size: 6, weight: .semibold)).foregroundStyle(text == "Início" ? previewAccent : Color(hex: 0x8D9A90)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(10).frame(width: geometry.size.width * 0.24).background(Color(hex: 0x151A17))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("O seu dia tem trilha.")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xF1F4EC))
                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("Uma boa trilha\nmuda tudo.")).font(.system(size: 10, weight: .medium))
                            Text(L10n.tr("Ouvir agora")).font(.system(size: 5, weight: .bold)).padding(5).foregroundStyle(previewInk).background(previewAccent, in: Capsule())
                        }.foregroundStyle(Color(hex: 0xF1F4EC))
                        Spacer(minLength: 0)
                        StationArtwork(station: Station.demo[0], hero: true).frame(width: 65, height: 58).clipped()
                    }.padding(9).background(Color(hex: 0x232F25), in: RoundedRectangle(cornerRadius: 7))
                    HStack(spacing: 5) {
                        ForEach(Station.demo.prefix(2)) { station in
                            HStack(spacing: 4) {
                                StationArtwork(station: station).frame(width: 17, height: 17).clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(station.name).font(.system(size: 6, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(5).background(Color(hex: 0x1C231E), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }.foregroundStyle(Color(hex: 0xF1F4EC))
                    Spacer(minLength: 0)
                }.padding(11).frame(maxWidth: .infinity)
            }.background(Color(hex: 0x101411))
        }.frame(height: 153).clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(previewAccent.opacity(0.2)))
            .allowsHitTesting(false)
    }
}
