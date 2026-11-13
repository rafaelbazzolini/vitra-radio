import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'radio_store.dart';

const onlineSources = ['Internet Archive', 'Jamendo'];
const onlineFields = [
  'Tudo',
  'Nome da música',
  'Cantor / artista',
  'Compositor',
];
const onlineGenres = [
  '',
  'electronic',
  'rock',
  'pop',
  'jazz',
  'classical',
  'ambient',
  'relaxation',
  'hiphop',
  'instrumental',
];
String onlineGenreTitle(String genre) =>
    const {
      '': 'Todas as categorias',
      'electronic': 'Eletrônica',
      'rock': 'Rock',
      'pop': 'Pop',
      'jazz': 'Jazz',
      'classical': 'Clássica',
      'ambient': 'Ambient',
      'relaxation': 'Relaxamento',
      'hiphop': 'Hip-hop',
      'instrumental': 'Instrumental',
    }[genre] ??
    genre;
String onlineText(dynamic value) => value is String
    ? value.substring(0, value.length.clamp(0, 1000))
    : value is List
    ? value.take(4).map(onlineText).join(' · ')
    : '';
bool safeOnlineID(String value) =>
    RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value) &&
    value != '.' &&
    value != '..';
Uri? onlineURL(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class OnlineMusicItem {
  final String source, remoteID, title, artist, album, license;
  final String? file;
  const OnlineMusicItem({
    required this.source,
    required this.remoteID,
    required this.title,
    this.artist = '',
    this.album = '',
    this.file,
    this.license = '',
  });
  String get id => '$source:$remoteID:${file ?? ''}';
  bool get isCollection => source == 'Internet Archive' && file == null;
  Uri get page => source == 'Internet Archive'
      ? Uri.https('archive.org', '/details/$remoteID')
      : Uri.https('www.jamendo.com', '/track/$remoteID');
  Map<String, dynamic> toJson() => {
    'source': source,
    'remoteID': remoteID,
    'title': title,
    'artist': artist,
    'album': album,
    'file': file,
    'license': license,
  };
  factory OnlineMusicItem.fromJson(Map<String, dynamic> j) => OnlineMusicItem(
    source: j['source'],
    remoteID: j['remoteID'],
    title: j['title'],
    artist: j['artist'] ?? '',
    album: j['album'] ?? '',
    file: j['file'],
    license: j['license'] ?? '',
  );
}

class OnlinePlaylist {
  final String id;
  String name;
  final List<OnlineMusicItem> tracks;
  OnlinePlaylist(this.id, this.name, [List<OnlineMusicItem>? tracks])
    : tracks = tracks ?? [];
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };
  factory OnlinePlaylist.fromJson(Map<String, dynamic> j) => OnlinePlaylist(
    j['id'],
    j['name'],
    (j['tracks'] as List)
        .map((t) => OnlineMusicItem.fromJson(Map<String, dynamic>.from(t)))
        .toList(),
  );
}

class OnlinePage {
  final List<OnlineMusicItem> items;
  final bool hasMore;
  OnlinePage(this.items, this.hasMore);
}

class OnlineMusicClient {
  final http.Client client;
  OnlineMusicClient({http.Client? client}) : client = client ?? http.Client();
  Future<Map<String, dynamic>> json(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'VitraRadio/0.1.11';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > 12000000) {
      throw const FormatException('A fonte não respondeu. Tente novamente.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      if (bytes.length + chunk.length > 12000000) {
        throw const FormatException('A resposta da fonte excedeu o limite.');
      }
      bytes.addAll(chunk);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
  }

