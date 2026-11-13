import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'radio_store.dart';

Uri? webURL(String value, [Uri? base]) {
  if (value.trim().isEmpty) {
    return null;
  }
  final raw = Uri.tryParse(value.trim());
  if (raw == null) {
    return null;
  }
  final url = base?.resolveUri(raw) ?? raw;
  return ['http', 'https'].contains(url.scheme) &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty
      ? url
      : null;
}

String plainText(String text) {
  var value = text
      .replaceAll(RegExp('<[^>]*>'), ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  value = value.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (match) {
    final raw = match[1]!;
    final number = int.tryParse(
      raw.startsWith('x') ? raw.substring(1) : raw,
      radix: raw.startsWith('x') ? 16 : 10,
    );
    return number != null && number > 0 && number <= 0x10ffff
        ? String.fromCharCode(number)
        : '';
  });
  value = value
      .replaceAll(RegExp('<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return value.length > 12000 ? value.substring(0, 12000) : value;
}

class PodcastShow {
  final String title, author, feed, artwork, summary;
  const PodcastShow({
    required this.title,
    required this.feed,
    this.author = '',
    this.artwork = '',
    this.summary = '',
  });
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'feed': feed,
    'artwork': artwork,
    'summary': summary,
  };
  factory PodcastShow.fromJson(Map j) => PodcastShow(
    title: j['title'],
    feed: j['feed'],
    author: j['author'] ?? '',
    artwork: j['artwork'] ?? '',
    summary: j['summary'] ?? '',
  );
}

class PodcastEpisode {
  final String id, title, audio, summary;
  final double duration;
  final DateTime? published;
  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.audio,
    this.summary = '',
    this.duration = 0,
    this.published,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'audio': audio,
    'summary': summary,
    'duration': duration,
    'published': published?.toIso8601String(),
  };
  factory PodcastEpisode.fromJson(Map j) => PodcastEpisode(
    id: j['id'],
    title: j['title'],
    audio: j['audio'],
    summary: j['summary'] ?? '',
    duration: (j['duration'] as num? ?? 0).toDouble(),
    published: DateTime.tryParse(j['published'] ?? ''),
  );
}

class PodcastFeed {
  final PodcastShow show;
  final List<PodcastEpisode> episodes;
  final String language;
  const PodcastFeed(this.show, this.episodes, this.language);
}

