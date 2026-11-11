class RadioStation {
  final String id, name, url, genre, location;
  const RadioStation({required this.id, required this.name, required this.url, this.genre = '', this.location = ''});
  factory RadioStation.fromJson(Map<String, dynamic> j) => RadioStation(id: j['id'] as String, name: j['name'] as String, url: j['url'] as String, genre: j['genre'] as String? ?? '', location: j['location'] as String? ?? '');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url, 'genre': genre, 'location': location};
  bool get valid { final u = Uri.tryParse(url); return u != null && ['http', 'https'].contains(u.scheme) && u.host.isNotEmpty && u.userInfo.isEmpty; }
}

class RadioSchedule {
  final String id, stationId, name;
  final Set<int> days;
  final int start, end;
  final String? date; // Civil date, yyyy-MM-dd; never a UTC timestamp.
  final bool enabled;
  const RadioSchedule({required this.id, required this.stationId, this.name = '', required this.days, required this.start, required this.end, this.date, this.enabled = true});
  factory RadioSchedule.fromJson(Map<String, dynamic> j) => RadioSchedule(id: j['id'], stationId: j['stationId'], name: j['name'] ?? '', days: Set<int>.from(j['days']), start: j['start'], end: j['end'], date: j['date'], enabled: j['enabled'] ?? true);
  Map<String, dynamic> toJson() => {'id': id, 'stationId': stationId, 'name': name, 'days': days.toList(), 'start': start, 'end': end, 'date': date, 'enabled': enabled};
  RadioSchedule toggled() => RadioSchedule(id: id, stationId: stationId, name: name, days: days, start: start, end: end, date: date, enabled: !enabled);
  bool get valid => start >= 0 && start < 1440 && end >= 0 && end < 1440 && start != end && (date != null || days.isNotEmpty);
  DateTime? occurrence(DateTime now) {
    if (!enabled || !valid) return null;
    for (final offset in [0, -1]) {
      final day = DateTime(now.year, now.month, now.day + offset);
      if (date != null ? civilDate(day) != date : !days.contains(day.weekday)) continue;
      final from = DateTime(day.year, day.month, day.day, start ~/ 60, start % 60);
      final to = DateTime(day.year, day.month, day.day + (end < start ? 1 : 0), end ~/ 60, end % 60);
      if (!now.isBefore(from) && now.isBefore(to)) return from;
    }
    return null;
  }
  bool duplicates(RadioSchedule other) => id != other.id && enabled && other.enabled && start == other.start && end == other.end && (date != null ? date == other.date : other.date == null && days.intersection(other.days).isNotEmpty);
  static String civilDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String time(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  static RadioSchedule? winner(List<RadioSchedule> rules, DateTime now) {
    final active = rules.where((r) => r.occurrence(now) != null).toList();
    active.sort((a, b) {
      if ((a.date != null) != (b.date != null)) return a.date != null ? -1 : 1;
      final order = b.occurrence(now)!.compareTo(a.occurrence(now)!);
      if (order != 0) return order;
      final durationA = (a.end - a.start + 1440) % 1440;
      final durationB = (b.end - b.start + 1440) % 1440;
      return durationA != durationB ? durationA.compareTo(durationB) : a.id.compareTo(b.id);
    });
    return active.isEmpty ? null : active.first;
  }
}
