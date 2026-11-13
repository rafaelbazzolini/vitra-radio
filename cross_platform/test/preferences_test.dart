import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitra_radio/core/preferences.dart';

void main() {
  testWidgets(
    'region, language and independent theme color survive reopening',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = (await tester.runAsync(
        () => AppPreferences.load(prefs),
      ))!;
      expect(settings.needsSetup, true);
      expect(settings.codes.length, 1);
      await settings.setCodes(['br', 'BR', 'US', 'ZZ']);
      expect(settings.codes, ['BR', 'US']);
      await settings.setLanguage('en');
      await settings.setAccent('72c7f5');
      await settings.finishSetup();
      final reopened = (await tester.runAsync(
        () => AppPreferences.load(prefs),
      ))!;
      expect(reopened.language, 'en');
      expect(reopened.codes, ['BR', 'US']);
      expect(reopened.accentHex, '72c7f5');
      expect(reopened.needsSetup, false);
      expect(tr('Todas as rádios'), 'All stations');
      await reopened.setCodes([]);
      expect(reopened.countrySummary, 'Worldwide');
      await reopened.setAccent(null);
      expect(prefs.containsKey('accentOverride'), false);
      await reopened.setCodes(
        reopened.countries.take(20).map((c) => c['code'] as String).toList(),
      );
      expect(reopened.codes.length, 8);
      settings.dispose();
      reopened.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