class PodcastClient {
  final http.Client client;
  PodcastClient({http.Client? client}) : client = client ?? http.Client();
  Future<List<int>> data(Uri url, int maximum) async {
    final response = await client
        .send(
          http.Request('GET', url)..headers['User-Agent'] = 'VitraRadio/0.1.10',
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || (response.contentLength ?? 0) > maximum) {
      throw const FormatException('Não foi possível carregar os podcasts.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > maximum) {
        throw const FormatException('O RSS é muito grande.');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<List<PodcastShow>> search(String term, String country) async {
    final bytes = await data(
      Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'country': country,
        'media': 'podcast',
        'entity': 'podcast',
        'limit': '24',
      }),
      2000000,
    );
    final rows = (jsonDecode(utf8.decode(bytes)) as Map)['results'] as List;
    final seen = <String>{};
    return rows
        .whereType<Map>()
        .where(
          (j) =>
              webURL(j['feedUrl'] ?? '') != null &&
              (j['collectionName'] as String? ?? '').isNotEmpty &&
              seen.add(j['feedUrl']),
        )
        .map(
          (j) => PodcastShow(
            title: j['collectionName'],
            feed: j['feedUrl'],
            author: j['artistName'] ?? '',
            artwork: j['artworkUrl600'] ?? j['artworkUrl100'] ?? '',
          ),
        )
        .toList();
  }

  Future<PodcastFeed> feed(PodcastShow show) async => parse(
    await data(
      webURL(show.feed) ??
          (throw const FormatException('Endereço RSS inválido.')),
      20000000,
    ),
    show,
  );
  static PodcastFeed parse(List<int> bytes, PodcastShow source) {
    if (bytes.length > 20000000) {
      throw const FormatException('O RSS é muito grande.');
    }
    String xml;
    if (bytes.length > 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      final le = bytes[0] == 255;
      xml = String.fromCharCodes([
        for (var i = 2; i + 1 < bytes.length; i += 2)
          le ? bytes[i] + bytes[i + 1] * 256 : bytes[i] * 256 + bytes[i + 1],
      ]);
    } else {
      xml = utf8.decode(bytes);
    }
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(xml)) {
      throw const FormatException('Declaração XML não permitida.');
    }
    final doc = XmlDocument.parse(xml), root = doc.rootElement;
    if (!['rss', 'feed', 'RDF'].contains(root.name.local)) {
      throw const FormatException('Este endereço não contém um podcast RSS.');
    }
    final channel =
        root.childElements
            .where((e) => e.name.local == 'channel')
            .firstOrNull ??
        root;
    String text(XmlElement e, List<String> names) {
      for (final n in names) {
        final node = e.childElements
            .where((x) => x.name.qualified == n || x.name.local == n)
            .firstOrNull;
        if (node != null && node.innerText.trim().isNotEmpty) {
          return plainText(node.innerText);
        }
      }
      return '';
    }

    final base = webURL(source.feed)!;
    final image = channel.childElements
        .where((e) => e.name.local == 'image')
        .firstOrNull;
    final imageURL =
        image?.getAttribute('href') ??
        image?.childElements
            .where((e) => e.name.local == 'url')
            .firstOrNull
            ?.innerText ??
        source.artwork;
    final title = text(channel, ['title']);
    final show = PodcastShow(
      title: title.isEmpty ? source.title : title,
      feed: source.feed,
      author: text(channel, ['itunes:author', 'author']),
      summary: text(channel, ['description', 'subtitle']),
      artwork: webURL(imageURL, base)?.toString() ?? source.artwork,
    );
    final episodes = <PodcastEpisode>[], seen = <String>{};
    for (final item in root.descendants.whereType<XmlElement>().where(
      (e) => ['item', 'entry'].contains(e.name.local),
    )) {
      if (episodes.length >= 500) {
        break;
      }
      final enclosure = item.childElements
          .where(
            (e) =>
                e.name.local == 'enclosure' ||
                (e.name.local == 'link' &&
                    e.getAttribute('rel') == 'enclosure'),
          )
          .where(
            (e) =>
                (e.getAttribute('type') ?? 'audio/').startsWith('audio/') ||
                e.getAttribute('type') == 'application/octet-stream',
          )
          .firstOrNull;
      final audio = webURL(
        enclosure?.getAttribute('url') ?? enclosure?.getAttribute('href') ?? '',
        base,
      );
      if (enclosure == null || audio == null) {
        continue;
      }
      final guid = text(item, ['guid', 'id']);
      final id = sha256
          .convert(utf8.encode('${source.feed}|${guid.isEmpty ? audio : guid}'))
          .toString();
      if (!seen.add(id)) {
        continue;
      }
      DateTime? date;
      final stamp = text(item, ['pubDate', 'published', 'updated']);
      try {
        date = DateTime.tryParse(stamp) ?? HttpDate.parse(stamp);
      } catch (_) {}
      episodes.add(
        PodcastEpisode(
          id: id,
          title: text(item, ['title']),
          audio: audio.toString(),
          summary: text(item, ['description', 'summary', 'content', 'encoded']),
          duration: parseDuration(text(item, ['itunes:duration'])),
          published: date,
        ),
      );
    }
    if (episodes.isEmpty) {
      throw const FormatException(
        'Nenhum episódio de áudio compatível neste RSS.',
      );
    }
    episodes.sort(
      (a, b) => (b.published ?? DateTime(1900)).compareTo(
        a.published ?? DateTime(1900),
      ),
    );
    return PodcastFeed(show, episodes, text(channel, ['language']));
  }

  static double parseDuration(String value) {
    final parts = value.split(':');
    if (parts.length > 3) {
      return 0;
    }
    double seconds = 0;
    for (final part in parts) {
      final n = double.tryParse(part);
      if (n == null || !n.isFinite || n < 0) {
        return 0;
      }
      seconds = seconds * 60 + n;
    }
    return seconds.clamp(0, 604800);
  }

  void close() => client.close();
}

class RecentPodcast {
  final PodcastShow show;
  final PodcastEpisode episode;
  RecentPodcast(this.show, this.episode);
  Map<String, dynamic> toJson() => {
    'show': show.toJson(),
    'episode': episode.toJson(),
  };
}

