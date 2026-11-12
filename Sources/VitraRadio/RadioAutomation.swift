import AppKit

struct AutomationDate: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int
    init(_ date: Date, calendar: Calendar = .current) {
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }
    func date(calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year, calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
    var label: String {
        guard let value = date(calendar: Calendar(identifier: .gregorian)) else { return String(format: "%02d/%02d/%04d", day, month, year) }
        return value.formatted(.dateTime.locale(L10n.locale).day().month(.abbreviated).year())
    }
}

struct RadioAutomation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var station: Station.Saved
    var weekdays: Set<Int> = [2, 3, 4, 5, 6] // Calendar: Sunday = 1.
    var hour = 9
    var minute = 0
    var enabled = true
    var endHour: Int? = nil
    var endMinute: Int? = nil
    var dayOfMonth: Int? = nil // Decode the short-lived monthly format for migration only.
    var specificDate: AutomationDate? = nil
    func matchesDay(_ date: Date, calendar: Calendar) -> Bool {
        if let specificDate { return AutomationDate(date, calendar: calendar) == specificDate }
        return weekdays.contains(calendar.component(.weekday, from: date))
    }
    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }
    var startMinute: Int { hour * 60 + minute }
    var endTime: Int? { guard let endHour, let endMinute else { return nil }; return endHour * 60 + endMinute }
    var endsNextDay: Bool { endTime.map { $0 < startMinute } ?? false }
    var endLabel: String? { guard let endHour, let endMinute else { return nil }; return String(format: "%02d:%02d", endHour, endMinute) }
    var periodLabel: String { timeLabel + (endLabel.map { "–" + $0 + (endsNextDay ? L10n.tr(" (+1 dia)") : "") } ?? L10n.tr(" · sem término")) }
    var isValid: Bool {
        guard (0...23).contains(hour), (0...59).contains(minute), (specificDate.map { $0.date(calendar: .current) != nil } ?? (!weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) })), station.station?.isLive == true else { return false }
        if endHour == nil && endMinute == nil { return true } // Existing start-only schedules remain readable.
        guard let endHour, let endMinute else { return false }
        return (0...23).contains(endHour) && (0...59).contains(endMinute) && endTime != startMinute
    }
    private var weeklyIntervals: [Range<Int>] {
        let duration = endTime.map { ($0 - startMinute + 1440) % 1440 } ?? 1
        return weekdays.map { day in let start = (day - 1) * 1440 + startMinute; return start..<(start + duration) }
    }
    func overlaps(_ other: RadioAutomation) -> Bool {
        guard id != other.id, enabled, other.enabled else { return false }
        for left in weeklyIntervals {
            for right in other.weeklyIntervals {
                for offset in [-10080, 0, 10080] {
                    if left.overlaps((right.lowerBound + offset)..<(right.upperBound + offset)) { return true }
                }
            }
        }
        return false
    }
    func duplicates(_ other: RadioAutomation) -> Bool {
        let sameDays: Bool
        if let specificDate { sameDays = other.specificDate == specificDate }
        else { sameDays = other.specificDate == nil && !weekdays.isDisjoint(with: other.weekdays) }
        return id != other.id && enabled && other.enabled && startMinute == other.startMinute && endTime == other.endTime && sameDays
    }
    func endingDate(for start: Date, calendar: Calendar) -> Date? {
        guard let endHour, let endMinute else { return nil }
        let day = calendar.date(byAdding: .day, value: endsNextDay ? 1 : 0, to: calendar.startOfDay(for: start))!
        return calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
    func nextDate(after now: Date, calendar: Calendar) -> Date? {
        guard enabled else { return nil }
        if let specificDate {
            guard let day = specificDate.date(calendar: calendar),
                  let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .strict, repeatedTimePolicy: .first),
                  calendar.isDate(start, inSameDayAs: day), start > now else { return nil }
            return start
        }
        return weekdays.compactMap { weekday in
            calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday), matchingPolicy: .strict, repeatedTimePolicy: .first)
        }.min()
    }
    static let days: [(Int, String)] = [(2, "Seg"), (3, "Ter"), (4, "Qua"), (5, "Qui"), (6, "Sex"), (7, "Sáb"), (1, "Dom")]
    var daysLabel: String { if let specificDate { return L10n.tr("\(specificDate.label) · uma vez · prioridade") }; return Self.days.filter { weekdays.contains($0.0) }.map { L10n.tr($0.1) }.joined(separator: " · ") }
}

