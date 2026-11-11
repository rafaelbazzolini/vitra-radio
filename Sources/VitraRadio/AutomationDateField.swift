import SwiftUI

struct AutomationDateField: View {
    @Environment(\.appPalette) private var palette
    @Binding var selection: AutomationDate?
    @State private var showingCalendar = false
    @State private var displayedMonth = Date()
    private var calendar: Calendar { Calendar.current }
    private var selected: Date { selection?.date(calendar: calendar) ?? Date() }
    private func label(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.calendar = calendar
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private func shift(_ amount: Int) {
        if let date = calendar.date(byAdding: .day, value: amount, to: selected) { selection = AutomationDate(date) }
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(palette.accent)
                .frame(width: 36, height: 36).background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text("DATA DE INÍCIO").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(palette.muted)
                Button {
                    displayedMonth = selected
                    showingCalendar.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(label(selected, format: "dd 'de' MMMM 'de' yyyy")).font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.accent)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Escolher data no calendário")
                .popover(isPresented: $showingCalendar, arrowEdge: .bottom) { calendarPanel }
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                arrow("chevron.left", help: "Dia anterior") { shift(-1) }
                arrow("chevron.right", help: "Próximo dia") { shift(1) }
            }
        }.padding(12).foregroundStyle(palette.text)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line))
    }
    private func arrow(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28)
                .background(palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.line)).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: displayedMonth)!.start }
    private var monthOffset: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    private var monthCount: Int { calendar.range(of: .day, in: .month, for: displayedMonth)!.count }
    private var calendarPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text(label(displayedMonth, format: "MMMM yyyy").capitalized).font(.system(size: 15, weight: .semibold))
                Spacer()
                arrow("chevron.left", help: "Mês anterior") { displayedMonth = calendar.date(byAdding: .month, value: -1, to: monthStart)! }
                arrow("chevron.right", help: "Próximo mês") { displayedMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)! }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(["S", "T", "Q", "Q", "S", "S", "D"].indices, id: \.self) { index in
                    Text(["S", "T", "Q", "Q", "S", "S", "D"][index]).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.muted).frame(height: 22)
                }
                ForEach(0..<(monthOffset + monthCount), id: \.self) { index in
                    if index < monthOffset { Color.clear.frame(height: 32) }
                    else {
                        let date = calendar.date(byAdding: .day, value: index - monthOffset, to: monthStart)!
                        let active = calendar.isDate(date, inSameDayAs: selected)
                        Button {
                            selection = AutomationDate(date)
                            showingCalendar = false
                        } label: {
                            Text("\(index - monthOffset + 1)").font(.system(size: 12, weight: active ? .bold : .medium))
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .foregroundStyle(active ? palette.onAccent : palette.text)
                                .background(active ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(calendar.isDateInToday(date) && !active ? palette.accent.opacity(0.5) : .clear))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(label(date, format: "dd 'de' MMMM 'de' yyyy"))
                    }
                }
            }
            HStack {
                Text(label(selected, format: "EEEE").capitalized).font(.system(size: 11)).foregroundStyle(palette.muted)
                Spacer()
                Button("Hoje") { selection = AutomationDate(Date()); displayedMonth = Date(); showingCalendar = false }
                    .buttonStyle(VitraButtonStyle(compact: true))
            }
        }.padding(18).frame(width: 310).background(palette.background).foregroundStyle(palette.text)
    }
}
