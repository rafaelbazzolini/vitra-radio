import SwiftUI

struct UpdateBanner: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.appPalette) private var palette
    var body: some View {
        if updates.bannerVisible {
            HStack(spacing: 12) {
                if updates.installing || updates.checking { ProgressView().controlSize(.small) }
                else { Image(systemName: updates.error == nil ? "arrow.down.circle.fill" : "exclamationmark.circle").foregroundStyle(palette.accent) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(updates.installing ? L10n.tr("Atualizando o Vitra Radio") : updates.available.map { L10n.tr("Vitra Radio \($0.version) disponível") } ?? L10n.tr("Atualizações"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(updates.error.map { L10n.tr($0) } ?? updates.detail.map { L10n.tr($0) } ?? L10n.tr("Atualize por aqui. Suas rádios e configurações serão mantidas."))
                        .font(.system(size: 11)).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 8)
                if updates.available != nil && !updates.installing {
                    Button(L10n.tr("Atualizar e reiniciar")) { updates.install() }.buttonStyle(VitraButtonStyle())
                        .disabled(updates.checking)
                }
                if !updates.installing {
                    Button { updates.dismissed = true } label: {
                        Image(systemName: "xmark").frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L10n.tr("Lembrar depois"))
                }
            }.padding(14).padding(.top, 25).foregroundStyle(palette.text)
                .background(palette.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.accent.opacity(0.25)).frame(height: 1) }
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.appPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "arrow.triangle.2.circlepath.circle").font(.system(size: 38, weight: .light)).foregroundStyle(palette.accent)
            Text(L10n.tr("Sempre na sua frequência.")).font(.system(size: 25, weight: .semibold))
            Text("Vitra Radio \(updates.currentVersion)").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(palette.muted)
            Text(L10n.tr("O Vitra procura novas versões ao abrir e a cada hora. Quando houver uma atualização, o aviso aparece dentro do app. Ao atualizar, ele prepara a nova versão e reinicia automaticamente."))
                .font(.system(size: 13)).foregroundStyle(palette.muted).lineSpacing(4)
            Text(L10n.tr("Suas rádios, favoritas, temas, servidores e automações continuam neste Mac.")).font(.system(size: 12)).foregroundStyle(palette.muted)
            if let date = updates.lastCheck { Text(L10n.tr("Última verificação: \(L10n.date(date))")).font(.system(size: 11)).foregroundStyle(palette.muted) }
            HStack(spacing: 12) {
                Button(updates.checking ? L10n.tr("Buscando…") : L10n.tr("Buscar atualizações")) { updates.check(manual: true) }
                    .buttonStyle(VitraButtonStyle()).disabled(updates.checking || updates.installing)
                if updates.available != nil {
                    Button(L10n.tr("Atualizar e reiniciar")) { updates.install() }.buttonStyle(VitraButtonStyle()).disabled(updates.installing)
                }
            }
            Spacer()
        }.padding(28).frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
