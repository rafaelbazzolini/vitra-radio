import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class CatalogPage {
  final List<RadioStation> stations;
  final bool hasMore;
  const CatalogPage(this.stations, this.hasMore);
}

class CatalogClient {
  final http.Client client;
  CatalogClient({http.Client? client}) : client = client ?? http.Client();
  static const mirrors = [
    'all.api.radio-browser.info',
    'de1.api.radio-browser.info',
    'fr1.api.radio-browser.info',
  ];
  static const pageSize = 40;
  static Uri query(String host, String text, String country, int offset) =>
      Uri.https(host, '/json/stations/search', {
        if (text.trim().isNotEmpty) 'name': text.trim(),
        if (country.isNotEmpty) 'countrycode': country,
        'limit': '$pageSize',
        'offset': '$offset',
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
      });
  Future<CatalogPage> _country(String text, String code, int offset) async {
    for (final host in mirrors) {
      try {
        final response = await client
            .get(
              query(host, text, code, offset),
              headers: {
                'User-Agent': 'VitraRadio/0.1.10',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200 || response.bodyBytes.length > 8000000) {
          throw const FormatException();
        }
        final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List;
        final stations = <RadioStation>[];
        for (final raw in rows.whereType<Map>()) {
          final name = (raw['name'] as String? ?? '').trim(),
              id = raw['stationuuid'] as String? ?? '';
          final resolved = (raw['url_resolved'] as String? ?? '').trim();
          final station = RadioStation(
            id: 'rb-$id',
            name: name,
            url: resolved.isNotEmpty
                ? resolved
                : (raw['url'] as String? ?? '').trim(),
            genre: (raw['tags'] as String? ?? '')
                .split(',')
                .take(2)
                .join(' · '),
            location: [
              raw['state'],
              raw['country'],
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          );
          if (id.isNotEmpty && name.isNotEmpty && station.valid) {
            stations.add(station);
          }
        }
        return CatalogPage(stations, rows.length == pageSize);
      } catch (_) {
        if (host == mirrors.last) {
          rethrow;
        }
      }
    }
    throw const FormatException();
  }

  Future<CatalogPage> search(
    String text,
    List<String> codes, {
    int offset = 0,
  }) async {
    final chosen = codes.isEmpty ? [''] : codes.toSet().take(8).toList();
    final pages = <CatalogPage>[];
    for (var i = 0; i < chosen.length; i += 4) {
      pages.addAll(
        await Future.wait(
          chosen.skip(i).take(4).map((c) => _country(text, c, offset)),
        ),
      );
    }
    final mixed = <RadioStation>[], seen = <String>{};
    for (var row = 0; pages.any((p) => p.stations.length > row); row++) {
      for (final page in pages) {
        if (page.stations.length > row && seen.add(page.stations[row].id)) {
          mixed.add(page.stations[row]);
        }
      }
    }
    if (mixed.isEmpty &&
        offset == 0 &&
        RegExp(r'[a-zA-Z][0-9]').hasMatch(text)) {
      return search(
        text.replaceAllMapped(
          RegExp(r'([a-zA-Z])([0-9])'),
          (m) => '${m[1]} ${m[2]}',
        ),
        codes,
      );
    }
    return CatalogPage(mixed, pages.any((p) => p.hasMore));
  }

  void close() => client.close();
}