  static String quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  Future<OnlinePage> search({
    required String source,
    required String text,
    required String field,
    required String genre,
    required int page,
    required String clientID,
  }) async {
    final term = text.trim().substring(0, text.trim().length.clamp(0, 200));
    if (source == 'Jamendo') {
      if (clientID.isEmpty) {
        throw const FormatException(
          'Configure o Client ID do Jamendo para pesquisar nesta fonte.',
        );
      }
      if (field == 'Compositor') {
        throw const FormatException(
          'O Jamendo não possui filtro de compositor. Use Tudo ou Cantor / artista.',
        );
      }
      final params = {
        'client_id': clientID,
        'format': 'json',
        'limit': '24',
        'offset': '${(page - 1) * 24}',
        'type': 'single albumtrack',
        'audioformat': 'mp32',
        'include': 'licenses',
      };
      if (term.isNotEmpty) {
        params[field == 'Nome da música'
                ? 'namesearch'
                : field == 'Cantor / artista'
                ? 'artist_name'
                : 'search'] =
            term;
      }
      if (genre.isNotEmpty) {
        params['tags'] = genre;
      }
      if (term.isEmpty) {
        params['order'] = 'popularity_total';
      }
      final data = await json(
        Uri.https('api.jamendo.com', '/v3.0/tracks/', params),
      );
      return OnlinePage(
        jamendoItems(data),
        (data['results'] as List).length == 24,
      );
    }
    final clauses = [
      'mediatype:audio',
      '(collection:etree OR collection:netlabels OR collection:audio_music OR collection:georgeblood)',
      '-access-restricted-item:true',
    ];
    if (term.isNotEmpty) {
      final q = quote(term);
      clauses.add(switch (field) {
        'Nome da música' => 'title:$q',
        'Cantor / artista' => 'creator:$q',
        'Compositor' => 'composer:$q',
        _ => '(title:$q OR creator:$q OR composer:$q OR description:$q)',
      });
    }
    if (genre.isNotEmpty) {
      clauses.add('subject:${quote(genre)}');
    }
    final params = {
      'q': clauses.join(' AND '),
      'output': 'json',
      'rows': '24',
      'page': '$page',
      'fl[]': 'identifier,title,creator,licenseurl',
    };
    if (term.isEmpty) {
      params['sort[]'] = 'downloads desc';
    }
    final data = await json(
      Uri.https('archive.org', '/advancedsearch.php', params),
    );
    final response = data['response'] as Map;
    final items = (response['docs'] as List)
        .where((r) => safeOnlineID(onlineText(r['identifier'])))
        .map(
          (r) => OnlineMusicItem(
            source: 'Internet Archive',
            remoteID: onlineText(r['identifier']),
            title: onlineText(r['title']),
            artist: onlineText(r['creator']),
            license: onlineText(r['licenseurl']),
          ),
        )
        .toList();
    return OnlinePage(items, page * 24 < (response['numFound'] as num));
  }

  static List<OnlineMusicItem> jamendoItems(Map<String, dynamic> json) {
    if (json['headers']?['status'] != 'success' || json['results'] is! List) {
      throw const FormatException(
        'O Jamendo não aceitou a consulta. Confira o Client ID e tente novamente.',
      );
    }
    return (json['results'] as List)
        .where(
          (r) =>
              RegExp(r'^\d+$').hasMatch(onlineText(r['id'])) &&
              onlineURL(onlineText(r['audio'])) != null,
        )
        .map(
          (r) => OnlineMusicItem(
            source: 'Jamendo',
            remoteID: onlineText(r['id']),
            title: onlineText(r['name']),
            artist: onlineText(r['artist_name']),
            album: onlineText(r['album_name']),
            license: onlineText(r['license_ccurl']),
          ),
        )
        .toList();
  }

  static List<OnlineMusicItem> archiveFiles(
    Map<String, dynamic> json,
    OnlineMusicItem item,
  ) {
    final metadata = json['metadata'] as Map? ?? {};
    bool restricted(dynamic v) =>
        v == true || v == 1 || v == 'true' || v == '1';
    if (restricted(json['is_dark']) ||
        restricted(metadata['access-restricted-item']) ||
        json['files'] is! List) {
      throw const FormatException(
        'Este item está indisponível ou tem acesso restrito.',
      );
    }
    final files = List<Map<String, dynamic>>.from(
      (json['files'] as List).map((f) => Map<String, dynamic>.from(f)),
    )..sort((a, b) => onlineText(a['name']).compareTo(onlineText(b['name'])));
    final seen = <String>{}, tracks = <OnlineMusicItem>[];
    for (final f in files) {
      final name = onlineText(f['name']),
          ext = name.split('.').last.toLowerCase();
      if (name.startsWith('/') ||
          name.split('/').contains('..') ||
          restricted(f['private']) ||
          !['mp3', 'm4a', 'ogg'].contains(ext)) {
        continue;
      }
      final original = onlineText(f['original']);
      final key = (original.isEmpty ? name : original).replaceFirst(
        RegExp(r'\.[^.]+$'),
        '',
      );
      if (!seen.add(key)) {
        continue;
      }
      tracks.add(
        OnlineMusicItem(
          source: 'Internet Archive',
          remoteID: item.remoteID,
          title: onlineText(f['title']).isEmpty
              ? name.replaceFirst(RegExp(r'\.[^.]+$'), '')
              : onlineText(f['title']),
          artist: onlineText(f['creator']).isEmpty
              ? item.artist
              : onlineText(f['creator']),
          album: item.title,
          file: name,
          license: onlineText(metadata['licenseurl']).isEmpty
              ? item.license
              : onlineText(metadata['licenseurl']),
        ),
      );
      if (tracks.length >= 500) {
        break;
      }
    }
    return tracks;
  }

