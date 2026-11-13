import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, String> english = {};
String appLanguage = 'pt-BR';
String tr(String text) => appLanguage == 'en' ? english[text] ?? text : text;

class AppPreferences extends ChangeNotifier {
  final SharedPreferences prefs;
  final List<Map<String, dynamic>> countries;
  String language;
  List<String> codes;
  bool needsSetup;
  String settingsTab = 'Idioma e região';
  String? accentHex;
  AppPreferences._(
    this.prefs,
    this.countries,
    this.language,
    this.codes,
    this.needsSetup,
  ) {
    appLanguage = language;
    accentHex = prefs.getString('accentOverride');
  }
  static Future<AppPreferences> load(SharedPreferences prefs) async {
    english = Map<String, String>.from(
      jsonDecode(await rootBundle.loadString('assets/en.json')),
    );
    final countries =
        (jsonDecode(await rootBundle.loadString('assets/countries.json'))
                as List)
            .cast<Map<String, dynamic>>();
    final locale = PlatformDispatcher.instance.locale;
    final valid = countries.map((c) => c['code'] as String).toSet();
    final suggested = valid.contains(locale.countryCode)
        ? locale.countryCode!
        : 'BR';
    return AppPreferences._(
      prefs,
      countries,
      prefs.getString('interfaceLanguage') ??
          (locale.languageCode == 'en' ? 'en' : 'pt-BR'),
      (prefs.getStringList('catalogCountryCodes') ?? [suggested])
          .where(valid.contains)
          .take(8)
          .toList(),
      !(prefs.getBool('catalogCountriesConfigured') ?? false),
    );
  }

  String name(String code) =>
      countries.where((c) => c['code'] == code).firstOrNull?[language == 'en'
              ? 'en'
              : 'pt']
          as String? ??
      code;
  String get countrySummary =>
      codes.isEmpty ? tr('Mundo todo') : codes.map(name).join(', ');
  Future<void> setLanguage(String value) async {
    language = value == 'en' ? 'en' : 'pt-BR';
    appLanguage = language;
    await prefs.setString('interfaceLanguage', language);
    notifyListeners();
  }

  Future<void> setCodes(List<String> values) async {
    final valid = countries.map((c) => c['code']).toSet();
    codes =
        values
            .map((v) => v.toUpperCase())
            .toSet()
            .where(valid.contains)
            .take(8)
            .toList()
          ..sort();
    await prefs.setStringList('catalogCountryCodes', codes);
    notifyListeners();
  }

  Future<void> finishSetup() async {
    needsSetup = false;
    await prefs.setString('interfaceLanguage', language);
    await prefs.setBool('catalogCountriesConfigured', true);
    notifyListeners();
  }

  void selectSettings(String tab) {
    settingsTab = tab;
    notifyListeners();
  }

  Future<void> setAccent(String? value) async {
    accentHex = value;
    if (value == null) {
      await prefs.remove('accentOverride');
    } else {
      await prefs.setString('accentOverride', value);
    }
    notifyListeners();
  }
}
