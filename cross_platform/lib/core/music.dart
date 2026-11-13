import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'radio_store.dart';

class MusicProfile {
  final String id, name, kind, address, username, network, folder;
  final bool local;
  const MusicProfile({
    required this.id,
    required this.name,
    this.kind = 'subsonic',
    this.address = '',
    this.username = '',
    this.network = 'local',
    this.folder = '',
    this.local = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'address': address,
    'username': username,
    'network': network,
    'folder': folder,
    'local': local,
  };
  factory MusicProfile.fromJson(Map j) => MusicProfile(
    id: j['id'],
    name: j['name'],
    kind: j['kind'] ?? 'subsonic',
    address: j['address'] ?? '',
    username: j['username'] ?? '',
    network: j['network'] ?? 'local',
    folder: j['folder'] ?? '',
    local: j['local'] ?? false,
  );
  Uri get base {
    final raw = address.trim();
    var url = Uri.tryParse(
      raw.contains('://')
          ? raw
          : '${network == 'internet' ? 'https' : 'http'}://$raw',
    );
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (network == 'internet' && url.scheme != 'https')) {
      throw const FormatException(
        'Use um endereço HTTP ou HTTPS válido, sem usuário ou senha na URL. Pela internet, use HTTPS.',
      );
    }
    var path = url.path.replaceAll(RegExp(r'/+$'), '');
    if (kind == 'subsonic' && path.endsWith('/rest')) {
      path = path.substring(0, path.length - 5);
    }
    return url.replace(path: '$path/');
  }
}

class MusicItem {
  final String id, title, artist, album, uri;
  const MusicItem(
    this.id,
    this.title,
    this.artist, {
    this.album = '',
    this.uri = '',
  });
}

class MusicClient {
  final MusicProfile profile;
  final Map<String, dynamic> credential;
  final http.Client httpClient;
  MusicClient(this.profile, this.credential, {http.Client? client})
    : httpClient = client ?? http.Client();
  Map<String, String> auth() {
    final random = Random.secure();
    final salt = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return {
      'u': profile.username,
      't': md5
          .convert(utf8.encode('${credential['password'] ?? ''}$salt'))
          .toString(),
      's': salt,
      'v': '1.16.1',
      'c': 'VitraRadio',
      'f': 'json',
    };
  }

