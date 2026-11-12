import SwiftUI

struct AutomationView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var scheduler: RadioAutomationStore
    @EnvironmentObject private var radio: RadioPlayer
    @State private var editing: RadioAutomation?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.tr("SUA RÁDIO. NA HORA CERTA.")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(palette.muted)
                        Text(L10n.tr("Automação.")).font(.system(size: 29, weight: .semibold)).tracking(-1)
                        Text(L10n.tr("Programe por dias da semana ou por uma data específica.")).font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Button { editing = RadioAutomation(station: Station.Saved(radio.selected.isLive ? radio.selected : (radio.library.first ?? Station.placeholder))) } label: {
                        Label(L10n.tr("Novo horário"), systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(12).foregroundStyle(palette.onAccent).background(palette.accent, in: Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain).disabled(!radio.library.contains(where: { $0.isLive }))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.tr("Horário local do Mac · \(TimeZone.current.identifier)"), systemImage: "clock").font(.system(size: 12, weight: .semibold))
                    Text(L10n.tr("O app precisa estar aberto e o Mac acordado. Funciona com a janela fechada, pela barra de menus. Ao reabrir ou acordar, a programação retoma a faixa que estiver dentro do período atual; faixas já encerradas são ignoradas.")).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(L10n.tr("Períodos podem se sobrepor: a rádio que começa depois assume e, ao terminar, a anterior retoma se ainda estiver no seu período. Se começarem juntas, a faixa mais curta toca primeiro. Programações por data específica têm prioridade durante todo o período, mesmo com início igual ao de uma semanal. Uma troca manual vale até a próxima transição programada.")).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    if let next = scheduler.nextRule() {
                        Text("Próxima troca: \(next.0.station.name) · \(L10n.date(next.1))").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.accent)
                    }
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 13))
                if let error { Label(L10n.tr(error), systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange) }
                if scheduler.rules.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 36, weight: .light)).foregroundStyle(palette.accent)
                        Text(L10n.tr("Uma trilha para cada momento.")).font(.system(size: 20, weight: .semibold))
                        Text(L10n.tr("Escolha uma rádio para a manhã, outra para a tarde.\nCada horário pode ter seus próprios dias da semana.")).font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(palette.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 44)
                }
                ForEach(scheduler.rules) { rule in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr(rule.timeLabel)).font(.system(size: 23, weight: .medium, design: .monospaced))
                            Text(rule.endLabel.map { L10n.tr("até ") + $0 + (rule.endsNextDay ? L10n.tr(" +1 dia") : "") } ?? L10n.tr("Sem término")).font(.system(size: 10, weight: .medium, design: .monospaced))
                        }.foregroundStyle(rule.enabled ? palette.accent : palette.muted).frame(width: 115, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rule.name.isEmpty ? rule.station.name : rule.name).font(.system(size: 14, weight: .semibold))
                            Text((rule.name.isEmpty ? "" : rule.station.name + " · ") + rule.daysLabel).font(.system(size: 11)).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Toggle(L10n.tr("Ativa"), isOn: Binding(get: { rule.enabled }, set: { error = scheduler.setEnabled(rule, $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel("Ativar \(rule.station.name) às \(rule.timeLabel)")
                        Button { editing = rule } label: { Image(systemName: "pencil").frame(width: 28, height: 30).contentShape(Rectangle()) }.buttonStyle(.plain).help(L10n.tr("Editar horário"))
                        Button { scheduler.remove(rule.id); error = nil } label: { Image(systemName: "trash").frame(width: 28, height: 30).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(palette.muted).help(L10n.tr("Remover horário"))
                    }.padding(17).background(palette.surface, in: RoundedRectangle(cornerRadius: 13))
                }
                if let message = scheduler.lastMessage { Text(L10n.tr("Última execução nesta sessão: \(message)")).font(.system(size: 11)).foregroundStyle(palette.muted) }
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 30)
        }.scrollIndicators(.hidden).sheet(item: $editing) { rule in AutomationForm(rule: rule) }
            .onAppear {
                if CommandLine.arguments.contains("--automation-form-preview") {
                    editing = RadioAutomation(station: Station.Saved(Station.all[0]), hour: 10, specificDate: CommandLine.arguments.contains("--automation-date-preview") ? AutomationDate(Date()) : nil)
                }
            }
    }
}

