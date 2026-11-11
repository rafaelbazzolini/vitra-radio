import SwiftUI

struct AudioBalanceMenu: View {
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var radio: RadioPlayer
    var body: some View {
        Menu {
            Toggle("Equilibrar volume entre rádios", isOn: $radio.volumeBalancingEnabled)
            Divider()
            Text(radio.volumeBalanceStatus)
            Text("Ajuste gradual de nível e proteção contra picos.")
            Text("Seu volume e o volume do Mac são preservados.")
        } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                .foregroundStyle(radio.volumeBalancingEnabled ? palette.accent : palette.muted)
                .frame(width: 26, height: 28).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Equilíbrio automático de volume")
    }
}