  String get authorization =>
      'MediaBrowser Client="VitraRadio", Device="Android", DeviceId="${profile.id}", Version="0.1.10"${credential['token'] != null ? ', Token="${credential['token'].toString().replaceAll('"', '')}"' : ''}';
  Future<Map<String, dynamic>> json(
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    bool subsonic = false,
  }) async {
    var url = profile.base
        .resolve(path)
        .replace(queryParameters: subsonic || query.isEmpty ? null : query);
    for (var redirect = 0; redirect < 4; redirect++) {
      final request = http.Request(
        subsonic || body != null ? 'POST' : 'GET',
        url,
      )..followRedirects = false;
      request.headers.addAll({
        'User-Agent': 'VitraRadio/0.1.10',
        'Accept': 'application/json',
      });
      if (subsonic) {
        request.bodyFields = {...auth(), ...query};
      } else {
        request.headers['Authorization'] = authorization;
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
      }
      final response = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 20));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.drain<void>();
        final next = url.resolve(response.headers['location'] ?? '');
        if (next.host != profile.base.host ||
            next.port != profile.base.port ||
            next.userInfo.isNotEmpty ||
            next.scheme != url.scheme) {
          throw const FormatException(
            'Redirecionamento do servidor não permitido. Confira o endereço base.',
          );
        }
        url = next;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw const FormatException(
          'Servidor não respondeu. Confira endereço, usuário e senha.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (bytes.length + chunk.length > 10000000) {
          throw const FormatException('Resposta do servidor muito grande.');
        }
        bytes.addAll(chunk);
      }
      final data = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      if (!subsonic) {
        return data;
      }
      final value = data['subsonic-response'];
      if (value is! Map || value['status'] != 'ok') {
        throw const FormatException(
          'Usuário, senha ou API Subsonic não aceitos.',
        );
      }
      return Map<String, dynamic>.from(value);
    }
    throw const FormatException('Muitos redirecionamentos no servidor.');
  }

  Future<Map<String, dynamic>> authenticate(String password) async {
    if (profile.kind == 'subsonic') {
      final secret = password.isEmpty ? credential['password'] ?? '' : password;
      if (profile.username.isEmpty || secret.isEmpty) {
        throw const FormatException('Informe o usuário e a senha do servidor.');
      }
      final test = MusicClient(profile, {
        'password': secret,
      }, client: httpClient);
      await test.json('rest/ping.view', subsonic: true);
      return {'password': secret};
    }
    if (password.isEmpty && credential['token'] != null) {
      await json('Users/${Uri.encodeComponent(credential['userID'])}');
      return credential;
    }
    final data = await json(
      'Users/AuthenticateByName',
      body: {'Username': profile.username, 'Pw': password},
    );
    if (data['AccessToken'] is! String || data['User']?['Id'] is! String) {
      throw const FormatException('O Jellyfin não retornou uma sessão válida.');
    }
    return {'token': data['AccessToken'], 'userID': data['User']['Id']};
  }

  Future<({List<MusicItem> items, bool more})> albums(int offset) async {
    if (profile.kind == 'subsonic') {
      final data = await json(
        'rest/getAlbumList2.view',
        subsonic: true,
        query: {'type': 'newest', 'size': '40', 'offset': '$offset'},
      );
      final rows = (data['albumList2']?['album'] as List? ?? [])
          .whereType<Map>()
          .toList();
      return (
        items: rows
            .map(
              (j) => MusicItem(
                '${j['id']}',
                j['name'] ?? 'Álbum',
                j['artist'] ?? '',
              ),
            )
            .toList(),
        more: rows.length == 40,
      );
    }
    final data = await json(
      'Users/${Uri.encodeComponent(credential['userID'])}/Items',
      query: {
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': 'true',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'StartIndex': '$offset',
        'Limit': '40',
      },
    );
    final rows = (data['Items'] as List? ?? []).whereType<Map>().toList();
    return (
      items: rows
          .map(
            (j) => MusicItem(
              '${j['Id']}',
              j['Name'] ?? 'Álbum',
              j['AlbumArtist'] ?? '',
            ),
          )
          .toList(),
      more:
          offset + rows.length <
          (data['TotalRecordCount'] as int? ?? rows.length),
    );
  }

  Future<List<MusicItem>> tracks({MusicItem? album, String search = ''}) async {
    if (profile.kind == 'subsonic') {
      final data = await json(
        album == null ? 'rest/search3.view' : 'rest/getAlbum.view',
        subsonic: true,
        query: album == null
            ? {
                'query': search,
                'songCount': '100',
                'albumCount': '0',
                'artistCount': '0',
              }
            : {'id': album.id},
      );
      final container = data[album == null ? 'searchResult3' : 'album'] as Map?;
      final rows = container?['song'] as List? ?? [];
      return rows
          .whereType<Map>()
          .map(
            (j) => MusicItem(
              '${j['id']}',
              j['title'] ?? 'Faixa',
              j['artist'] ?? '',
              album: j['album'] ?? '',
            ),
          )
          .toList();
    }
    final data = await json(
      'Users/${Uri.encodeComponent(credential['userID'])}/Items',
      query: {
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
        'Limit': '100',
        if (album != null) 'ParentId': album.id,
        if (search.isNotEmpty) 'SearchTerm': search,
      },
    );
    return (data['Items'] as List? ?? [])
        .whereType<Map>()
        .map(
          (j) => MusicItem(
            '${j['Id']}',
            j['Name'] ?? 'Faixa',
            (j['Artists'] as List? ?? []).join(', '),
            album: j['Album'] ?? '',
          ),
        )
        .toList();
  }

  String playback(MusicItem track) => profile.kind == 'subsonic'
      ? profile.base
            .resolve('rest/stream.view')
            .replace(queryParameters: {...auth(), 'id': track.id})
            .toString()
      : profile.base
            .resolve('Audio/${Uri.encodeComponent(track.id)}/stream')
            .replace(
              queryParameters: {
                'static': 'true',
                'api_key': credential['token'],
              },
            )
            .toString();
  void close() => httpClient.close();
}

class DeviceMusic {
  static const channel = MethodChannel('com.vitra.radio/device-music');
  static Future<Map?> choose() => channel.invokeMapMethod('chooseFolder');
  static Future<List<MusicItem>> scan(String uri) async {
    final rows =
        await channel.invokeListMethod('scanFolder', {'uri': uri}) ?? [];
    return rows
        .whereType<Map>()
        .map((j) => MusicItem(j['uri'], j['title'], '', uri: j['uri']))
        .toList();
  }
}

class MusicStore extends ChangeNotifier {
  final SharedPreferences prefs;
  final FlutterSecureStorage vault = const FlutterSecureStorage();
  List<MusicProfile> profiles = [];
  MusicProfile? active;
  MusicClient? _client;
  List<MusicItem> albums = [], tracks = [];
  bool working = false, showingTracks = false, hasMore = false;
  String? error;
  String searchText = '';
  int _generation = 0;
  MusicStore(this.prefs) {
    try {
      profiles = (jsonDecode(prefs.getString('musicProfiles') ?? '[]') as List)
          .map((j) => MusicProfile.fromJson(j))
          .toList();
    } catch (_) {
      error = 'Não foi possível ler suas bibliotecas.';
    }
  }
  Future<Map<String, dynamic>> credential(String id) async =>
      Map<String, dynamic>.from(
        jsonDecode(await vault.read(key: 'music-$id') ?? '{}'),
      );
  Future<void> test(MusicProfile profile, String password) async {
    if (profile.kind == 'folder') {
      if (profile.folder.isEmpty) {
        throw const FormatException('Escolha uma pasta de músicas.');
      }
      await DeviceMusic.scan(profile.folder);
      return;
    }
    final client = MusicClient(profile, await credential(profile.id));
    try {
      await client.authenticate(password);
    } finally {
      client.close();
    }
  }

