import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/models.dart';
import 'core/radio_store.dart';
import 'core/updates.dart';
import 'core/preferences.dart';
import 'core/podcasts.dart';
import 'core/radio_moods.dart';
import 'core/music.dart';
import 'views/library_views.dart';
import 'views/position_slider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = await AppPreferences.load(prefs);
  final store = RadioStore(prefs)..countryCodes = settings.codes;
  runApp(
    VitraApp(
      store: store,
      settings: settings,
      podcasts: PodcastStore(prefs),
      music: MusicStore(prefs),
    ),
  );
}

class VitraApp extends StatefulWidget {
  final RadioStore store;
  final AppPreferences settings;
  final PodcastStore podcasts;
  final MusicStore music;
  const VitraApp({
    super.key,
    required this.store,
    required this.settings,
    required this.podcasts,
    required this.music,
  });
  @override
  State<VitraApp> createState() => _VitraAppState();
}

class _VitraAppState extends State<VitraApp> with WidgetsBindingObserver {
  final updates = UpdateService();
  Timer? timer;
  final search = TextEditingController();
  RadioStore get radio => widget.store;
  bool _setupScheduled = false;
  AppPreferences get settings => widget.settings;
  static const pages = [
    'Início',
    'Todas as rádios',
    'Podcasts',
    'Minhas Músicas',
    'Ajustes',
  ];
  static const icons = [
    Icons.home_rounded,
    Icons.radio,
    Icons.podcasts,
    Icons.library_music_outlined,
    Icons.settings_outlined,
  ];
  static const skins = ['Vitra', 'Receiver', 'Studio', 'Heritage', 'Signal 90'];
  Color get accent => settings.accentHex != null
      ? Color(int.parse(settings.accentHex!, radix: 16) | 0xff000000)
      : switch (radio.skin) {
          'Studio' => const Color(0xff245a8a),
          'Heritage' => const Color(0xfff4c779),
          'Signal 90' => const Color(0xff72e6cd),
          _ => const Color(0xffc3f47a),
        };
  Color get background => switch (radio.skin) {
    'Studio' => const Color(0xffaebbc5),
    'Heritage' => const Color(0xff493122),
    'Signal 90' => const Color(0xff202630),
    'Receiver' => const Color(0xff141d16),
    _ => const Color(0xff101411),
  };
  Color get panel => switch (radio.skin) {
    'Studio' => const Color(0xffcdd6de),
    'Heritage' => const Color(0xff241f19),
    'Signal 90' => const Color(0xff101a20),
    'Receiver' => const Color(0xff233026),
    _ => const Color(0xff1c231e),
  };
  Color get ink => switch (radio.skin) {
    'Studio' => const Color(0xff202d3b),
    'Heritage' => const Color(0xfff9e9c8),
    'Signal 90' => const Color(0xffd4f8ee),
    _ => const Color(0xfff1f4ec),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(updates.start());
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => updates.checkIfDue(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      radio.evaluateSchedule();
      unawaited(updates.checkIfDue());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    search.dispose();
    updates.dispose();
    widget.podcasts.dispose();
    widget.music.dispose();
    radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      radio,
      updates,
      settings,
      widget.podcasts,
      widget.music,
    ]),
    builder: (context, _) {
      final light = radio.skin == 'Studio';
      return MaterialApp(
        title: 'Vitra Radio',
        locale: Locale(
          settings.language == 'en' ? 'en' : 'pt',
          settings.language == 'en' ? 'US' : 'BR',
        ),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: light ? Brightness.light : Brightness.dark,
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: accent,
                brightness: light ? Brightness.light : Brightness.dark,
              ).copyWith(
                primary: accent,
                onPrimary: accent.computeLuminance() > .4
                    ? const Color(0xff101411)
                    : Colors.white,
                secondary: accent,
                surface: panel,
                onSurface: ink,
              ),
          cardTheme: CardThemeData(
            color: panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                radio.skin == 'Signal 90' ? 7 : 14,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ink.withValues(alpha: .15)),
            ),
          ),
          scaffoldBackgroundColor: background,
          fontFamily: radio.skin == 'Signal 90' ? 'monospace' : null,
        ),
        home: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (settings.needsSetup && !_setupScheduled) {
              _setupScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  countryDialog(
                    context,
                    settings,
                    countriesChanged,
                    onboarding: true,
                  );
                }
              });
            }
            final content = Padding(
              padding: EdgeInsets.all(wide ? 30 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('SUA FREQUÊNCIA'),
                              style: TextStyle(
                                color: accent,
                                letterSpacing: 3,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(
                                radio.page == 'Início'
                                    ? 'O seu dia tem trilha.'
                                    : tr(radio.page),
                              ),
                              style: TextStyle(
                                fontSize: wide ? 30 : 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: tr('Escolher tema'),
                        initialValue: radio.skin,
                        onSelected: radio.chooseSkin,
                        itemBuilder: (_) => skins
                            .map(
                              (s) => CheckedPopupMenuItem(
                                value: s,
                                checked: s == radio.skin,
                                child: Text(
                                  s == 'Vitra' ? tr('Vitra Padrão') : s,
                                ),
                              ),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.palette_outlined,
                                size: 19,
                                color: accent,
                              ),
                              if (wide) Text(tr(' Tema')),
                              const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (updates.availableVersion != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.system_update),
                          title: Text(
                            tr(
                              '${tr('Nova versão disponível')}: ${updates.availableVersion}',
                            ),
                          ),
                          subtitle: Text(
                            tr(
                              'Uma nova versão está pronta. Você decide quando atualizar.',
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: updates.openRelease,
                            child: Text(tr('Atualizar')),
                          ),
                        ),
                      ),
                    ),
                  if (radio.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        tr(radio.error!),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  Expanded(
                    child: switch (radio.page) {
                      'Início' => home(context, wide),
                      'Todas as rádios' => catalog(context, wide),
                      'Podcasts' => PodcastsPage(
                        store: widget.podcasts,
                        radio: radio,
                        settings: settings,
                      ),
                      'Minhas Músicas' => MusicPage(
                        store: widget.music,
                        radio: radio,
                      ),
                      _ => settingsPage(context),
                    },
                  ),
                ],
              ),
            );
            return Scaffold(
              appBar: wide
                  ? null
                  : AppBar(
                      title: Text(tr('vitra radio')),
                      backgroundColor: background,
                    ),
              drawer: wide
                  ? null
                  : Drawer(child: navigation(context, drawer: true)),
              body: SafeArea(
                child: Column(
                  children: [
                    if (wide && radio.skin != 'Vitra')
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < pages.length; i++)
                              ChoiceChip(
                                avatar: Icon(icons[i], size: 16),
                                label: Text(tr(pages[i])),
                                selected: radio.page == pages[i],
                                onSelected: (_) => radio.navigate(pages[i]),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (wide && radio.skin == 'Vitra')
                            SizedBox(width: 212, child: navigation(context)),
                          Expanded(child: content),
                        ],
                      ),
                    ),
                    if (MediaQuery.viewInsetsOf(context).bottom == 0)
                      transport(context, wide),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
  void countriesChanged() {
    radio.countryCodes = List.of(settings.codes);
    if (radio.page == 'Todas as rádios') {
      unawaited(radio.search(search.text));
    }
  }

  Widget navigation(BuildContext context, {bool drawer = false}) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 30, 12, 18),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 28),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.graphic_eq,
                color: Colors.black,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                tr('vitra'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ],
        ),
      ),
      for (var i = 0; i < pages.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            selected: radio.page == pages[i],
            selectedColor: accent,
            selectedTileColor: accent.withValues(alpha: .10),
            leading: Icon(icons[i], size: 20),
            title: Text(tr(pages[i]), style: const TextStyle(fontSize: 13)),
            onTap: () {
              radio.navigate(pages[i]);
              if (drawer) {
                Navigator.pop(context);
              }
            },
          ),
        ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          tr('Sua biblioteca fica neste dispositivo.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
  Widget receiver(BuildContext context) {
    final name = radio.selected?.name ?? tr('Escolha sua rádio');
    final frequency = RegExp(
      r'(8[8-9]|9[0-9]|10[0-8])[,\.][0-9]',
    ).firstMatch(name)?.group(0)?.replaceAll('.', ',');
    final number = double.tryParse(frequency?.replaceAll(',', '.') ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                radio.skin == 'Heritage'
                    ? 'VITRA · HIGH FIDELITY'
                    : radio.skin == 'Signal 90'
                    ? 'SIGNAL / DIGITAL TUNER'
                    : 'STUDIO / RECEIVER',
              ),
              style: TextStyle(color: accent, letterSpacing: 2, fontSize: 10),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(
                  radio.skin == 'Signal 90' ? 3 : 14,
                ),
                border: Border.all(color: accent.withValues(alpha: .25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(frequency == null ? 'WEB RADIO' : '$frequency FM'),
                    style: TextStyle(
                      fontSize: 32,
                      color: accent,
                      fontFamily: radio.skin == 'Heritage'
                          ? 'serif'
                          : 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(radio.selected?.genre ?? tr('Sintonize seu momento')),
                  ),
                  if (number != null) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 20,
                      child: Stack(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              21,
                              (i) => Container(
                                width: 1,
                                height: i % 5 == 0 ? 14 : 6,
                                color: accent.withValues(alpha: .4),
                              ),
                            ),
                          ),
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment(
                              ((number - 88) / 20 * 2 - 1).clamp(-1, 1),
                              0,
                            ),
                            child: Container(
                              width: 3,
                              height: 20,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: radio.selected == null
                    ? () => radio.navigate('Todas as rádios')
                    : radio.toggle,
                icon: Icon(radio.playing ? Icons.pause : Icons.play_arrow),
                label: Text(
                  tr(
                    radio.selected == null
                        ? 'Encontrar rádios'
                        : radio.playing
                        ? 'Pausar rádio'
                        : 'Ouvir rádio',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget home(BuildContext context, bool wide) => ListView(
    children: [
      if (radio.skin != 'Vitra')
        receiver(context)
      else
        Container(
          padding: EdgeInsets.all(wide ? 30 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: .2)),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: .15),
                accent.withValues(alpha: .025),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(radio.playing ? '● NO AR AGORA' : 'SINTONIZE SEU MOMENTO'),
                style: TextStyle(color: accent, fontSize: 10, letterSpacing: 2),
              ),
              const SizedBox(height: 18),
              Text(
                tr(radio.selected?.name ?? 'Uma boa trilha\nmuda tudo.'),
                style: TextStyle(
                  fontSize: wide ? 38 : 28,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr(
                  radio.selected?.genre ??
                      'Busque uma rádio ou adicione seu próprio stream.\nSem conta, sem uma seleção pré-carregada.',
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: radio.selected == null
                    ? () {
                        radio.navigate('Todas as rádios');
                        unawaited(radio.search(''));
                      }
                    : radio.toggle,
                icon: Icon(radio.playing ? Icons.pause : Icons.play_arrow),
                label: Text(
                  tr(
                    radio.selected == null
                        ? 'Encontrar rádios'
                        : radio.playing
                        ? 'Pausar rádio'
                        : 'Ouvir rádio',
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final section in [
            'Favoritas',
            'Recentes',
            'Podcasts favoritos',
            'Podcasts recentes',
          ])
            ChoiceChip(
              label: Text(tr(section)),
              selected: radio.section == section,
              onSelected: (_) => radio.chooseSection(section),
            ),
        ],
      ),
      const SizedBox(height: 18),
      if (radio.section.startsWith('Podcasts'))
        ...homePodcasts()
      else if (radio.visible.isEmpty)
        empty(
          radio.section == 'Favoritas'
              ? 'Suas favoritas moram aqui.'
              : 'Seu histórico começa quando você ouvir uma rádio.',
        ),
      if (!radio.section.startsWith('Podcasts'))
        ...radio.visible.map(stationTile),
    ],
  );
  List<Widget> homePodcasts() {
    final store = widget.podcasts;
    if (radio.section == 'Podcasts favoritos') {
      if (store.favorites.isEmpty) {
        return [empty('Favorite podcasts para encontrá-los aqui.')];
      }
      return store.favorites
          .map(
            (show) => Card(
              child: ListTile(
                leading: const Icon(Icons.podcasts),
                title: Text(show.title),
                subtitle: Text(show.author),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  radio.navigate('Podcasts');
                  unawaited(store.open(show));
                },
              ),
            ),
          )
          .toList();
    }
    if (store.recents.isEmpty) {
      return [empty('Os episódios que você ouvir aparecerão aqui.')];
    }
    return store.recents
        .map(
          (item) => Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(item.episode.title),
              subtitle: Text(item.show.title),
              onTap: () => store.play(item.show, item.episode, radio),
            ),
          ),
        )
        .toList();
  }

  Widget stationTile(RadioStation station) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.radio, color: accent),
      ),
      title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        tr(
          [
            station.genre,
            station.location,
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => radio.play(station),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: tr('Vincular a categorias'),
            icon: const Icon(Icons.sell_outlined),
            onSelected: (mood) => radio.toggleMood(mood, station),
            itemBuilder: (_) => radioMoods
                .map(
                  (mood) => CheckedPopupMenuItem(
                    value: mood,
                    checked: radio.hasMood(mood, station),
                    child: Text(tr(mood)),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: tr('Favoritar'),
            onPressed: () => radio.favorite(station),
            icon: Icon(
              radio.isFavorite(station)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: accent,
            ),
          ),
        ],
      ),
    ),
  );
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(child: Text(text, textAlign: TextAlign.center)),
  );
  Widget catalog(BuildContext context, bool wide) {
    final stations = radio.catalogVisible;
    final more = radio.mood == null && radio.hasMore;
    return ListView.builder(
      itemCount: 1 + (stations.isEmpty ? 1 : stations.length) + (more ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tr('Nome da rádio'),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: radio.search,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: radio.searching
                        ? null
                        : () => radio.search(search.text),
                    child: Text(tr('Buscar')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        countryDialog(context, settings, countriesChanged),
                    icon: const Icon(Icons.public),
                    label: Text(
                      settings.countrySummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => addStream(context),
                    icon: const Icon(Icons.add_link),
                    label: Text(tr('Adicionar rádio por URL')),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(tr('Todas')),
                    selected: radio.mood == null,
                    onSelected: (_) => radio.chooseMood(null),
                  ),
                  for (final mood in radioMoods)
                    ChoiceChip(
                      label: Text(tr(mood)),
                      selected: radio.mood == mood,
                      onSelected: (_) => radio.chooseMood(mood),
                    ),
                ],
              ),
              if (radio.mood != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    tr(
                      'Seleção internacional e seus vínculos locais. Use a etiqueta de uma rádio para alterar as categorias.',
                    ),
                  ),
                ),
              if (radio.searching) const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
          );
        }
        if (stations.isEmpty) {
          return empty(
            radio.mood == null && radio.error != null
                ? 'Catálogo indisponível. Confira a conexão e tente novamente.'
                : 'Nenhuma rádio encontrada.',
          );
        }
        if (index <= stations.length) return stationTile(stations[index - 1]);
        return TextButton(
          onPressed: radio.searching
              ? null
              : () => radio.search(search.text, more: true),
          child: Text(tr('Carregar mais rádios')),
        );
      },
    );
  }

  Future<void> addStream(BuildContext context) async {
    final name = TextEditingController(), url = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Adicionar rádio')),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Nome')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  decoration: InputDecoration(
                    labelText: tr('URL direta do stream'),
                    hintText: tr('https://servidor/stream'),
                  ),
                ),
                if (error != null)
                  Text(
                    tr(error!),
                    style: const TextStyle(color: Colors.orange),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancelar')),
            ),
            FilledButton(
              onPressed: () {
                final station = RadioStation(
                  id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  url: url.text.trim(),
                );
                if (station.name.isEmpty || !station.valid) {
                  set(
                    () => error =
                        'Informe nome e uma URL HTTP(S) sem credenciais.',
                  );
                  return;
                }
                radio.favorite(station);
                Navigator.pop(ctx);
              },
              child: Text(tr('Salvar nas favoritas')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    url.dispose();
  }

  Widget themes() => ListView(
    children: [
      Text(
        tr('Uma nova cara para o seu som.'),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 18),
      ...skins.map(
        (s) => Card(
          child: ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(s == 'Vitra' ? tr('Vitra Padrão') : s),
            subtitle: Text(
              tr(
                s == 'Heritage'
                    ? 'Madeira e âmbar'
                    : s == 'Studio'
                    ? 'Alumínio e azul'
                    : s == 'Signal 90'
                    ? 'Digital e luminoso'
                    : 'Escuro e contemporâneo',
              ),
            ),
            trailing: radio.skin == s
                ? Icon(Icons.check_circle, color: accent)
                : null,
            onTap: () => radio.chooseSkin(s),
          ),
        ),
      ),
    ],
  );
  Widget automation(BuildContext context) => ListView(
    children: [
      Text(
        tr('Sua rádio. Na hora certa.'),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          'Horário local do dispositivo. Sobreposições retomam a faixa anterior. Datas específicas têm prioridade. A execução exige que o processo esteja ativo; não acorda o aparelho nem promete execução com o app suspenso.',
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: radio.library.isEmpty ? null : () => scheduleDialog(context),
        icon: const Icon(Icons.add),
        label: Text(tr('Programar rádio')),
      ),
      const SizedBox(height: 18),
      ...radio.schedules.map(
        (r) => Card(
          child: ListTile(
            title: Text(
              tr(
                '${RadioSchedule.time(r.start)} — ${RadioSchedule.time(r.end)} · ${radio.library.where((s) => s.id == r.stationId).firstOrNull?.name ?? 'Rádio removida'}',
              ),
            ),
            subtitle: Text(
              tr(
                r.date == null
                    ? r.days
                          .toList()
                          .map(
                            (d) => [
                              'Seg',
                              'Ter',
                              'Qua',
                              'Qui',
                              'Sex',
                              'Sáb',
                              'Dom',
                            ][d - 1],
                          )
                          .join(' · ')
                    : '${r.date} · uma vez · prioridade',
              ),
            ),
            onTap: () => scheduleDialog(context, existing: r),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: r.enabled,
                  onChanged: (_) {
                    final error = radio.saveSchedule(r.toggled());
                    if (error != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                ),
                IconButton(
                  onPressed: () => radio.removeSchedule(r.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  Future<void> scheduleDialog(
    BuildContext context, {
    RadioSchedule? existing,
  }) async {
    var station = existing?.stationId ?? radio.library.first.id,
        dated = existing?.date != null;
    var date = existing?.date == null
        ? DateTime.now()
        : DateTime.parse(existing!.date!);
    var days = Set<int>.from(existing?.days ?? [1, 2, 3, 4, 5]);
    final from = TextEditingController(
          text: RadioSchedule.time(existing?.start ?? 540),
        ),
        to = TextEditingController(
          text: RadioSchedule.time(existing?.end ?? 600),
        );
    String? error;
    int? minutes(String text) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
      if (m == null) return null;
      final h = int.parse(m[1]!), n = int.parse(m[2]!);
      return h < 24 && n < 60 ? h * 60 + n : null;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Programar rádio')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: station,
                    isExpanded: true,
                    items: radio.library
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => station = v!,
                    decoration: InputDecoration(labelText: tr('Rádio')),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: from,
                          decoration: InputDecoration(
                            labelText: tr('Início · HH:mm'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: to,
                          decoration: InputDecoration(
                            labelText: tr('Término · HH:mm'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(tr('Semanal'))),
                      ButtonSegment(
                        value: true,
                        label: Text(tr('Data específica')),
                      ),
                    ],
                    selected: {dated},
                    onSelectionChanged: (v) => set(() => dated = v.first),
                  ),
                  const SizedBox(height: 16),
                  if (dated)
                    TextButton.icon(
                      onPressed: () async {
                        final next = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (next != null) set(() => date = next);
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(RadioSchedule.civilDate(date)),
                    )
                  else
                    Wrap(
                      spacing: 4,
                      children: List.generate(
                        7,
                        (i) => FilterChip(
                          label: Text(
                            tr(['S', 'T', 'Q', 'Q', 'S', 'S', 'D'][i]),
                          ),
                          selected: days.contains(i + 1),
                          onSelected: (v) => set(() {
                            if (v) {
                              days.add(i + 1);
                            } else {
                              days.remove(i + 1);
                            }
                          }),
                        ),
                      ),
                    ),
                  if (error != null)
                    Text(
                      tr(error!),
                      style: const TextStyle(color: Colors.orange),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancelar')),
            ),
            FilledButton(
              onPressed: () {
                final a = minutes(from.text), b = minutes(to.text);
                if (a == null || b == null) {
                  set(() => error = 'Use horas válidas no formato HH:mm.');
                  return;
                }
                final rule = RadioSchedule(
                  id:
                      existing?.id ??
                      '${DateTime.now().microsecondsSinceEpoch}',
                  stationId: station,
                  days: days,
                  start: a,
                  end: b,
                  date: dated ? RadioSchedule.civilDate(date) : null,
                );
                final message = radio.saveSchedule(rule);
                if (message != null) {
                  set(() => error = message);
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: Text(tr('Salvar')),
            ),
          ],
        ),
      ),
    );
    from.dispose();
    to.dispose();
  }

  Widget settingsPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              [
                    'Idioma e região',
                    'Temas',
                    'Automação',
                    'Miniplayer',
                    'Atualizações',
                  ]
                  .map(
                    (tab) => Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 12),
                      child: ChoiceChip(
                        label: Text(tr(tab)),
                        selected: settings.settingsTab == tab,
                        onSelected: (_) => settings.selectSettings(tab),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
      Expanded(
        child: switch (settings.settingsTab) {
          'Temas' => ListView(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text(tr('Cor do tema')),
                    onPressed: () => settings.setAccent(null),
                  ),
                  ...[
                    'c3f47a',
                    '72c7f5',
                    '72e6cd',
                    'c7a2ed',
                    'efc47e',
                    'ed9bb6',
                  ].map(
                    (hex) => ChoiceChip(
                      label: Container(
                        width: 24,
                        height: 16,
                        color: Color(int.parse(hex, radix: 16) | 0xff000000),
                      ),
                      selected: settings.accentHex == hex,
                      onSelected: (_) => settings.setAccent(hex),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 600, child: themes()),
            ],
          ),
          'Automação' => automation(context),
          'Miniplayer' => ListView(
            children: [
              Text(
                tr('Miniplayer'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'O player fica na barra inferior. Os controles se ajustam à tela e à orientação do dispositivo.',
                ),
              ),
              SwitchListTile(
                title: Text(tr('Exibir controle de volume')),
                value: radio.prefs.getBool('playerShowVolume') ?? false,
                onChanged: (value) async {
                  await radio.prefs.setBool('playerShowVolume', value);
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          'Atualizações' => updateSettings(context),
          _ => SingleChildScrollView(
            child: CountrySettings(
              settings: settings,
              changed: countriesChanged,
            ),
          ),
        },
      ),
    ],
  );
  Widget updateSettings(BuildContext context) => ListView(
    children: [
      Text(
        tr('Vitra Radio ${updates.currentVersion}'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      Text(
        tr(
          'Escolha quando o Vitra deve buscar novas versões. Quando houver uma atualização, o aviso aparece dentro do app para você decidir quando atualizar.',
        ),
      ),
      SwitchListTile(
        title: Text(tr('Verificar ao abrir o app')),
        value: updates.checkOnLaunch,
        onChanged: updates.initialized ? updates.setCheckOnLaunch : null,
      ),
      SwitchListTile(
        title: Text(tr('Verificar automaticamente uma vez por dia')),
        subtitle: Text(
          tr(
            'Enquanto o app estiver ativo ou ao voltar para ele após 24 horas.',
          ),
        ),
        value: updates.checkDaily,
        onChanged: updates.initialized ? updates.setCheckDaily : null,
      ),
      infoMessage(updates.error),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: updates.checking ? null : updates.check,
            icon: const Icon(Icons.refresh),
            label: Text(
              tr(updates.checking ? 'Buscando…' : 'Buscar atualizações'),
            ),
          ),
          if (updates.availableVersion != null)
            FilledButton(
              onPressed: updates.openRelease,
              child: Text(tr('Atualizar')),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: updates.requestNotificationPermission,
        icon: const Icon(Icons.notifications_outlined),
        label: Text(tr('Ativar notificações de atualização')),
      ),
      const SizedBox(height: 20),
      Text(
        tr(
          'Sua biblioteca fica neste dispositivo. Sem conta e sem telemetria própria.',
        ),
      ),
    ],
  );
  Future<void> skip(int direction) async {
    if (radio.isLive) {
      await radio.skip(direction);
    } else if (radio.mediaID?.startsWith('music-') == true) {
      await widget.music.skip(direction, radio);
    } else {
      await radio.seek(radio.position + Duration(seconds: direction * 15));
    }
  }

  Widget transport(BuildContext context, bool wide) => LayoutBuilder(
    builder: (context, constraints) {
      final roomy = constraints.maxWidth >= 900,
          showVolume = radio.prefs.getBool('playerShowVolume') ?? false;
      final metadata = Row(
        children: [
          Icon(
            radio.isLive ? Icons.graphic_eq : Icons.music_note,
            color: accent,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    radio.mediaTitle ??
                        radio.selected?.name ??
                        tr('Escolha sua rádio'),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  tr(
                    radio.busy
                        ? tr('Conectando…')
                        : radio.mediaArtist ??
                              tr(
                                radio.playing ? 'Ao vivo' : 'Pronto para ouvir',
                              ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          if (radio.selected != null)
            IconButton(
              tooltip: tr('Favoritar'),
              onPressed: () => radio.favorite(radio.selected!),
              icon: Icon(
                radio.favorites.contains(radio.selected!.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                size: 20,
              ),
            ),
        ],
      );
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: tr(
              radio.isLive || radio.mediaID?.startsWith('music-') == true
                  ? 'Anterior'
                  : 'Voltar 15 segundos',
            ),
            onPressed: () => skip(-1),
            icon: Icon(
              radio.isLive || radio.mediaID?.startsWith('music-') == true
                  ? Icons.skip_previous
                  : Icons.replay,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: radio.hasMedia ? radio.toggle : null,
              child: Icon(radio.playing ? Icons.pause : Icons.play_arrow),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: tr(
              radio.isLive || radio.mediaID?.startsWith('music-') == true
                  ? 'Próxima'
                  : 'Avançar 15 segundos',
            ),
            onPressed: () => skip(1),
            icon: Icon(
              radio.isLive || radio.mediaID?.startsWith('music-') == true
                  ? Icons.skip_next
                  : Icons.forward,
            ),
          ),
        ],
      );
      return Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .055),
          border: Border(top: BorderSide(color: accent.withValues(alpha: .1))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!radio.isLive && radio.duration.inMilliseconds > 0)
              PositionSlider(
                position: radio.position,
                duration: radio.duration,
                seek: (value) => unawaited(radio.seek(value)),
              ),
            if (roomy)
              Row(
                children: [
                  Expanded(flex: 3, child: metadata),
                  Expanded(flex: 2, child: controls),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        const Icon(Icons.volume_down, size: 20),
                        Expanded(
                          child: Slider(
                            value: radio.volume,
                            onChanged: radio.setVolume,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  metadata,
                  const SizedBox(height: 4),
                  controls,
                  if (showVolume)
                    Row(
                      children: [
                        const Icon(Icons.volume_down, size: 20),
                        Expanded(
                          child: Slider(
                            value: radio.volume,
                            onChanged: radio.setVolume,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}
