import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitra_radio/core/podcasts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const show = PodcastShow(
    title: 'Example',
    feed: 'https://feed.example.test/rss',
  );
  final rss =
      '''<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Science &amp; music</title><language>en-US</language><itunes:author>Example author</itunes:author><item><guid>ep-1</guid><title>First episode</title><description><![CDATA[<p>Safe description</p>]]></description><enclosure url="https://audio.example.test/1.mp3" type="audio/mpeg"/><itunes:duration>01:02:03</itunes:duration></item><item><guid>ep-1</guid><title>Duplicate</title><enclosure url="https://audio.example.test/duplicate.mp3" type="audio/mpeg"/></item></channel></rss>''';
  test(
    'RSS retains feed identity, decodes text and deduplicates episode GUID',
    () {
      final feed = PodcastClient.parse(utf8.encode(rss), show);
      expect(feed.show.title, 'Science & music');
      expect(feed.show.feed, show.feed);
      expect(feed.language, 'en-US');
      expect(feed.episodes.length, 1);
      expect(feed.episodes.single.duration, 3723);
      expect(feed.episodes.single.summary, 'Safe description');
      expect(
        PodcastClient.parse(
          utf8.encode(rss.replaceAll('1.mp3', 'new.mp3')),
          show,
        ).episodes.single.id,
        feed.episodes.single.id,
      );
    },
  );
  test(
    'Atom audio enclosure works and executable/credential URLs are rejected',
    () {
      const atom =
          '<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><id>one</id><title>Episode</title><link rel="enclosure" href="https://audio.example.test/a.mp3" type="audio/mpeg"/></entry></feed>';
      expect(
        PodcastClient.parse(utf8.encode(atom), show).episodes.single.title,
        'Episode',
      );
      expect(webURL('javascript:alert(1)'), null);
      expect(webURL('https://user:password@example.test/rss'), null);
      expect(
        () => PodcastClient.parse(
          utf8.encode(
            rss
                .replaceAll(
                  'https://audio.example.test/1.mp3',
                  'file:///private',
                )
                .replaceAll(
                  'https://audio.example.test/duplicate.mp3',
                  'file:///secret',
                ),
          ),
          show,
        ),
        throwsFormatException,
      );
    },
  );
  test('XML entity declarations, including UTF-16, are rejected', () {
    final unsafe = '<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///secret">]>$rss';
    expect(
      () => PodcastClient.parse(utf8.encode(unsafe), show),
      throwsFormatException,
    );
    final utf16 = [
      255,
      254,
      ...unsafe.codeUnits.expand((c) => [c & 255, c >> 8]),
    ];
    expect(() => PodcastClient.parse(utf16, show), throwsFormatException);
  });
  test('recent episodes migrate the saved last episode without mixing radios', () async {
    final episode = PodcastClient.parse(utf8.encode(rss), show).episodes.first;
    SharedPreferences.setMockInitialValues({
      'podcastLastShow': jsonEncode(show.toJson()),
      'podcastLastEpisode': jsonEncode(episode.toJson()),
      'recent': '["radio-original"]',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = PodcastStore(prefs);
    expect(store.recents.single.episode.id, episode.id);
    expect(store.recents.single.show.feed, show.feed);
    expect(prefs.getString('recent'), '["radio-original"]');
    store.dispose();
  });
  test('favorites remain separate from radio library', () async {
    SharedPreferences.setMockInitialValues({'stations': '[]'});
    final prefs = await SharedPreferences.getInstance();
    final store = PodcastStore(prefs);
    store.favorite(show);
    await Future<void>.delayed(Duration.zero);
    final reopened = PodcastStore(prefs);
    expect(reopened.favorites.single.feed, show.feed);
    expect(prefs.getString('stations'), '[]');
    store.dispose();
    reopened.dispose();
  });
}