struct AutomationForm: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scheduler: RadioAutomationStore
    @EnvironmentObject private var radio: RadioPlayer
    @State private var draft: RadioAutomation
    @State private var error: String?
    init(rule: RadioAutomation) {
        var rule = rule
        if rule.endHour == nil { rule.endHour = (rule.hour + 1) % 24; rule.endMinute = rule.minute }
        _draft = State(initialValue: rule)
    }
    @State private var startHourValid = true
    @State private var startMinuteValid = true
    @State private var endHourValid = true
    @State private var endMinuteValid = true
    private var validFields: Bool { startHourValid && startMinuteValid && endHourValid && endMinuteValid }
    @State private var choosingRadio = false
    @State private var radioSearch = ""
    private var matchingStations: [Station] {
        radio.library.filter { $0.isLive && (radioSearch.isEmpty || "\($0.name) \($0.frequency) \($0.genre)".localizedCaseInsensitiveContains(radioSearch)) }
            .sorted { left, right in
                let a = radio.isFavorite(left), b = radio.isFavorite(right)
                if a != b { return a }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text(L10n.tr("Programar rádio")).font(.system(size: 23, weight: .semibold))
            Text(L10n.tr("Escolha a rádio, o período e quando executar.")).font(.system(size: 12)).foregroundStyle(palette.muted)
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.tr("NOME DA AUTOMAÇÃO")).font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(palette.muted)
                TextField(L10n.tr("Opcional · ex.: Foco da manhã"), text: $draft.name).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(13).background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.line))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.tr("RÁDIO")).font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(palette.muted)
                Button { radioSearch = ""; choosingRadio.toggle() } label: {
                    HStack(spacing: 11) {
                        if let station = draft.station.station {
                            StationArtwork(station: radio.canonical(station)).frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.station.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.text)
                            Text(draft.station.frequency + " · " + draft.station.genre).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                        }
                        Spacer()
                        Text(L10n.tr("Alterar")).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.accent)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.muted)
                    }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.accent.opacity(0.25))).contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).popover(isPresented: $choosingRadio, arrowEdge: .bottom) { radioChoices }
                Text(L10n.tr("As favoritas aparecem primeiro. Outras rádios ouvidas no catálogo também ficam disponíveis.")).font(.system(size: 10)).foregroundStyle(palette.muted)
            }
            VStack(spacing: 10) {
                timeRow("Início", hour: $draft.hour, minute: $draft.minute, hourValid: $startHourValid, minuteValid: $startMinuteValid)
                timeRow("Término", hour: Binding(get: { draft.endHour ?? 10 }, set: { draft.endHour = $0 }), minute: Binding(get: { draft.endMinute ?? 0 }, set: { draft.endMinute = $0 }), hourValid: $endHourValid, minuteValid: $endMinuteValid)
                if !validFields {
                    Text(L10n.tr("Digite horas de 00 a 23 e minutos de 00 a 59.")).font(.system(size: 10)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                } else if draft.endsNextDay {
                    Text(L10n.tr("O término será no dia seguinte à data ou ao dia de início.")).font(.system(size: 10)).foregroundStyle(palette.accent).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 10) {
                scheduleOption("Semanal", subtitle: "Repete nos dias escolhidos", icon: "repeat", dated: false)
                scheduleOption("Data específica", subtitle: "Uma vez · prioridade", icon: "calendar.badge.clock", dated: true)
            }
            if draft.specificDate != nil {
                AutomationDateField(selection: $draft.specificDate)
                Text(L10n.tr("Executa uma única vez nesta data e tem prioridade sobre as semanais até o término. Depois, a programação normal retoma.")).font(.system(size: 11)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            } else {
            HStack {
                Text(L10n.tr("Repetir")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(L10n.tr("Dias úteis")) { draft.weekdays = [2,3,4,5,6] }.buttonStyle(VitraButtonStyle(compact: true))
                Button(L10n.tr("Todos")) { draft.weekdays = Set(1...7) }.buttonStyle(VitraButtonStyle(compact: true))
            }
            HStack(spacing: 7) {
                ForEach(RadioAutomation.days, id: \.0) { day, name in
                    Button {
                        if draft.weekdays.contains(day) { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                    } label: {
                        Text(L10n.tr(name)).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(draft.weekdays.contains(day) ? palette.accent : palette.muted)
                            .background(draft.weekdays.contains(day) ? palette.accent.opacity(0.13) : palette.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(draft.weekdays.contains(day) ? palette.accent.opacity(0.6) : palette.line)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            }
            Toggle(L10n.tr("Automação ativa"), isOn: $draft.enabled).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            if let validation = scheduler.validationError(for: draft) ?? error {
                Label(L10n.tr(validation), systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Button(L10n.tr("Cancelar")) { dismiss() }.buttonStyle(VitraButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    error = scheduler.save(draft)
                    if error == nil { dismiss() }
                } label: { Label(L10n.tr("Salvar horário"), systemImage: "checkmark") }
                    .buttonStyle(VitraButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(!validFields || scheduler.validationError(for: draft) != nil)
            }
        }.padding(27).frame(width: 575, height: 710).foregroundStyle(palette.text).background(palette.background)
            .onChange(of: draft) { _ in error = nil }
    }
    private func scheduleOption(_ title: String, subtitle: String, icon: String, dated: Bool) -> some View {
        let selected = (draft.specificDate != nil) == dated
        return Button {
            draft.specificDate = dated ? (draft.specificDate ?? AutomationDate(Date())) : nil
            draft.dayOfMonth = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(selected ? palette.accent : palette.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr(title)).font(.system(size: 12, weight: .semibold))
                    Text(L10n.tr(subtitle)).font(.system(size: 9)).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? palette.accent : palette.muted)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? palette.accent.opacity(0.10) : palette.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? palette.accent.opacity(0.65) : palette.line))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func timeRow(_ title: String, hour: Binding<Int>, minute: Binding<Int>, hourValid: Binding<Bool>, minuteValid: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Label(title == "Início" ? L10n.tr("Início do período") : L10n.tr(title), systemImage: title == "Início" ? "play.circle" : "stop.circle").font(.system(size: 12, weight: .semibold))
            Spacer()
            TimeNumberField(value: hour, valid: hourValid, range: 0...23, title: L10n.tr("Hora de \(title == "Início" ? L10n.tr("Início do período") : L10n.tr(title))"))
            Text(":").font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(palette.muted)
            TimeNumberField(value: minute, valid: minuteValid, range: 0...59, title: L10n.tr("Minuto de \(title == "Início" ? L10n.tr("Início do período") : L10n.tr(title))"))
        }
    }
    private var radioChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Escolher rádio")).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField(L10n.tr("Buscar por nome, frequência ou estilo"), text: $radioSearch).textFieldStyle(.plain).font(.system(size: 12))
            }.padding(11).background(palette.surface, in: RoundedRectangle(cornerRadius: 9))
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(matchingStations) { station in
                        Button {
                            draft.station = Station.Saved(station)
                            choosingRadio = false
                        } label: {
                            HStack(spacing: 11) {
                                StationArtwork(station: station).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(station.name).font(.system(size: 12, weight: .semibold))
                                    Text(station.frequency + " · " + station.genre).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                                }
                                Spacer()
                                if radio.isFavorite(station) { Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(palette.muted) }
                                if draft.station.id == station.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent) }
                            }.padding(10).foregroundStyle(palette.text)
                                .background(draft.station.id == station.id ? palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if matchingStations.isEmpty { Text(L10n.tr("Nenhuma rádio encontrada.")).font(.system(size: 12)).foregroundStyle(palette.muted).padding(20) }
                }
            }
        }.padding(17).frame(width: 420, height: 350).background(palette.background).foregroundStyle(palette.text)

    }

}
