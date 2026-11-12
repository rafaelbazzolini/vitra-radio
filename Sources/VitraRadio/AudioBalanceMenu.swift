import SwiftUI

struct AudioBalanceMenu: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        Menu {
            Toggle(L10n.tr("Equilibrar volume entre rádios"), isOn: $radio.volumeBalancingEnabled)
            Divider()
            Text(L10n.tr(radio.volumeBalanceStatus))
            Text(L10n.tr("Ajuste gradual de nível e proteção contra picos."))
            Text(L10n.tr("Seu volume e o volume do Mac são preservados."))
        } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                .foregroundStyle(radio.volumeBalancingEnabled ? palette.accent : palette.muted)
                .frame(width: 26, height: 28).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(L10n.tr("Equilíbrio automático de volume"))
    }
}