  Future<bool> save(MusicProfile profile, String password) async {
    if (working) {
      return false;
    }
    working = true;
    error = null;
    notifyListeners();
    try {
      if (profile.kind != 'folder') {
        final client = MusicClient(profile, await credential(profile.id));
        try {
          final verified = await client.authenticate(password);
          await vault.write(
            key: 'music-${profile.id}',
            value: jsonEncode(verified),
          );
        } finally {
          client.close();
        }
      } else {
        await test(profile, password);
      }
      profiles.removeWhere((p) => p.id == profile.id);
      profiles.add(profile);
      await prefs.setString(
        'musicProfiles',
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
      );
      working = false;
      await connect(profile);
      return active?.id == profile.id;
    } catch (_) {
      error =
          'Não foi possível conectar. Confira a pasta, endereço e credenciais.';
      working = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> connect(MusicProfile profile) async {
    if (working) {
      return;
    }
    final generation = ++_generation;
    working = true;
    error = null;
    notifyListeners();
    MusicClient? next;
    try {
      List<MusicItem> nextAlbums = [], nextTracks = [];
      bool more = false;
      if (profile.kind == 'folder') {
        nextTracks = await DeviceMusic.scan(profile.folder);
      } else {
        next = MusicClient(profile, await credential(profile.id));
        final page = await next.albums(0);
        nextAlbums = page.items;
        more = page.more;
      }
      if (generation != _generation) {
        next?.close();
        return;
      }
      _client?.close();
      _client = next;
      active = profile;
      albums = nextAlbums;
      tracks = nextTracks;
      showingTracks = profile.kind == 'folder';
      hasMore = more;
    } catch (_) {
      next?.close();
      error =
          'Não foi possível abrir sua biblioteca. Confira a conexão ou escolha a pasta novamente.';
    } finally {
      if (generation == _generation) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (working || _client == null) {
      return;
    }
    working = true;
    notifyListeners();
    try {
      final page = await _client!.albums(albums.length);
      albums.addAll(page.items);
      hasMore = page.more;
    } catch (_) {
      error = 'Não foi possível carregar mais álbuns.';
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> openAlbum(MusicItem? album, {String search = ''}) async {
    if (working || _client == null) {
      return;
    }
    working = true;
    error = null;
    notifyListeners();
    try {
      tracks = await _client!.tracks(album: album, search: search);
      showingTracks = true;
    } catch (_) {
      error = 'Não foi possível carregar as músicas.';
    } finally {
      working = false;
      notifyListeners();
    }
  }

  void showAlbums() {
    showingTracks = false;
    notifyListeners();
  }

  Future<void> remove(MusicProfile profile, RadioStore radio) async {
    if (working) {
      return;
    }
    if (active?.id == profile.id) {
      await disconnect(radio);
    }
    await vault.delete(key: 'music-${profile.id}');
    profiles.removeWhere((p) => p.id == profile.id);
    await prefs.setString(
      'musicProfiles',
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> disconnect(RadioStore radio) async {
    if (radio.mediaID?.startsWith('music-${active?.id}-') == true) {
      await radio.player.stop();
      radio.mediaTitle = null;
      radio.mediaArtist = null;
    }
    _generation++;
    _client?.close();
    _client = null;
    active = null;
    tracks = [];
    albums = [];
    notifyListeners();
  }

  Future<void> play(MusicItem track, RadioStore radio) async {
    final profile = active;
    if (profile == null) {
      return;
    }
    final url = track.uri.isNotEmpty ? track.uri : _client?.playback(track);
    if (url == null) {
      return;
    }
    await radio.playMedia(
      id: 'music-${profile.id}-${track.id}',
      title: track.title,
      artist: track.artist.isEmpty ? profile.name : track.artist,
      url: url,
      completed: () => unawaited(skip(1, radio)),
    );
  }

  Future<void> skip(int direction, RadioStore radio) async {
    if (tracks.isEmpty) {
      return;
    }
    final index = tracks.indexWhere(
      (t) => radio.mediaID == 'music-${active?.id}-${t.id}',
    );
    await play(tracks[(index + direction) % tracks.length], radio);
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