class PodcastStore extends ChangeNotifier {
  List<RecentPodcast> recents = [];
  final SharedPreferences prefs;
  final PodcastClient client;
  List<PodcastShow> favorites = [], results = [];
  PodcastFeed? opened;
  PodcastShow? lastShow;
  PodcastEpisode? lastEpisode;
  Map<String, dynamic> progress = {};
  bool searching = false, loading = false;
  String? lastCountry;
  String? error;
  int _generation = 0, _feedGeneration = 0, _lastSaved = -1;
  PodcastStore(this.prefs, {PodcastClient? client})
    : client = client ?? PodcastClient() {
    try {
      favorites =
          (jsonDecode(prefs.getString('podcastFavorites') ?? '[]') as List)
              .map((j) => PodcastShow.fromJson(j))
              .where((s) => webURL(s.feed) != null)
              .toList();
      progress = Map<String, dynamic>.from(
        jsonDecode(prefs.getString('podcastProgress') ?? '{}'),
      );
      final episode = prefs.getString('podcastLastEpisode'),
          show = prefs.getString('podcastLastShow');
      if (episode != null && show != null) {
        lastEpisode = PodcastEpisode.fromJson(jsonDecode(episode));
        lastShow = PodcastShow.fromJson(jsonDecode(show));
      }
      recents = (jsonDecode(prefs.getString('podcastRecents') ?? '[]') as List)
          .map(
            (j) => RecentPodcast(
              PodcastShow.fromJson(j['show']),
              PodcastEpisode.fromJson(j['episode']),
            ),
          )
          .where(
            (item) =>
                webURL(item.show.feed) != null &&
                webURL(item.episode.audio) != null,
          )
          .take(50)
          .toList();
      if (recents.isEmpty && lastShow != null && lastEpisode != null) {
        recents = [RecentPodcast(lastShow!, lastEpisode!)];
      }
    } catch (_) {
      error = 'Não foi possível ler parte dos podcasts salvos.';
    }
  }
  void favorite(PodcastShow show) {
    if (favorites.any((s) => s.feed == show.feed)) {
      favorites.removeWhere((s) => s.feed == show.feed);
    } else {
      favorites.add(show);
    }
    unawaited(
      prefs.setString(
        'podcastFavorites',
        jsonEncode(favorites.map((s) => s.toJson()).toList()),
      ),
    );
    notifyListeners();
  }

  Future<void> search(
    String term,
    String country, {
    String language = '',
  }) async {
    final generation = ++_generation;
    lastCountry = country;
    searching = true;
    error = null;
    notifyListeners();
    try {
      var found = await client.search(
        term.trim().isEmpty ? 'podcast' : term.trim(),
        country,
      );
      if (language.isNotEmpty) {
        final filtered = <PodcastShow>[];
        for (var i = 0; i < found.length; i += 4) {
          final rows = await Future.wait(
            found.skip(i).take(4).map((s) async {
              try {
                final f = await client.feed(s);
                return f.language.toLowerCase().startsWith(language)
                    ? f.show
                    : null;
              } catch (_) {
                return null;
              }
            }),
          );
          filtered.addAll(rows.whereType<PodcastShow>());
          if (generation != _generation) {
            return;
          }
        }
        found = filtered;
      }
      if (generation == _generation) {
        results = found;
      }
    } catch (_) {
      if (generation == _generation) {
        error = 'Não foi possível carregar os podcasts. Tente novamente.';
      }
    } finally {
      if (generation == _generation) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<void> open(PodcastShow show) async {
    final generation = ++_feedGeneration;
    loading = true;
    error = null;
    opened = null;
    notifyListeners();
    try {
      final feed = await client.feed(show);
      if (generation == _feedGeneration) {
        opened = feed;
      }
    } catch (_) {
      if (generation == _feedGeneration) {
        error =
            'Não foi possível abrir o RSS. Confira o endereço e tente novamente.';
      }
    } finally {
      if (generation == _feedGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void closeFeed() {
    _feedGeneration++;
    opened = null;
    loading = false;
    error = null;
    notifyListeners();
  }

  double position(String id) =>
      (progress[id] as Map?)?['seconds'] as double? ?? 0;
  void _saveProgress(String id, Duration value, {bool completed = false}) {
    if (progress.length >= 500 && !progress.containsKey(id)) {
      progress.remove(progress.keys.first);
    }
    progress[id] = {
      'seconds': completed ? 0.0 : value.inMilliseconds / 1000,
      'completed': completed,
    };
    unawaited(prefs.setString('podcastProgress', jsonEncode(progress)));
  }

  Future<void> play(
    PodcastShow show,
    PodcastEpisode episode,
    RadioStore radio,
  ) async {
    if (webURL(episode.audio) == null) {
      return;
    }
    if (radio.mediaID == episode.id) {
      if (!radio.playing) {
        await radio.toggle();
      }
      return;
    }
    recents.removeWhere((item) => item.episode.id == episode.id);
    recents.insert(0, RecentPodcast(show, episode));
    recents = recents.take(50).toList();
    await prefs.setString(
      'podcastRecents',
      jsonEncode(recents.map((item) => item.toJson()).toList()),
    );
    lastShow = show;
    lastEpisode = episode;
    _lastSaved = -1;
    await prefs.setString('podcastLastEpisode', jsonEncode(episode.toJson()));
    await prefs.setString('podcastLastShow', jsonEncode(show.toJson()));
    await radio.playMedia(
      id: episode.id,
      title: episode.title,
      artist: show.title,
      url: episode.audio,
      resume: Duration(milliseconds: (position(episode.id) * 1000).round()),
      progress: (value) {
        if ((value.inSeconds - _lastSaved).abs() >= 5 || !radio.playing) {
          _lastSaved = value.inSeconds;
          _saveProgress(episode.id, value);
        }
      },
      completed: () {
        _saveProgress(episode.id, Duration.zero, completed: true);
        notifyListeners();
      },
    );
    notifyListeners();
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
