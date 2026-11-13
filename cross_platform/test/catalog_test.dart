import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitra_radio/core/catalog.dart';

void main() {
  Map<String, dynamic> station(
    String id,
    String name, {
    String country = 'Brazil',
  }) => {
    'stationuuid': id,
    'name': name,
    'url': 'https://stream.example.test/$id',
    'url_resolved': '',
    'country': country,
    'state': '',
    'tags': 'pop,rock',
  };
  test(
    'worldwide search omits empty country filter and keeps UTF-8 names',
    () async {
      final client = CatalogClient(
        client: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('countrycode'), false);
          expect(request.url.queryParameters['name'], 'Antena 1');
          return http.Response.bytes(
            utf8.encode(jsonEncode([station('a', 'Rádio Antena 1 São Paulo')])),
            200,
          );
        }),
      );
      final result = await client.search('Antena 1', []);
      expect(result.stations.single.name, 'Rádio Antena 1 São Paulo');
      expect(result.hasMore, false);
      client.close();
    },
  );
  test(
    'selected countries are merged and paging uses per-country offset',
    () async {
      final calls = <String>[];
      final client = CatalogClient(
        client: MockClient((request) async {
          final code = request.url.queryParameters['countrycode']!;
          calls.add(code);
          expect(request.url.queryParameters['offset'], '40');
          return http.Response(
            jsonEncode([
              station('$code-1', '$code A'),
              station('$code-2', '$code B'),
            ]),
            200,
          );
        }),
      );
      final result = await client.search('', ['BR', 'US'], offset: 40);
      expect(result.stations.map((s) => s.name), [
        'BR A',
        'US A',
        'BR B',
        'US B',
      ]);
      expect(calls.toSet(), {'BR', 'US'});
      client.close();
    },
  );
  test('directory outage retries another official mirror', () async {
    var count = 0;
    final client = CatalogClient(
      client: MockClient((request) async {
        count++;
        if (request.url.host == CatalogClient.mirrors.first) {
          return http.Response('unavailable', 503);
        }
        return http.Response(jsonEncode([station('a', 'Antena 1')]), 200);
      }),
    );
    expect(
      (await client.search('Antena 1', ['BR'])).stations.single.name,
      'Antena 1',
    );
    expect(count, 2);
    client.close();
  });
  test(
    'compact station name retries with separation and invalid URLs are rejected',
    () async {
      final client = CatalogClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.queryParameters['name'] == 'Antena1'
                  ? []
                  : [
                      station('a', 'Antena 1'),
                      {
                        ...station('bad', 'Bad'),
                        'url': 'https://user:password@example.test/audio',
                      },
                    ],
            ),
            200,
          ),
        ),
      );
      final result = await client.search('Antena1', ['BR']);
      expect(result.stations.length, 1);
      expect(result.stations.single.name, 'Antena 1');
      client.close();
    },
  );
}