@MainActor final class RadioAutomationStore: ObservableObject {
    @Published private(set) var rules: [RadioAutomation]
    @Published private(set) var lastMessage: String?
    private let preferences: UserDefaults
    private var lastRuns: [String: String]
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var fire: ((RadioAutomation) -> Void)?
    private var finish: ((RadioAutomation) -> Void)?
    private struct Run {
        let rule: RadioAutomation
        let start: Date
        let end: Date
        func sameOccurrence(as other: Run?) -> Bool { other?.rule.id == rule.id && other?.start == start && other?.rule.station == rule.station }
    }
    private var activeRuns: [UUID: Run] = [:]
    private var currentRun: Run?
    private var canResume: ((RadioAutomation) -> Bool)?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let decoded = preferences.data(forKey: "radioAutomations").flatMap { try? JSONDecoder().decode([RadioAutomation].self, from: $0) } ?? []
        var accepted: [RadioAutomation] = []
        for var rule in decoded {
            if let legacyDay = rule.dayOfMonth, rule.specificDate == nil {
                if let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(day: legacyDay, hour: rule.hour, minute: rule.minute), matchingPolicy: .strict) {
                    rule.specificDate = AutomationDate(next)
                }
                rule.dayOfMonth = nil
            }
            guard rule.isValid else { continue }
            if !accepted.contains(where: { $0.id == rule.id || $0.duplicates(rule) }) { accepted.append(rule) }
        }
        rules = accepted
        lastRuns = preferences.dictionary(forKey: "radioAutomationRuns") as? [String: String] ?? [:]
    }
    func validationError(for rule: RadioAutomation) -> String? {
        guard rule.isValid else { return L10n.tr("Escolha uma rádio, pelo menos um dia e horários válidos. O término deve ser diferente do início.") }
        if let other = rules.first(where: { rule.duplicates($0) }) {
            return L10n.tr("Já existe um período com início e término idênticos: \(other.station.name), \(other.periodLabel) (\(other.daysLabel)). Altere o período ou os dias.")
        }
        return nil
    }
    @discardableResult func save(_ rule: RadioAutomation) -> String? {
        if let error = validationError(for: rule) { return error }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule }
        else { rules.append(rule) }
        rules.sort { ($0.hour, $0.minute, $0.name) < ($1.hour, $1.minute, $1.name) }
        persist()
        return nil
    }
    func setEnabled(_ rule: RadioAutomation, _ enabled: Bool) -> String? {
        var updated = rule; updated.enabled = enabled
        return save(updated)
    }
    func remove(_ id: UUID) {
        rules.removeAll { $0.id == id }
        lastRuns.removeValue(forKey: id.uuidString)
        persist()
    }
    func start(finish: @escaping (RadioAutomation) -> Void, canResume: @escaping (RadioAutomation) -> Bool, fire: @escaping (RadioAutomation) -> Void) {
        stop()
        self.fire = fire
        self.finish = finish
        self.canResume = canResume
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }
    func stop() {
        timer?.invalidate(); timer = nil; fire = nil; finish = nil; canResume = nil; activeRuns.removeAll(); currentRun = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }
    private func tick() {
        guard let fire else { return }
        evaluate(now: Date(), calendar: .current, finish: finish ?? { _ in }, canResume: canResume ?? { _ in true }, fire: fire)
    }
    // Reconstruct bounded periods from the calendar on every tick, including startup/wake/edit.
    private func run(_ rule: RadioAutomation, on day: Date, calendar: Calendar) -> Run? {
        guard rule.enabled, rule.matchesDay(day, calendar: calendar),
              let start = calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: day, matchingPolicy: .strict, repeatedTimePolicy: .first),
              calendar.isDate(start, inSameDayAs: day),
              let end = rule.endingDate(for: start, calendar: calendar) else { return nil }
        return Run(rule: rule, start: start, end: end)
    }
    private func plannedRuns(at now: Date, calendar: Calendar) -> [Run] {
        let today = calendar.startOfDay(for: now)
        var result: [Run] = []
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for rule in rules where rule.endTime != nil {
                if let run = run(rule, on: day, calendar: calendar), run.start <= now && now < run.end { result.append(run) }
            }
        }
        return result
    }
    private func preferred(_ runs: [Run]) -> Run? {
        runs.max { left, right in
            if (left.rule.specificDate != nil) != (right.rule.specificDate != nil) { return left.rule.specificDate == nil }
            if left.start != right.start { return left.start < right.start }
            if left.end != right.end { return left.end > right.end }
            return left.rule.id.uuidString < right.rule.id.uuidString
        }
    }
    func evaluate(now: Date, calendar: Calendar, finish: (RadioAutomation) -> Void = { _ in }, canResume: (RadioAutomation) -> Bool = { _ in true }, fire: (RadioAutomation) -> Void) {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
        guard let hour = parts.hour, let minute = parts.minute else { return }
        let occurrence = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(hour)-\(minute)"
        // Legacy start-only rules retain their original exact-minute behavior.
        activeRuns = activeRuns.filter { _, run in run.rule.endTime == nil && rules.contains(where: { $0.id == run.rule.id && $0.enabled }) }
        var newLegacy = false
        for rule in rules where rule.enabled && rule.endTime == nil && rule.matchesDay(now, calendar: calendar) && rule.hour == hour && rule.minute == minute && lastRuns[rule.id.uuidString] != occurrence {
            lastRuns[rule.id.uuidString] = occurrence; newLegacy = true
            activeRuns[rule.id] = Run(rule: rule, start: calendar.dateInterval(of: .minute, for: now)?.start ?? now, end: .distantFuture)
        }
        if newLegacy { preferences.set(lastRuns, forKey: "radioAutomationRuns") }
        let candidates = plannedRuns(at: now, calendar: calendar) + Array(activeRuns.values)
        let winner = preferred(candidates)
        let previous = currentRun
        if let winner, winner.sameOccurrence(as: currentRun) { currentRun = winner; return }
        if let previous, canResume(previous.rule), !candidates.contains(where: { $0.sameOccurrence(as: previous) }) {
            lastMessage = L10n.tr("Período encerrado · \(previous.rule.station.name)")
            finish(previous.rule)
        }
        currentRun = winner
        if let winner {
            lastMessage = "\(String(format: "%02d:%02d", hour, minute)) · \(winner.rule.station.name)"
            fire(winner.rule)
        }
    }
    func nextRule(now: Date = Date(), calendar: Calendar = .current) -> (RadioAutomation, Date)? {
        let day = calendar.startOfDay(for: now)
        var boundaries = Set<Date>()
        for offset in -1...8 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            for rule in rules where rule.endTime != nil {
                if let run = run(rule, on: date, calendar: calendar) {
                    if run.start > now { boundaries.insert(run.start) }
                    if run.end > now { boundaries.insert(run.end) }
                }
            }
        }
        for rule in rules where rule.endTime != nil {
            if let day = rule.specificDate?.date(calendar: calendar), let run = run(rule, on: day, calendar: calendar) {
                if run.start > now { boundaries.insert(run.start) }
                if run.end > now { boundaries.insert(run.end) }
            }
        }
        var current = preferred(plannedRuns(at: now, calendar: calendar))
        var next: (RadioAutomation, Date)?
        for boundary in boundaries.sorted() {
            let after = preferred(plannedRuns(at: boundary, calendar: calendar))
            if let after, !after.sameOccurrence(as: current) { next = (after.rule, boundary); break }
            current = after
        }
        let legacy = rules.filter { $0.endTime == nil }.compactMap { rule in rule.nextDate(after: now, calendar: calendar).map { (rule, $0) } }.min { $0.1 < $1.1 }
        if let legacy, next == nil || legacy.1 < next!.1 { return legacy }
        return next
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { preferences.set(data, forKey: "radioAutomations") }
        preferences.set(lastRuns, forKey: "radioAutomationRuns")
    }
}
