import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'catalog.dart';
import 'radio_moods.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class RadioStore extends ChangeNotifier {
  String? mood;
  Map<String, List<String>> moodOverrides = {};
  bool hasMood(String category, RadioStation station) =>
      moodOverrides[station.url]?.contains(category) ??
      (moodSuggestions[category]?.any((s) => s.url == station.url) ?? false);
  void toggleMood(String category, RadioStation station) {
    remember(station);
    final values = radioMoods.where((m) => hasMood(m, station)).toList();
    if (values.contains(category)) {
      values.remove(category);
    } else {
      values.add(category);
    }
    moodOverrides[station.url] = values;
    unawaited(prefs.setString('radioMoodOverrides', jsonEncode(moodOverrides)));
    notifyListeners();
  }

  void chooseMood(String? value) {
    mood = value;
    notifyListeners();
  }

  List<RadioStation> get catalogVisible {
    if (mood == null) return results;
    final seen = <String>{};
    return [...library, ...moodSuggestions.values.expand((s) => s)]
        .where(
          (s) =>
              hasMood(mood!, s) &&
              seen.add(s.url) &&
              (query.isEmpty ||
                  '${s.name} ${s.genre}'.toLowerCase().contains(
                    query.toLowerCase(),
                  )),
        )
        .toList();
  }

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
  final CatalogClient catalog = CatalogClient();
  List<String> countryCodes = [];
  bool hasMore = false;
  int _offset = 0;
  String query = '';
  bool isLive = true;
  String? mediaTitle, mediaArtist;
  Duration position = Duration.zero, duration = Duration.zero;
  String? mediaID;
  void Function(Duration)? onProgress;
  VoidCallback? onMediaCompleted;
  bool get hasMedia => selected != null || mediaTitle != null;
  int _searchGeneration = 0;
  String? _winnerKey;
  bool _automationOwnsPlayback = false;
  Timer? _scheduler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  RadioStore(this.prefs) {
    try {
      final savedMoods =
          jsonDecode(prefs.getString('radioMoodOverrides') ?? '{}') as Map;
      moodOverrides = savedMoods.map(
        (key, value) => MapEntry(key as String, List<String>.from(value)),
      );
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
      player.stream.position.listen((value) {
        final changed = value.inSeconds != position.inSeconds;
        position = value;
        onProgress?.call(value);
        if (changed) {
          notifyListeners();
        }
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        duration = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((value) {
        if (value && !isLive) {
          onMediaCompleted?.call();
        }
      }),
    );
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
    if (value == 'Todas as rádios' && results.isEmpty && !searching) {
      unawaited(search(query));
    }
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

  RadioStation remember(RadioStation station) {
    final existing = library
        .where((s) => s.id == station.id || s.url == station.url)
        .firstOrNull;
    if (existing != null) {
      return existing;
    }
    library.add(station);
    unawaited(_save());
    return station;
  }

  bool isFavorite(RadioStation station) => favorites.contains(
    library
            .where((s) => s.id == station.id || s.url == station.url)
            .firstOrNull
            ?.id ??
        station.id,
  );
  void favorite(RadioStation input) {
    final station = remember(input);
    if (!favorites.add(station.id)) {
      favorites.remove(station.id);
    }
    unawaited(_save());
    notifyListeners();
  }

  Future<void> play(RadioStation input, {bool automated = false}) async {
    if (!input.valid) return;
    final station = remember(input);
    onProgress?.call(position);
    onProgress = null;
    onMediaCompleted = null;
    isLive = true;
    mediaTitle = null;
    mediaArtist = null;
    mediaID = null;
    position = Duration.zero;
    duration = Duration.zero;
    _automationOwnsPlayback = automated;
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
    onProgress?.call(position);
    await player.playOrPause();
    onProgress?.call(position);
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

  Future<void> playMedia({
    required String id,
    required String title,
    required String artist,
    required String url,
    Duration resume = Duration.zero,
    void Function(Duration)? progress,
    VoidCallback? completed,
  }) async {
    onProgress?.call(position);
    onProgress = null;
    onMediaCompleted = null;
    _automationOwnsPlayback = false;
    isLive = false;
    selected = null;
    mediaID = id;
    mediaTitle = title;
    mediaArtist = artist;
    busy = true;
    error = null;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
    try {
      await player.open(Media(url, start: resume));
      if (mediaID == id) {
        onProgress = progress;
        onMediaCompleted = completed;
      }
    } catch (_) {
      busy = false;
      error = 'Não foi possível abrir o áudio.';
      notifyListeners();
    }
  }

  Future<void> seek(Duration value) async {
    final end = duration.inMilliseconds;
    await player.seek(
      Duration(
        milliseconds: value.inMilliseconds.clamp(0, end > 0 ? end : 2147483647),
      ),
    );
    onProgress?.call(player.state.position);
  }

  Future<void> search(String text, {bool more = false}) async {
    final generation = ++_searchGeneration;
    if (!more) {
      query = text.trim();
      _offset = 0;
      results = [];
    }
    searching = true;
    error = null;
    notifyListeners();
    try {
      final page = await catalog.search(query, countryCodes, offset: _offset);
      if (generation != _searchGeneration) {
        return;
      }
      final merged = more ? [...results, ...page.stations] : page.stations;
      final seen = <String>{};
      results = merged.where((s) => seen.add(s.id)).toList();
      hasMore = page.hasMore;
      _offset += CatalogClient.pageSize;
    } catch (_) {
      if (generation == _searchGeneration) {
        error = 'Catálogo indisponível. Confira a conexão e tente novamente.';
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
    onProgress?.call(position);
    catalog.close();
    unawaited(player.dispose());
    super.dispose();
  }
}
