import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:vitra_radio/core/music.dart';

void main() {
  test(
    'music profiles never persist credentials and reject unsafe server URLs',
    () {
      const profile = MusicProfile(
        id: 'one',
        name: 'Library',
        address: 'https://music.example.test/proxy/rest',
        username: 'tester',
      );
      expect(profile.base.toString(), 'https://music.example.test/proxy/');
      expect(profile.toJson().containsKey('password'), false);
      expect(profile.toJson().containsKey('token'), false);
      expect(
        () => const MusicProfile(
          id: 'bad',
          name: 'Bad',
          address: 'https://user:secret@example.test',
        ).base,
        throwsFormatException,
      );
      expect(
        () => const MusicProfile(
          id: 'bad',
          name: 'Bad',
          address: 'http://example.test',
          network: 'internet',
        ).base,
        throwsFormatException,
      );
    },
  );
  test(
    'Subsonic uses salted authentication, proxy paths and album API',
    () async {
      const profile = MusicProfile(
        id: 'one',
        name: 'Library',
        address: 'https://music.example.test/proxy',
        username: 'tester+local',
      );
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path.startsWith('/proxy/rest/'), true);
        final form = Uri.splitQueryString(request.body);
        expect(form['u'], 'tester+local');
        expect(form.containsKey('p'), false);
        expect(
          form['t'],
          md5.convert(utf8.encode('secret${form['s']}')).toString(),
        );
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'albumList2': {
                'album': [
                  {'id': 'a1', 'name': 'Album', 'artist': 'Artist'},
                ],
              },
            },
          }),
          200,
        );
      });
      final client = MusicClient(profile, {'password': 'secret'}, client: mock);
      expect((await client.authenticate(''))['password'], 'secret');
      expect((await client.albums(0)).items.single.title, 'Album');
      final url = Uri.parse(
        client.playback(const MusicItem('t1', 'Track', 'Artist')),
      );
      expect(url.path, '/proxy/rest/stream.view');
      expect(url.queryParameters['id'], 't1');
      expect(url.queryParameters.containsKey('p'), false);
      client.close();
    },
  );
  test(
    'Jellyfin session is validated and credentials are not redirected',
    () async {
      const profile = MusicProfile(
        id: 'one',
        name: 'Library',
        kind: 'jellyfin',
        address: 'https://music.example.test/jellyfin',
        username: 'tester',
      );
      final client = MusicClient(
        profile,
        {},
        client: MockClient((request) async {
          if (request.url.path.endsWith('AuthenticateByName')) {
            expect(jsonDecode(request.body)['Username'], 'tester');
            return http.Response(
              jsonEncode({
                'AccessToken': 'fixture-token',
                'User': {'Id': 'u1'},
              }),
              200,
            );
          }
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.example.test/steal'},
          );
        }),
      );
      expect((await client.authenticate('secret'))['token'], 'fixture-token');
      expect(() => client.json('Albums'), throwsFormatException);
      client.close();
    },
  );
}
