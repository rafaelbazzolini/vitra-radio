import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class RadioStore extends ChangeNotifier {
  final Player player = Player();
  final SharedPreferences prefs;
  final List<RadioStation> library = [];
  final Set<String> favorites = {};
  final List<String> recent = [];
  final List<RadioSchedule> schedules = [];
  RadioStation? selected;
  bool playing = false, busy = false, searching = false;
  double volume = 0.6;
  String skin = 'Vitra', page = 'Início', section = 'Favoritas';
  String? error;
  List<RadioStation> results = [];
  int _searchGeneration = 0;
  String? _winnerKey;
  bool _automationOwnsPlayback = false;
  Timer? _scheduler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  RadioStore(this.prefs) {
    try {
      library.addAll(
        (jsonDecode(prefs.getString('stations') ?? '[]') as List)
            .map((j) => RadioStation.fromJson(Map<String, dynamic>.from(j)))
            .where((s) => s.valid),
      );
      schedules.addAll(
        (jsonDecode(prefs.getString('schedules') ?? '[]') as List)
            .map((j) => RadioSchedule.fromJson(Map<String, dynamic>.from(j)))
            .where((r) => r.valid),
      );
    } catch (_) {
      error = 'Não foi possível ler parte dos dados locais.';
    }
    favorites.addAll(prefs.getStringList('favorites') ?? []);
    recent.addAll(prefs.getStringList('recent') ?? []);
    skin = prefs.getString('skin') ?? 'Vitra';
    volume = (prefs.getDouble('volume') ?? 0.6).clamp(0, 1);
    _subscriptions.add(
      player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((v) {
        busy = v;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((v) {
        error = 'Não foi possível tocar esta transmissão: $v';
        busy = false;
        notifyListeners();
      }),
    );
    unawaited(player.setVolume(volume * 100));
    _scheduler = Timer.periodic(
      const Duration(seconds: 10),
      (_) => evaluateSchedule(),
    );
    evaluateSchedule();
  }
  List<RadioStation> get visible => section == 'Favoritas'
      ? library.where((s) => favorites.contains(s.id)).toList()
      : recent
            .map((id) => library.where((s) => s.id == id).firstOrNull)
            .whereType<RadioStation>()
            .toList();
  void navigate(String value) {
    page = value;
    notifyListeners();
  }

  void chooseSection(String value) {
    section = value;
    notifyListeners();
  }

  void chooseSkin(String value) {
    skin = value;
    unawaited(prefs.setString('skin', value));
    notifyListeners();
  }

  void remember(RadioStation station) {
    if (!library.any((s) => s.id == station.id || s.url == station.url)) {
      library.add(station);
    }
    unawaited(_save());
  }

  void favorite(RadioStation station) {
    remember(station);
    if (!favorites.add(station.id)) favorites.remove(station.id);
    unawaited(_save());
    notifyListeners();
  }

  Future<void> play(RadioStation station, {bool automated = false}) async {
    if (!station.valid) return;
    _automationOwnsPlayback = automated;
    remember(station);
    selected = station;
    error = null;
    busy = true;
    recent.remove(station.id);
    recent.insert(0, station.id);
    if (recent.length > 30) recent.removeLast();
    notifyListeners();
    await _save();
    try {
      await player.open(Media(station.url));
    } catch (_) {
      busy = false;
      error = 'Não foi possível abrir a transmissão.';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    _automationOwnsPlayback = false;
    await player.playOrPause();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 1);
    await player.setVolume(volume * 100);
    await prefs.setDouble('volume', volume);
    notifyListeners();
  }

  Future<void> skip(int direction) async {
    final queue = library.where((s) => favorites.contains(s.id)).toList();
    if (queue.isEmpty) return;
    final index = queue.indexWhere((s) => s.id == selected?.id);
    await play(queue[(index + direction) % queue.length]);
  }

  Future<void> search(String query, {String country = ''}) async {
    final generation = ++_searchGeneration;
    searching = true;
    error = null;
    notifyListeners();
    try {
      final uri =
          Uri.https('all.api.radio-browser.info', '/json/stations/search', {
            'name': query,
            'countrycode': country,
            'limit': '80',
            'hidebroken': 'true',
            'order': 'clickcount',
            'reverse': 'true',
          });
      final response = await http
          .get(uri, headers: {'User-Agent': 'VitraRadio/0.1'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw const FormatException();
      final stations = (jsonDecode(response.body) as List)
          .map(
            (j) => RadioStation(
              id: j['stationuuid'],
              name: j['name'],
              url: (j['url_resolved'] as String?)?.isNotEmpty == true
                  ? j['url_resolved']
                  : j['url'],
              genre: j['tags'] ?? '',
              location: j['country'] ?? '',
            ),
          )
          .where((s) => s.valid)
          .toList();
      if (generation == _searchGeneration) results = stations;
    } catch (_) {
      if (generation == _searchGeneration) {
        error = 'Catálogo indisponível. Tente novamente ou adicione um stream.';
      }
    } finally {
      if (generation == _searchGeneration) {
        searching = false;
        notifyListeners();
      }
    }
  }

  String? saveSchedule(RadioSchedule rule) {
    if (!rule.valid || !library.any((s) => s.id == rule.stationId)) {
      return 'Escolha uma rádio e um período válido.';
    }
    if (schedules.any(rule.duplicates)) {
      return 'Já existe um período idêntico para estes dias ou data.';
    }
    schedules.removeWhere((r) => r.id == rule.id);
    schedules.add(rule);
    unawaited(_save());
    evaluateSchedule();
    notifyListeners();
    return null;
  }

  void removeSchedule(String id) {
    schedules.removeWhere((r) => r.id == id);
    unawaited(_save());
    evaluateSchedule();
    notifyListeners();
  }

  void evaluateSchedule() {
    final now = DateTime.now(),
        winner = RadioSchedule.winner(schedules, DateTime.now());
    final key = winner == null
        ? null
        : '${winner.id}:${winner.occurrence(now)}';
    if (key == _winnerKey) return;
    _winnerKey = key;
    if (winner != null) {
      final station = library
          .where((s) => s.id == winner.stationId)
          .firstOrNull;
      if (station != null) unawaited(play(station, automated: true));
    } else if (_automationOwnsPlayback) {
      _automationOwnsPlayback = false;
      unawaited(player.pause());
    }
  }

  Future<void> _save() async {
    await prefs.setString(
      'stations',
      jsonEncode(library.map((s) => s.toJson()).toList()),
    );
    await prefs.setStringList('favorites', favorites.toList());
    await prefs.setStringList('recent', recent);
    await prefs.setString(
      'schedules',
      jsonEncode(schedules.map((r) => r.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _scheduler?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
