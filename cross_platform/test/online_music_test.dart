import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitra_radio/core/online_music.dart';
import 'package:vitra_radio/core/radio_store.dart';

const collection = OnlineMusicItem(
  source: 'Internet Archive',
  remoteID: 'test-album',
  title: 'Album',
  artist: 'Artist',
);
const track = OnlineMusicItem(
  source: 'Internet Archive',
  remoteID: 'test-album',
  title: 'One',
  artist: 'Artist',
  file: 'One & two.mp3',
);
const jamTrack = OnlineMusicItem(
  source: 'Jamendo',
  remoteID: '123',
  title: 'Two',
  artist: 'Artist',
);
Map<String, dynamic> metadata() => {
  'metadata': {'licenseurl': 'https://creativecommons.org/licenses/by/4.0/'},
  'files': [
    {'name': 'One & two.mp3', 'title': 'One', 'original': 'One & two.flac'},
    {'name': 'One & two.ogg', 'original': 'One & two.flac'},
    {'name': 'secret.mp3', 'private': 'true'},
    {'name': '../evil.mp3'},
    {'name': 'picture.png'},
  ],
};

class FakeRadio extends ChangeNotifier implements RadioStore {
  @override
  int playbackRevision = 0;
  @override
  Future<void> Function(int)? onMediaStep;
  @override
  VoidCallback? onMediaCompleted;
  final played = <String>[];
  @override
  Future<void> playMedia({
    required String id,
    required String title,
    required String artist,
    required String url,
    Duration resume = Duration.zero,
    void Function(Duration)? progress,
    VoidCallback? completed,
    Future<void> Function(int)? step,
  }) async {
    playbackRevision++;
    played.add(url);
    onMediaStep = step;
    onMediaCompleted = completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'archive query keeps text literal and filters music collections, category and pagination',
    () async {
      final client = OnlineMusicClient(
        client: MockClient((r) async {
          expect(r.url.host, 'archive.org');
          expect(r.url.queryParameters['page'], '2');
          final q = r.url.queryParameters['q']!;
          expect(q, contains('composer:"A \\"B\\" OR *:*"'));
          expect(q, contains('subject:"jazz"'));
          expect(q, contains('mediatype:audio'));
          expect(q, contains('-access-restricted-item:true'));
          return http.Response(
            jsonEncode({
              'response': {
                'numFound': 50,
                'docs': [
                  {
                    'identifier': 'test-album',
                    'title': 'Álbum',
                    'creator': ['A', 'B'],
                  },
                  {'identifier': '../bad'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final page = await client.search(
        source: 'Internet Archive',
        text: 'A "B" OR *:*',
        field: 'Compositor',
        genre: 'jazz',
        page: 2,
        clientID: '',
      );
      expect(page.items.single.artist, 'A · B');
      expect(page.items.single.title, 'Álbum');
      expect(page.hasMore, true);
      client.close();
    },
  );
  test(
    'archive parser excludes restricted/private items, unsafe paths and duplicate formats',
    () {
      final files = OnlineMusicClient.archiveFiles(metadata(), collection);
      expect(files.length, 1);
      expect(files.single.file, 'One & two.mp3');
      expect(files.single.license, contains('creativecommons'));
      expect(
        () => OnlineMusicClient.archiveFiles({
          'is_dark': true,
          'files': [],
        }, collection),
        throwsFormatException,
      );
      expect(
        () => OnlineMusicClient.archiveFiles({
          'metadata': {'access-restricted-item': 'true'},
          'files': [],
        }, collection),
        throwsFormatException,
      );
    },
  );
  test(
    'Jamendo uses only streaming URLs, irrespective of download permission',
    () async {
      final client = OnlineMusicClient(
        client: MockClient((r) async {
          expect(r.url.queryParameters['artist_name'], 'A Singer');
          expect(r.url.queryParameters['offset'], '24');
          expect(r.url.queryParameters['tags'], 'rock');
          return http.Response(
            jsonEncode({
              'headers': {'status': 'success'},
              'results': [
                {
                  'id': '123',
                  'name': 'Music',
                  'artist_name': 'A Singer',
                  'audio': 'https://audio.example.test/stream',
                  'audiodownload_allowed': false,
                  'audiodownload': '',
                },
                {'id': '124', 'audio': 'javascript:alert(1)'},
              ],
            }),
            200,
          );
        }),
      );
      final page = await client.search(
        source: 'Jamendo',
        text: 'A Singer',
        field: 'Cantor / artista',
        genre: 'rock',
        page: 2,
        clientID: 'test-app',
      );
      expect(page.items.single.remoteID, '123');
      expect(page.items.single.toJson().containsKey('audio'), false);
      expect(
        () => client.search(
          source: 'Jamendo',
          text: 'A',
          field: 'Compositor',
          genre: '',
          page: 1,
          clientID: 'test-app',
        ),
        throwsFormatException,
      );
      expect(
        () => client.search(
          source: 'Jamendo',
          text: 'A',
          field: 'Tudo',
          genre: '',
          page: 1,
          clientID: '',
        ),
        throwsFormatException,
      );
      client.close();
    },
  );
  test(
    'playlists persist mixed sources, deduplicate and support organizing without changing radios',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorites': ['radio-one'],
      });
      final prefs = await SharedPreferences.getInstance();
      final store = OnlineMusicStore(prefs);
      final a = store.create('  Workout  ')!, b = store.create('Study')!;
      store.add(track, a);
      store.add(jamTrack, a);
      store.add(track, a);
      store.add(collection, a);
      expect(store.playlists.first.tracks.length, 2);
      store.moveTrack(jamTrack, a, -1);
      store.movePlaylist(b, -1);
      store.rename(a, 'My mix');
      await Future<void>.delayed(Duration.zero);
      final restored = OnlineMusicStore(prefs);
      expect(restored.playlists.first.id, b);
      expect(restored.playlists.last.name, 'My mix');
      expect(restored.playlists.last.tracks.first.source, 'Jamendo');
      expect(prefs.getStringList('favorites'), ['radio-one']);
      expect(
        prefs.getString('onlinePlaylists'),
        isNot(contains('https://audio')),
      );
      restored.remove(track, a);
      expect(restored.playlists.last.tracks.length, 1);
      restored.delete(b);
      expect(restored.playlists.single.id, a);
      store.dispose();
      restored.dispose();
    },
  );
  test(
    'play resolves source at playback time and queue supports next, previous and ends without wrapping',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = OnlineMusicClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              ...metadata(),
              'files': [
                ...metadata()['files'],
                {'name': 'Second.mp3'},
              ],
            }),
            200,
          ),
        ),
      );
      final store = OnlineMusicStore(prefs, client: client),
          radio = FakeRadio();
      const second = OnlineMusicItem(
        source: 'Internet Archive',
        remoteID: 'test-album',
        title: 'Again',
        file: 'Second.mp3',
        artist: 'Another',
      );
      await store.play(track, [track, second], radio);
      expect(Uri.parse(radio.played.single).pathSegments.last, 'One & two.mp3');
      await radio.onMediaStep!(1);
      expect(radio.played.length, 2);
      await radio.onMediaStep!(1);
      expect(radio.played.length, 2);
      await radio.onMediaStep!(-1);
      expect(radio.played.length, 3);
      store.dispose();
      radio.dispose();
    },
  );
  test(
    'late stream resolution cannot take over playback after user changes source',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final pending = Completer<http.Response>();
      final store = OnlineMusicStore(
            prefs,
            client: OnlineMusicClient(
              client: MockClient((_) => pending.future),
            ),
          ),
          radio = FakeRadio();
      final playing = store.play(track, [track], radio);
      radio.playbackRevision++;
      pending.complete(http.Response(jsonEncode(metadata()), 200));
      await playing;
      expect(radio.played, isEmpty);
      expect(store.resolving, false);
      store.dispose();
      radio.dispose();
    },
  );
  test('stale search responses do not overwrite a new source', () async {
    final first = Completer<http.Response>();
    int calls = 0;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnlineMusicStore(
      prefs,
      client: OnlineMusicClient(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return first.future;
          }
          return http.Response(
            jsonEncode({
              'response': {'numFound': 0, 'docs': []},
            }),
            200,
          );
        }),
      ),
    );
    final old = store.search(
      source: 'Internet Archive',
      text: 'old',
      field: 'Tudo',
      genre: '',
    );
    await Future<void>.delayed(Duration.zero);
    await store.search(
      source: 'Internet Archive',
      text: 'new',
      field: 'Tudo',
      genre: '',
    );
    first.complete(
      http.Response(
        jsonEncode({
          'response': {
            'numFound': 1,
            'docs': [
              {'identifier': 'old', 'title': 'Old'},
            ],
          },
        }),
        200,
      ),
    );
    await old;
    expect(store.results, isEmpty);
    store.dispose();
  });
}