  Future<List<OnlineMusicItem>> files(OnlineMusicItem item) async {
    if (!safeOnlineID(item.remoteID)) {
      throw const FormatException('Item inválido.');
    }
    return archiveFiles(
      await json(Uri.https('archive.org', '/metadata/${item.remoteID}')),
      item,
    );
  }

  Future<Uri> stream(OnlineMusicItem item, String clientID) async {
    if (item.source == 'Internet Archive') {
      final available = await files(item);
      if (item.file == null || !available.any((t) => t.file == item.file)) {
        throw const FormatException(
          'Esta faixa não está mais disponível para reprodução.',
        );
      }
      return Uri(
        scheme: 'https',
        host: 'archive.org',
        pathSegments: ['download', item.remoteID, ...item.file!.split('/')],
      );
    }
    if (clientID.isEmpty) {
      throw const FormatException(
        'Configure o Client ID do Jamendo para pesquisar nesta fonte.',
      );
    }
    final data = await json(
      Uri.https('api.jamendo.com', '/v3.0/tracks/', {
        'client_id': clientID,
        'id': item.remoteID,
        'format': 'json',
        'audioformat': 'mp32',
      }),
    );
    final valid = jamendoItems(data);
    if (valid.isEmpty || valid.first.remoteID != item.remoteID) {
      throw const FormatException(
        'Esta faixa não está mais disponível para reprodução.',
      );
    }
    return onlineURL(onlineText((data['results'] as List).first['audio']))!;
  }

  void close() => client.close();
}

class OnlineMusicStore extends ChangeNotifier {
  final SharedPreferences prefs;
  final OnlineMusicClient client;
  List<OnlinePlaylist> playlists = [];
  List<OnlineMusicItem> results = [], tracks = [];
  OnlineMusicItem? opened;
  String? error, notice;
  bool working = false, resolving = false, hasMore = false;
  int _generation = 0, _playGeneration = 0, _page = 1, _index = 0;
  List<OnlineMusicItem> _queue = [];
  String clientID;
  Map<String, String>? _query;
  OnlineMusicStore(this.prefs, {OnlineMusicClient? client})
    : client = client ?? OnlineMusicClient(),
      clientID =
          prefs.getString('jamendoClientID') ??
          const String.fromEnvironment('JAMENDO_CLIENT_ID') {
    try {
      playlists =
          (jsonDecode(prefs.getString('onlinePlaylists') ?? '[]') as List)
              .map((j) => OnlinePlaylist.fromJson(Map<String, dynamic>.from(j)))
              .toList();
    } catch (_) {
      error = 'Não foi possível ler as playlists salvas.';
    }
  }
  Future<void> setClientID(String id) async {
    clientID = id.trim();
    await prefs.setString('jamendoClientID', clientID);
    notifyListeners();
  }

  String _message(Object e) => e is FormatException
      ? e.message.toString()
      : 'Não foi possível acessar a fonte. Confira a conexão e tente novamente.';
  Future<void> search({
    required String source,
    required String text,
    required String field,
    required String genre,
    bool more = false,
  }) async {
    final token = ++_generation;
    working = true;
    error = null;
    if (!more) {
      _page = 1;
      results = [];
      opened = null;
      tracks = [];
      hasMore = false;
    }
    final page = more ? _page + 1 : 1;
    notifyListeners();
    try {
      final found = await client.search(
        source: source,
        text: text,
        field: field,
        genre: genre,
        page: page,
        clientID: clientID,
      );
      if (token != _generation) {
        return;
      }
      final seen = <String>{};
      results = [
        ...(more ? results : <OnlineMusicItem>[]),
        ...found.items,
      ].where((t) => seen.add(t.id)).toList();
      _page = page;
      hasMore = found.hasMore;
      _query = {'source': source, 'text': text, 'field': field, 'genre': genre};
    } catch (e) {
      if (token == _generation) {
        error = _message(e);
      }
    }
    if (token == _generation) {
      working = false;
      notifyListeners();
    }
  }

  Future<void> more() async {
    final q = _query;
    if (q == null || working || !hasMore) {
      return;
    }
    await search(
      source: q['source']!,
      text: q['text']!,
      field: q['field']!,
      genre: q['genre']!,
      more: true,
    );
  }

