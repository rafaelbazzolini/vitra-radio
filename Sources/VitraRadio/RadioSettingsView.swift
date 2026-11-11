import SwiftUI

struct RadioSettingsView: View {
    @Environment(\.appPalette) private var palette
    @AppStorage("settingsTab") private var tab = "Servidor"
    private let tabs = ["Servidor", "Temas", "Automação", "Miniplayer", "Atualizações"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ajustes").font(.system(size: 27, weight: .semibold)).padding(.bottom, 18)
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .foregroundStyle(tab == item ? palette.onAccent : palette.muted)
                            .background(tab == item ? palette.accent : palette.surface, in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 16)
            Group {
                switch tab {
                case "Temas": PlayerThemesView()
                case "Automação": AutomationView()
                case "Miniplayer": MiniSettingsView()
                case "Atualizações": UpdateSettingsView()
                default: MusicServerView(configurationOnly: true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.horizontal, 24).padding(.top, 38).foregroundStyle(palette.text)
            .onAppear { if CommandLine.arguments.contains("--mini-settings-preview") { tab = "Miniplayer" }; if CommandLine.arguments.contains("--updates-preview") { tab = "Atualizações" } }
    }
}

struct MiniSettingsView: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.appPalette) private var palette
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Miniplayer").font(.system(size: 24, weight: .semibold))
                Text("Acompanhe sua música ao lado da Dock. Arraste o canto superior para redimensionar livremente.")
                    .font(.system(size: 12)).foregroundStyle(palette.muted)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Aparência").font(.headline)
                    SettingsOptions(selection: $app.miniAppearance, options: MiniAppearance.allCases.map { ($0.title, $0) })
                    Toggle("Manter sobre outras janelas", isOn: $radio.alwaysOnTop)
                    HStack {
                        Text("Largura")
                        Slider(value: Binding(get: { Double(app.miniSize.width) }, set: { app.setMiniSize(CGSize(width: $0, height: app.miniSize.height)) }), in: 230...620)
                        Text("\(Int(app.miniSize.width)) px").monospacedDigit().frame(width: 55)
                    }
                    HStack {
                        Text("Altura")
                        Slider(value: Binding(get: { Double(app.miniSize.height) }, set: { app.setMiniSize(CGSize(width: app.miniSize.width, height: $0)) }), in: 44...200)
                        Text("\(Int(app.miniSize.height)) px").monospacedDigit().frame(width: 55)
                    }
                    Divider()
                    Text("VU no fundo do display").font(.headline)
                    SettingsOptions(selection: $app.miniVUStyle, options: [("Desligado", .off), ("Digital", .digital), ("Analógico", .analog)])
                    Text("Reage ao áudio em tempo real, por trás do nome e do status da rádio. Independente do VU da janela principal.")
                        .font(.system(size: 12)).foregroundStyle(palette.muted)
                }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                HStack {
                    Button("Ajustar à altura da Dock") { app.fitMiniToDock() }.buttonStyle(VitraButtonStyle())
                    Button("Abrir miniplayer") { app.showMini() }.buttonStyle(VitraButtonStyle())
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Decorative, non-interactive audio meters behind the station lettering.
struct MiniVUBackground: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if app.miniVUStyle != .off {
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.12 : 1.0 / 30)) { _ in
                Canvas { context, size in
                    let enabled = radio.state.isPlaying && !radio.muted
                    let levels = radio.audioLevels.read()
                    if app.miniVUStyle == .digital {
                        let left = radio.audioLevels.spectrum(right: false)
                        let right = radio.audioLevels.spectrum(right: true)
                        let gap: CGFloat = 2
                        let width = max(1, (size.width - gap * 7) / 8)
                        for band in 0..<8 {
                            let amplitude = enabled ? max(left[band], right[band]) * radio.volume : 0
                            let db = amplitude > 0.00001 ? 20 * log10(amplitude) : -70
                            let value = max(0, min(1, (db + 70) / 60))
                            for row in 0..<12 {
                                let rect = CGRect(x: CGFloat(band) * (width + gap), y: size.height - CGFloat(row + 1) * size.height / 12, width: width, height: max(1, size.height / 12 - 2))
                                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(palette.accent.opacity(value > Double(row) / 12 ? 0.20 : 0.025)))
                            }
                        }
                    } else {
                        for channel in 0..<2 {
                            let amplitude = enabled ? (channel == 0 ? levels.0 : levels.1) * radio.volume : 0
                            let db = amplitude > 0.00001 ? 20 * log10(amplitude) : -60
                            let value = max(0, min(1, (db + 60) / 60))
                            let pivot = CGPoint(x: size.width * (channel == 0 ? 0.27 : 0.77), y: size.height * 0.97)
                            let radius = min(size.width * 0.24, size.height * 0.85)
                            for tick in 0...10 {
                                let angle = (-150 + Double(tick) * 12) * Double.pi / 180
                                var path = Path()
                                path.move(to: CGPoint(x: pivot.x + cos(angle) * (radius - 4), y: pivot.y + sin(angle) * (radius - 4)))
                                path.addLine(to: CGPoint(x: pivot.x + cos(angle) * radius, y: pivot.y + sin(angle) * radius))
                                context.stroke(path, with: .color(palette.accent.opacity(0.18)), lineWidth: 1)
                            }
                            let angle = (-150 + value * 120) * Double.pi / 180
                            var needle = Path(); needle.move(to: pivot)
                            needle.addLine(to: CGPoint(x: pivot.x + cos(angle) * radius, y: pivot.y + sin(angle) * radius))
                            context.stroke(needle, with: .color(palette.accent.opacity(0.28)), lineWidth: 2)
                        }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 6)).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct SettingsOptions<Value: Hashable>: View {
    @Environment(\.appPalette) private var palette
    @Binding var selection: Value
    let options: [(String, Value)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.1) { title, value in
                Button { selection = value } label: {
                    HStack(spacing: 7) {
                        if selection == value { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                        Text(title).font(.system(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 13)
                        .foregroundStyle(selection == value ? palette.accent : palette.muted)
                        .background(selection == value ? palette.accent.opacity(0.12) : palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection == value ? palette.accent.opacity(0.5) : palette.line))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}
