import SwiftUI
import AppKit

extension SkinDesign {
    func overridingAccent(_ hex: UInt32?) -> SkinDesign {
        let chosen = hex ?? accent
        let resolved = name == "Studio" ? AccentColors.readable(chosen, on: panel) : chosen
        return SkinDesign(name: name, subtitle: subtitle, category: category, background: background, panel: panel, accent: resolved, text: text, muted: muted, radius: radius, mono: mono)
    }
    var onAccent: Color { AccentColors.ink(on: accent) }
}

enum AccentColors {
    static let presets: [(String, UInt32)] = [("Lima", 0xC3F47A), ("Azul", 0x78B7FF), ("Violeta", 0xBCA2FF), ("Coral", 0xFF9881), ("Âmbar", 0xF4C779), ("Turquesa", 0x72E6CD)]
    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ value: UInt32) -> Double { let c = Double(value) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear((hex >> 16) & 255) + 0.7152 * linear((hex >> 8) & 255) + 0.0722 * linear(hex & 255)
    }
    static func contrast(_ left: UInt32, _ right: UInt32) -> Double {
        let a = luminance(left), b = luminance(right)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    static func readable(_ hex: UInt32, on background: UInt32) -> UInt32 {
        if contrast(hex, background) >= 4.5 { return hex }
        for step in 1...24 {
            let factor = 1 - Double(step) / 24
            let r = UInt32((Double((hex >> 16) & 255) * factor).rounded())
            let g = UInt32((Double((hex >> 8) & 255) * factor).rounded())
            let b = UInt32((Double(hex & 255) * factor).rounded())
            let candidate = r << 16 | g << 8 | b
            if contrast(candidate, background) >= 4.5 { return candidate }
        }
        return 0
    }
    static func ink(on hex: UInt32) -> Color { luminance(hex) > 0.179 ? Color(hex: 0x101411) : .white }
    static func hex(_ color: Color) -> UInt32? {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
    }
}

struct AccentPicker: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var app: AppController
    @Environment(\.appPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("Cor de destaque")).font(.system(size: 16, weight: .semibold))
                    Text(L10n.tr("A cor é independente da skin e acompanha todo o app.")).font(.system(size: 11)).foregroundStyle(palette.muted)
                }
                Spacer()
                Button(L10n.tr("Padrão da skin")) { app.accentColorHex = nil }.font(.system(size: 11)).disabled(app.accentColorHex == nil)
            }
            HStack(spacing: 14) {
                ForEach(AccentColors.presets, id: \.0) { name, hex in
                    Button { app.accentColorHex = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                            .overlay { if app.accentColorHex == hex { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(AccentColors.ink(on: hex)) } }
                            .padding(3).overlay(Circle().strokeBorder(app.accentColorHex == hex ? palette.text.opacity(0.6) : .clear))
                            .contentShape(Circle())
                    }.buttonStyle(.plain).help(L10n.tr(name)).accessibilityLabel(L10n.tr(name))
                }
                Spacer()
                ColorPicker("Personalizar", selection: Binding(get: { Color(hex: app.accentColorHex ?? app.playerSkin.design.accent) }, set: { if let hex = AccentColors.hex($0) { app.accentColorHex = hex } }), supportsOpacity: false).font(.system(size: 11)).fixedSize()
            }
        }.padding(17).background(palette.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}
