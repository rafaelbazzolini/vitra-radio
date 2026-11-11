import 'package:flutter_test/flutter_test.dart';
import 'package:vitra_radio/core/models.dart';
import 'package:vitra_radio/core/updates.dart';
void main() {
  RadioSchedule rule(String id, int start, int end, {String? date}) => RadioSchedule(id: id, stationId: id, days: {1,2,3,4,5,6,7}, start: start, end: end, date: date);
  test('nested periods resume base after restart and end', () {
    final base = rule('base', 540, 1200), insert = rule('insert', 780, 840);
    expect(RadioSchedule.winner([base, insert], DateTime(2026, 11, 11, 13, 48))?.id, 'insert');
    expect(RadioSchedule.winner([base, insert], DateTime(2026, 11, 11, 14))?.id, 'base');
  });
  test('one-off has priority and never repeats next month', () {
    final base = rule('base', 540, 1200), dated = rule('date', 540, 1200, date: '2026-11-11');
    expect(dated.duplicates(base), false);
    expect(RadioSchedule.winner([base, dated], DateTime(2026, 11, 11, 10))?.id, 'date');
    expect(RadioSchedule.winner([base, dated], DateTime(2026, 12, 11, 10))?.id, 'base');
  });
  test('overnight and duplicate rules', () {
    final a = rule('a', 1380, 120, date: '2026-11-30');
    expect(a.occurrence(DateTime(2026, 12, 1, 1)), isNotNull);
    expect(a.occurrence(DateTime(2026, 12, 1, 2)), isNull);
    expect(a.duplicates(rule('b', 1380, 120, date: '2026-11-30')), true);
  });
  test('versions compare numerically, not lexically', () {
    expect(UpdateService.isNewer('v0.1.12', '0.1.9'), true);
    expect(UpdateService.isNewer('v0.1.2', '0.1.12'), false);
    expect(UpdateService.isNewer('v0.1.12', '0.1.12+3'), false);
  });
  test('station rejects embedded credentials and non-network URLs', () {
    expect(const RadioStation(id:'a', name:'A', url:'file:///secret').valid, false);
    expect(const RadioStation(id:'a', name:'A', url:'https://user:pass@example.org/stream').valid, false);
  });
}
