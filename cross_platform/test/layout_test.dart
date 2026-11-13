import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitra_radio/main.dart';
import 'package:vitra_radio/views/library_views.dart';
import 'package:vitra_radio/core/radio_store.dart';
import 'package:vitra_radio/core/models.dart';
import 'package:vitra_radio/core/preferences.dart';
import 'package:vitra_radio/core/music.dart';
import 'package:vitra_radio/core/podcasts.dart';
import 'package:vitra_radio/core/online_music.dart';
import 'package:vitra_radio/views/online_music_view.dart';

class LayoutRadio extends ChangeNotifier implements RadioStore {
  @override
  final SharedPreferences prefs;
  LayoutRadio(this.prefs);
  @override
  String skin = 'Vitra', page = 'Início', section = 'Favoritas';
  @override
  RadioStation? selected = const RadioStation(
    id: 'test',
    name: 'Uma rádio com nome bastante longo para conferir os controles',
    url: 'https://audio.example.test/radio',
  );
  @override
  bool playing = false,
      busy = false,
      searching = false,
      isLive = true,
      hasMore = false;
  @override
  double volume = .6;
  @override
  String? error, mediaTitle, mediaArtist, mediaID;
  @override
  Duration position = Duration.zero, duration = Duration.zero;
  @override
  List<String> countryCodes = ['BR'];
  @override
  List<RadioStation> library = [], results = [], visible = [];
  @override
  Set<String> favorites = {};
  @override
  List<RadioSchedule> schedules = [];
  @override
  bool get hasMedia => true;
  @override
  String? mood;
  @override
  List<RadioStation> get catalogVisible => results;
  @override
  void evaluateSchedule() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(600, 1024),
    const Size(1024, 600),
  ]) {
    for (final playlists in [false, true]) {
      testWidgets(
        'online music fits $size with large text, playlists=$playlists',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final store = OnlineMusicStore(
            prefs,
            client: OnlineMusicClient(
              client: MockClient(
                (_) async =>
                    http.Response('{"response":{"docs":[],"numFound":0}}', 200),
              ),
            ),
          );
          store.create('Uma playlist com nome longo para testar a organização');
          final radio = LayoutRadio(prefs);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OnlineMusicPage(
                  store: store,
                  radio: radio,
                  playlistsOnly: playlists,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (!playlists) {
            await tester.tap(find.text('Internet Archive').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Jamendo').last);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text('Conexão Jamendo'),
              100,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.drag(find.byType(ListView), const Offset(0, -500));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Conexão Jamendo'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Conexão Jamendo'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Client ID'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          radio.dispose();
        },
      );
    }
  }

  for (final size in [const Size(320, 640), const Size(1024, 600)]) {
    for (final page in [
      'Podcasts',
      'Minhas Músicas',
      'Ajustes',
      'Todas as rádios',
    ]) {
      testWidgets('$page fits ${size.width}x${size.height} with large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        SharedPreferences.setMockInitialValues({
          'catalogCountriesConfigured': true,
          'updatesCheckOnLaunch': false,
          'updatesCheckDaily': false,
          'interfaceLanguage': 'pt-BR',
        });
        PackageInfo.setMockInitialValues(
          appName: 'Vitra',
          packageName: 'com.vitra.vitra_radio',
          version: '0.1.10',
          buildNumber: '10',
          buildSignature: '',
        );
        final prefs = await SharedPreferences.getInstance(),
            settings = (await tester.runAsync(
              () async =>
                  AppPreferences.load(await SharedPreferences.getInstance()),
            ))!;
        final radio = LayoutRadio(prefs)..page = page;
        final podcasts = PodcastStore(
          prefs,
          client: PodcastClient(
            client: MockClient(
              (_) async => http.Response('{"results":[]}', 200),
            ),
          ),
        );
        podcasts.results = [
          const PodcastShow(
            title: 'Um programa com um nome longo para conferir o layout',
            feed: 'https://feed.example.test/rss',
          ),
        ];
        podcasts.lastCountry = settings.codes.firstOrNull ?? 'US';
        await tester.pumpWidget(
          VitraApp(
            store: radio,
            settings: settings,
            podcasts: podcasts,
            music: MusicStore(prefs),
          ),
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(600, 1024),
    const Size(1024, 600),
  ]) {
    for (final local in [true, false]) {
      testWidgets(
        'music form fits ${size.width}x${size.height}, local=$local',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          SharedPreferences.setMockInitialValues({});
          final store = MusicStore(await SharedPreferences.getInstance());
          appLanguage = 'pt-BR';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MusicForm(
                  store: store,
                  profile: local
                      ? null
                      : const MusicProfile(
                          id: 'test',
                          name: 'Library',
                          address: 'https://music.example.test',
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          store.dispose();
        },
      );
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(600, 1024),
    const Size(1024, 600),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'player and navigation fit ${size.width}x${size.height} at text scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          SharedPreferences.setMockInitialValues({
            'catalogCountriesConfigured': true,
            'updatesCheckOnLaunch': false,
            'updatesCheckDaily': false,
          });
          PackageInfo.setMockInitialValues(
            appName: 'Vitra',
            packageName: 'com.vitra.vitra_radio',
            version: '0.1.10',
            buildNumber: '10',
            buildSignature: '',
          );
          final prefs = await SharedPreferences.getInstance();
          final settings = (await tester.runAsync(
            () => AppPreferences.load(prefs),
          ))!;
          await tester.pumpWidget(
            VitraApp(
              store: LayoutRadio(prefs),
              settings: settings,
              podcasts: PodcastStore(prefs),
              music: MusicStore(prefs),
            ),
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.skip_previous), findsOneWidget);
          expect(find.byIcon(Icons.skip_next), findsOneWidget);
          final previous = tester.getRect(find.byIcon(Icons.skip_previous)),
              next = tester.getRect(find.byIcon(Icons.skip_next));
          expect(previous.right, lessThan(next.left));
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
        },
      );
    }
  }
}
