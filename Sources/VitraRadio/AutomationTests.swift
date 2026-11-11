import Foundation

@MainActor enum AutomationTests {
    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL"): \(label)")
            if !value { failures += 1 }
        }
        let domain = "com.vitra.radio.automation-tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        let store = RadioAutomationStore(preferences: preferences)
        var morning = RadioAutomation(station: Station.Saved(Station.all[0]), weekdays: [2,3], hour: 9, minute: 0)
        check(store.save(morning) == nil, "Automação salva rádio, dias e horário")
        var conflict = RadioAutomation(station: Station.Saved(Station.all[1]), weekdays: [3], hour: 9, minute: 0)
        check(store.save(conflict) != nil && store.rules.count == 1, "Períodos idênticos no mesmo dia são rejeitados")
        let separateDay = RadioAutomation(station: Station.Saved(Station.all[1]), weekdays: [4], hour: 9, minute: 0)
        check(store.save(separateDay) == nil, "Mesmo horário em dias diferentes é permitido")
        conflict.enabled = false
        check(store.save(conflict) == nil, "Regra desativada pode ser guardada sem reservar horário")
        check(store.setEnabled(conflict, true) != nil, "Reativar regra conflitante é bloqueado")
        var afternoon = RadioAutomation(station: Station.Saved(Station.all[2]), weekdays: [2], hour: 14, minute: 30)
        check(store.save(afternoon) == nil, "Outra rádio pode tocar em outro horário do dia")
        morning.name = "Manhã"
        check(store.save(morning) == nil && store.rules.filter { $0.id == morning.id }.count == 1, "Editar a própria regra não causa conflito nem duplicação")
        var invalid = afternoon; invalid.weekdays = []
        check(store.save(invalid) != nil, "Automação exige pelo menos um dia")
        invalid = afternoon; invalid.hour = 24
        check(store.save(invalid) != nil, "Horários fora de 00:00 a 23:59 são rejeitados")
        let restored = RadioAutomationStore(preferences: preferences)
        check(restored.rules.count == 4 && restored.rules.first(where: { $0.id == morning.id })?.station.id == Station.all[0].id, "Agendamentos e rádio persistem ao reabrir")
        var fired: [String] = []
        let monday = date("2026-11-09T09:00:10Z")
        store.evaluate(now: monday, calendar: calendar) { fired.append($0.station.id) }
        check(fired == [Station.all[0].id], "No dia e minuto corretos dispara a rádio escolhida")
        store.evaluate(now: monday.addingTimeInterval(20), calendar: calendar) { fired.append($0.station.id) }
        check(fired.count == 1, "O mesmo agendamento não repete dentro do minuto")
        let afterRun = RadioAutomationStore(preferences: preferences)
        afterRun.evaluate(now: monday.addingTimeInterval(30), calendar: calendar) { fired.append($0.station.id) }
        check(fired.count == 1, "Reabrir o app no mesmo minuto não repete a execução")
        store.evaluate(now: date("2026-11-09T09:01:00Z"), calendar: calendar) { fired.append($0.station.id) }
        check(fired.count == 1, "Horário perdido não é executado depois")
        store.evaluate(now: date("2026-11-09T14:30:00Z"), calendar: calendar) { fired.append($0.station.id) }
        check(fired.last == Station.all[2].id && fired.count == 2, "A programação troca para outra rádio durante o dia")
        store.evaluate(now: date("2026-11-16T09:00:00Z"), calendar: calendar) { fired.append($0.station.id) }
        check(fired.count == 3 && fired.last == Station.all[0].id, "Repetição semanal volta a executar na semana seguinte")
        let next = morning.nextDate(after: date("2026-11-09T08:00:00Z"), calendar: calendar)
        check(next == date("2026-11-09T09:00:00Z"), "Próxima execução usa o calendário local informado")
        afternoon.hour = 9; afternoon.minute = 0
        check(store.save(afternoon) != nil, "Editar para um período idêntico é bloqueado")
        store.remove(morning.id)
        check(store.setEnabled(conflict, true) == nil, "Excluir regra libera o horário para outra rádio")
        check(RadioAutomationStore(preferences: preferences).rules.count == 3, "Excluir automação persiste a remoção")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstRule = RadioAutomation(station: Station.Saved(Station.all[3]), weekdays: [1], hour: 1, minute: 30)
        check(store.save(dstRule) == nil, "Regra de domingo salva para validar mudança de horário")
        var dstFires = 0
        store.evaluate(now: date("2026-11-01T05:30:00Z"), calendar: dstCalendar) { _ in dstFires += 1 }
        store.evaluate(now: date("2026-11-01T06:30:00Z"), calendar: dstCalendar) { _ in dstFires += 1 }
        check(dstFires == 1, "Hora local repetida no horário de verão não dispara duas vezes")
        let periodDomain = domain + ".periods"
        let periodPreferences = UserDefaults(suiteName: periodDomain)!
        defer { periodPreferences.removePersistentDomain(forName: periodDomain) }
        let periods = RadioAutomationStore(preferences: periodPreferences)
        let first = RadioAutomation(station: Station.Saved(Station.all[0]), weekdays: [2], hour: 9, minute: 0, endHour: 10, endMinute: 0)
        let second = RadioAutomation(station: Station.Saved(Station.all[1]), weekdays: [2], hour: 10, minute: 0, endHour: 11, endMinute: 0)
        check(periods.save(first) == nil && periods.save(second) == nil, "Períodos consecutivos são permitidos")
        let overlap = RadioAutomation(station: Station.Saved(Station.all[2]), weekdays: [2], hour: 9, minute: 30, endHour: 10, endMinute: 30)
        check(periods.save(overlap) == nil, "Períodos sobrepostos são aceitos para mesclagem")
        periods.remove(overlap.id)
        var sameEnds = first; sameEnds.endHour = 9
        check(periods.save(sameEnds) != nil, "Início igual ao término é rejeitado")
        let night = RadioAutomation(station: Station.Saved(Station.all[0]), weekdays: [7], hour: 22, minute: 0, endHour: 6, endMinute: 0)
        let sunday = RadioAutomation(station: Station.Saved(Station.all[1]), weekdays: [1], hour: 5, minute: 0, endHour: 7, endMinute: 0)
        check(night.endsNextDay && night.overlaps(sunday), "Conflito noturno atravessa meia-noite e a virada da semana")
        var adjacentNight = sunday; adjacentNight.hour = 6
        check(!night.overlaps(adjacentNight), "Faixa seguinte pode começar exatamente no fim da faixa noturna")
        var events: [String] = []
        periods.evaluate(now: date("2026-11-09T09:00:00Z"), calendar: calendar, finish: { _ in events.append("fim") }) { _ in events.append("início") }
        periods.evaluate(now: date("2026-11-09T09:59:00Z"), calendar: calendar, finish: { _ in events.append("fim") }) { _ in events.append("início") }
        check(events == ["início"], "Rádio permanece no ar até o horário final")
        periods.evaluate(now: date("2026-11-09T10:00:00Z"), calendar: calendar, finish: { _ in events.append("fim") }) { _ in events.append("início") }
        check(events == ["início", "fim", "início"], "Na transição encerra a faixa anterior antes de iniciar a próxima")
        periods.evaluate(now: date("2026-11-09T11:15:00Z"), calendar: calendar, finish: { _ in events.append("fim") }) { _ in events.append("início") }
        check(events.last == "fim" && events.count == 4, "Fim vencido durante repouso é processado ao retornar")
        periods.evaluate(now: date("2026-11-09T11:16:00Z"), calendar: calendar, finish: { _ in events.append("fim") }) { _ in events.append("início") }
        check(events.count == 4, "Término não executa duas vezes")
        check(night.endingDate(for: date("2026-11-14T22:00:00Z"), calendar: calendar) == date("2026-11-15T06:00:00Z"), "Horário final noturno cai no dia seguinte")
        check(RadioAutomationStore(preferences: periodPreferences).rules.first?.endHour == 10, "Horário final persiste ao reabrir")
        let manual = RadioPlayer(preferences: periodPreferences, updatesSystemMedia: false)
        let intent = manual.playbackIntentID
        manual.pause()
        check(manual.playbackIntentID != intent, "Ação manual invalida o controle da sessão automatizada")
        manual.shutdown()
        let studio = PlayerSkin.studio.design.overridingAccent(0xC3F47A)
        check(AccentColors.contrast(studio.accent, studio.panel) >= 4.5, "Destaques claros no Studio mantêm contraste legível")
        let mixDomain = domain + ".mix"
        let mixPreferences = UserDefaults(suiteName: mixDomain)!
        defer { mixPreferences.removePersistentDomain(forName: mixDomain) }
        let mix = RadioAutomationStore(preferences: mixPreferences)
        let base = RadioAutomation(station: Station.Saved(Station.all[0]), weekdays: [2], hour: 9, minute: 0, endHour: 20, endMinute: 0)
        let insert = RadioAutomation(station: Station.Saved(Station.all[1]), weekdays: [2], hour: 13, minute: 0, endHour: 14, endMinute: 0)
        let nested = RadioAutomation(station: Station.Saved(Station.all[2]), weekdays: [2], hour: 13, minute: 15, endHour: 13, endMinute: 30)
        check(mix.save(base) == nil && mix.save(insert) == nil && mix.save(nested) == nil, "Três faixas aninhadas são aceitas")
        var duplicate = insert; duplicate.id = UUID(); duplicate.station = Station.Saved(Station.all[3])
        check(mix.save(duplicate) != nil, "Início e término idênticos no mesmo dia são bloqueados")
        duplicate.weekdays = [3]
        check(mix.save(duplicate) == nil, "Períodos idênticos em dias diferentes são permitidos")
        var timeline: [String] = []
        for stamp in ["09:00", "13:00", "13:15", "13:30", "14:00", "20:00"] {
            mix.evaluate(now: date("2026-11-09T" + stamp + ":00Z"), calendar: calendar, finish: { _ in }) { timeline.append($0.station.id) }
        }
        check(timeline == [base.station.id, insert.station.id, nested.station.id, insert.station.id, base.station.id], "Faixas aninhadas interrompem e retomam na ordem correta")
        let manualMix = RadioAutomationStore(preferences: UserDefaults(suiteName: mixDomain + ".manual")!)
        defer { UserDefaults.standard.removePersistentDomain(forName: mixDomain + ".manual") }
        _ = manualMix.save(base); _ = manualMix.save(insert)
        var manualTimeline: [String] = []
        manualMix.evaluate(now: date("2026-11-09T09:00:00Z"), calendar: calendar) { manualTimeline.append($0.station.id) }
        manualMix.evaluate(now: date("2026-11-09T13:00:00Z"), calendar: calendar) { manualTimeline.append($0.station.id) }
        manualMix.evaluate(now: date("2026-11-09T14:00:00Z"), calendar: calendar, canResume: { _ in false }) { manualTimeline.append($0.station.id) }
        check(manualTimeline == [base.station.id, insert.station.id, base.station.id], "Troca manual não desativa a próxima transição programada")
        let shared = RadioAutomationStore(preferences: UserDefaults(suiteName: mixDomain + ".shared")!)
        defer { UserDefaults.standard.removePersistentDomain(forName: mixDomain + ".shared") }
        var short = insert; short.hour = 9; short.endHour = 10
        check(shared.save(base) == nil && shared.save(short) == nil, "Mesmo início com finais diferentes é permitido")
        var sharedTimeline: [String] = []
        shared.evaluate(now: date("2026-11-09T09:00:00Z"), calendar: calendar) { sharedTimeline.append($0.station.id) }
        shared.evaluate(now: date("2026-11-09T10:00:00Z"), calendar: calendar) { sharedTimeline.append($0.station.id) }
        check(sharedTimeline == [short.station.id, base.station.id], "Com início igual toca primeiro a menor faixa, depois a mais longa")
        let nightMix = RadioAutomationStore(preferences: UserDefaults(suiteName: mixDomain + ".night")!)
        defer { UserDefaults.standard.removePersistentDomain(forName: mixDomain + ".night") }
        let nightBase = RadioAutomation(station: base.station, weekdays: [6], hour: 22, minute: 0, endHour: 6, endMinute: 0)
        let nightInsert = RadioAutomation(station: insert.station, weekdays: [7], hour: 1, minute: 0, endHour: 2, endMinute: 0)
        _ = nightMix.save(nightBase); _ = nightMix.save(nightInsert)
        var nightTimeline: [String] = []
        for stamp in ["2026-11-13T22:00:00Z", "2026-11-14T01:00:00Z", "2026-11-14T02:00:00Z"] {
            nightMix.evaluate(now: date(stamp), calendar: calendar) { nightTimeline.append($0.station.id) }
        }
        check(nightTimeline == [nightBase.station.id, nightInsert.station.id, nightBase.station.id], "Mesclagem retoma a rádio anterior após a meia-noite")
        check(RadioAutomationStore(preferences: mixPreferences).rules.count == 4, "Reabrir preserva regras sobrepostas")
        let partialDomain = mixDomain + ".partial"
        let partial = RadioAutomationStore(preferences: UserDefaults(suiteName: partialDomain)!)
        defer { UserDefaults.standard.removePersistentDomain(forName: partialDomain) }
        var early = base; early.endHour = 14
        var late = insert; late.endHour = 16
        _ = partial.save(early); _ = partial.save(late)
        var partialTimeline: [String] = []
        var finishes = 0
        for stamp in ["09:00", "13:00", "14:00", "16:00"] {
            partial.evaluate(now: date("2026-11-09T" + stamp + ":00Z"), calendar: calendar, finish: { _ in finishes += 1 }) { partialTimeline.append($0.station.id) }
        }
        check(partialTimeline == [early.station.id, late.station.id] && finishes == 1, "Faixa anterior já encerrada não retorna após uma sobreposição parcial")
        let restartedAt1348 = RadioAutomationStore(preferences: mixPreferences)
        var restartTimeline: [String] = []
        restartedAt1348.evaluate(now: date("2026-11-09T13:48:00Z"), calendar: calendar) { restartTimeline.append($0.station.id) }
        restartedAt1348.evaluate(now: date("2026-11-09T14:00:00Z"), calendar: calendar) { restartTimeline.append($0.station.id) }
        check(restartTimeline == [insert.station.id, base.station.id], "Reabrir às 13h48 reconstrói a faixa atual e retoma a base às 14h")
        let restartedAfter14 = RadioAutomationStore(preferences: mixPreferences)
        var after14: [String] = []
        restartedAfter14.evaluate(now: date("2026-11-09T14:05:00Z"), calendar: calendar) { after14.append($0.station.id) }
        restartedAfter14.evaluate(now: date("2026-11-09T14:06:00Z"), calendar: calendar) { after14.append($0.station.id) }
        check(after14 == [base.station.id], "Reabrir após 14h aplica a base vigente uma única vez")
        let nextResume = restartedAt1348.nextRule(now: date("2026-11-09T13:48:00Z"), calendar: calendar)
        check(nextResume?.0.id == base.id && nextResume?.1 == date("2026-11-09T14:00:00Z"), "Próxima troca mostra a retomada das 14h, não apenas o início de amanhã")
        let wake = RadioAutomationStore(preferences: mixPreferences)
        var wakeTimeline: [String] = []
        wake.evaluate(now: date("2026-11-09T13:48:00Z"), calendar: calendar) { wakeTimeline.append($0.station.id) }
        wake.evaluate(now: date("2026-11-09T14:30:00Z"), calendar: calendar) { wakeTimeline.append($0.station.id) }
        check(wakeTimeline == [insert.station.id, base.station.id], "Acordar após o término aplica diretamente o período vigente")
        let edited = RadioAutomationStore(preferences: UserDefaults(suiteName: mixDomain + ".edit")!)
        defer { UserDefaults.standard.removePersistentDomain(forName: mixDomain + ".edit") }
        _ = edited.save(insert)
        var editTimeline: [String] = []
        edited.evaluate(now: date("2026-11-09T13:48:00Z"), calendar: calendar) { editTimeline.append($0.station.id) }
        _ = edited.save(base)
        edited.evaluate(now: date("2026-11-09T14:00:00Z"), calendar: calendar) { editTimeline.append($0.station.id) }
        check(editTimeline == [insert.station.id, base.station.id], "Base criada após o início do dia também participa da retomada")
        let monthlyDomain = domain + ".monthly"
        let monthlyPreferences = UserDefaults(suiteName: monthlyDomain)!
        defer { monthlyPreferences.removePersistentDomain(forName: monthlyDomain) }
        let monthly = RadioAutomationStore(preferences: monthlyPreferences)
        var weekly = base; weekly.weekdays = Set(1...7)
        var special = weekly; special.id = UUID(); special.station = insert.station; special.specificDate = AutomationDate(date("2026-11-09T00:00:00Z"), calendar: calendar); special.weekdays = []
        check(monthly.save(weekly) == nil && monthly.save(special) == nil, "Data específica e semanal com período idêntico podem coexistir")
        var laterWeekly = weekly; laterWeekly.id = UUID(); laterWeekly.hour = 13; laterWeekly.endHour = 21; laterWeekly.station = nested.station
        _ = monthly.save(laterWeekly)
        var monthlyTimeline: [String] = []
        for stamp in ["2026-11-09T09:00:00Z", "2026-11-09T13:00:00Z", "2026-11-09T20:00:00Z"] {
            monthly.evaluate(now: date(stamp), calendar: calendar) { monthlyTimeline.append($0.station.id) }
        }
        check(monthlyTimeline == [special.station.id, laterWeekly.station.id], "Data específica vence início igual e semanal posterior; ao terminar retoma a semanal")
        let monthlyReload = RadioAutomationStore(preferences: monthlyPreferences)
        var restoredMonthly: String?
        monthlyReload.evaluate(now: date("2026-11-09T14:00:00Z"), calendar: calendar) { restoredMonthly = $0.station.id }
        check(restoredMonthly == special.station.id && monthlyReload.rules.contains(where: { $0.specificDate == special.specificDate }), "Reabrir preserva data completa e prioridade vigente")
        var duplicateMonthly = special; duplicateMonthly.id = UUID()
        check(monthly.save(duplicateMonthly) != nil, "Duas específicas com mesma data e período são bloqueadas")
        duplicateMonthly.specificDate = AutomationDate(date("2026-11-10T00:00:00Z"), calendar: calendar)
        check(monthly.save(duplicateMonthly) == nil, "Mesmo período em datas distintas é permitido")
        var invalidMonthly = special; invalidMonthly.specificDate!.day = 32
        check(!invalidMonthly.isValid, "Data inexistente é rejeitada")
        check(special.nextDate(after: date("2026-11-10T00:00:00Z"), calendar: calendar) == nil, "Data específica encerrada não repete no mês ou ano seguinte")
        let sparseDomain = domain + ".specific"
        let sparsePrefs = UserDefaults(suiteName: sparseDomain)!
        defer { sparsePrefs.removePersistentDomain(forName: sparseDomain) }
        let sparse = RadioAutomationStore(preferences: sparsePrefs)
        var future = special; future.id = UUID(); future.specificDate = AutomationDate(date("2027-12-31T00:00:00Z"), calendar: calendar)
        _ = sparse.save(future)
        check(sparse.nextRule(now: date("2026-11-10T00:00:00Z"), calendar: calendar)?.1 == date("2027-12-31T09:00:00Z"), "Próxima troca encontra data específica distante")
        var overnight = special; overnight.id = UUID(); overnight.specificDate = AutomationDate(date("2027-01-31T00:00:00Z"), calendar: calendar); overnight.hour = 23; overnight.endHour = 2
        _ = sparse.save(overnight)
        var overnightStation: String?
        sparse.evaluate(now: date("2027-02-01T01:00:00Z"), calendar: calendar) { overnightStation = $0.station.id }
        check(overnightStation == overnight.station.id, "Data específica noturna mantém prioridade na virada do mês")
        let nextMonth = RadioAutomationStore(preferences: monthlyPreferences)
        var repeated = false
        nextMonth.evaluate(now: date("2026-12-09T10:00:00Z"), calendar: calendar) { if $0.id == special.id { repeated = true } }
        nextMonth.evaluate(now: date("2027-11-09T10:00:00Z"), calendar: calendar) { if $0.id == special.id { repeated = true } }
        check(!repeated, "Agendamento específico não é executado novamente em outra data")
        let design = PlayerSkin.heritage.design.overridingAccent(0x78B7FF)
        check(design.accent == 0x78B7FF && design.background == PlayerSkin.heritage.design.background, "Cor personalizada muda destaque sem mudar o material da skin")
        check(PlayerSkin.studio.design.overridingAccent(nil).accent == PlayerSkin.studio.design.accent, "Restaurar cor padrão respeita a skin selecionada")
        return failures
    }
}