  Future<void> open(OnlineMusicItem item) async {
    final token = ++_generation;
    working = true;
    opened = item;
    tracks = [];
    error = null;
    notifyListeners();
    try {
      final found = await client.files(item);
      if (token == _generation) {
        tracks = found;
      }
    } catch (e) {
      if (token == _generation) {
        error = _message(e);
      }
    }
    if (token == _generation) {
      working = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    results = [];
    hasMore = false;
    _query = null;
    closeCollection();
  }

  void closeCollection() {
    _generation++;
    opened = null;
    tracks = [];
    error = null;
    working = false;
    notifyListeners();
  }

  void _save() {
    unawaited(
      prefs.setString(
        'onlinePlaylists',
        jsonEncode(playlists.map((p) => p.toJson()).toList()),
      ),
    );
    notifyListeners();
  }

  String? create(String name) {
    name = name.trim();
    if (name.isEmpty || playlists.length >= 100) {
      return null;
    }
    final list = OnlinePlaylist(
      '${DateTime.now().microsecondsSinceEpoch}-${playlists.length}',
      name.substring(0, name.length.clamp(0, 120)),
    );
    playlists.add(list);
    _save();
    return list.id;
  }

  void rename(String id, String name) {
    final list = playlists.where((p) => p.id == id).firstOrNull;
    if (list == null || name.trim().isEmpty) {
      return;
    }
    list.name = name.trim().substring(0, name.trim().length.clamp(0, 120));
    _save();
  }

  void delete(String id) {
    playlists.removeWhere((p) => p.id == id);
    _save();
  }

  void movePlaylist(String id, int direction) {
    final i = playlists.indexWhere((p) => p.id == id),
        j = playlists.indexWhere((p) => p.id == id) + direction;
    if (i < 0 || j < 0 || j >= playlists.length) {
      return;
    }
    final list = playlists.removeAt(i);
    playlists.insert(j, list);
    _save();
  }

  void add(OnlineMusicItem item, String id) {
    final list = playlists.where((p) => p.id == id).firstOrNull;
    if (list == null || item.isCollection || list.tracks.length >= 500) {
      return;
    }
    if (list.tracks.any((t) => t.id == item.id)) {
      notice = 'Esta faixa já está na playlist.';
      notifyListeners();
      return;
    }
    list.tracks.add(item);
    notice = 'Faixa adicionada à playlist.';
    _save();
  }

  void remove(OnlineMusicItem item, String id) {
    playlists
        .where((p) => p.id == id)
        .firstOrNull
        ?.tracks
        .removeWhere((t) => t.id == item.id);
    _save();
  }

  void moveTrack(OnlineMusicItem item, String id, int direction) {
    final list = playlists.where((p) => p.id == id).firstOrNull;
    if (list == null) {
      return;
    }
    final i = list.tracks.indexWhere((t) => t.id == item.id),
        j = list.tracks.indexWhere((t) => t.id == item.id) + direction;
    if (i < 0 || j < 0 || j >= list.tracks.length) {
      return;
    }
    final track = list.tracks.removeAt(i);
    list.tracks.insert(j, track);
    _save();
  }

  Future<void> play(
    OnlineMusicItem item,
    List<OnlineMusicItem> queue,
    RadioStore radio,
  ) async {
    final i = queue.indexWhere((t) => t.id == item.id);
    if (i < 0 || item.isCollection) {
      return;
    }
    _queue = List.of(queue);
    _index = i;
    await _start(radio);
  }

  Future<void> _start(RadioStore radio) async {
    final token = ++_playGeneration, intent = radio.playbackRevision;
    final item = _queue[_index];
    resolving = true;
    error = null;
    notifyListeners();
    try {
      final uri = await client.stream(item, clientID);
      if (token != _playGeneration || intent != radio.playbackRevision) {
        if (token == _playGeneration) {
          resolving = false;
          notifyListeners();
        }
        return;
      }
      await radio.playMedia(
        id: 'online-${item.id}',
        title: item.title,
        artist: item.artist,
        url: uri.toString(),
        step: (direction) => skip(direction, radio),
        completed: () {
          unawaited(skip(1, radio));
        },
      );
    } catch (e) {
      if (token == _playGeneration) {
        error = _message(e);
      }
    }
    if (token == _playGeneration) {
      resolving = false;
      notifyListeners();
    }
  }

  Future<void> skip(int direction, RadioStore radio) async {
    final next = _index + direction;
    if (next < 0 || next >= _queue.length) {
      return;
    }
    _index = next;
    await _start(radio);
  }

  @override
  void dispose() {
    _generation++;
    _playGeneration++;
    client.close();
    super.dispose();
  }
}
