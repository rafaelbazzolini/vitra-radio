import 'dart:async';
import 'package:flutter/material.dart';
import '../core/preferences.dart';
import '../core/podcasts.dart';
import '../core/music.dart';
import '../core/radio_store.dart';

Widget infoMessage(String? message) => message == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(tr(message), style: const TextStyle(color: Colors.orange)),
      );

class CountrySettings extends StatefulWidget {
  final AppPreferences settings;
  final VoidCallback? changed;
  final bool onboarding;
  const CountrySettings({
    super.key,
    required this.settings,
    this.changed,
    this.onboarding = false,
  });
  @override
  State<CountrySettings> createState() => _CountrySettingsState();
}

class _CountrySettingsState extends State<CountrySettings> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      final settings = widget.settings;
      final codes =
          settings.countries
              .map((c) => c['code'] as String)
              .where(
                (c) =>
                    query.isEmpty ||
                    settings
                        .name(c)
                        .toLowerCase()
                        .contains(query.toLowerCase()) ||
                    c.toLowerCase().contains(query.toLowerCase()),
              )
              .toList()
            ..sort((a, b) => settings.name(a).compareTo(settings.name(b)));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Idioma e região'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: settings.language,
            decoration: InputDecoration(labelText: tr('Idioma')),
            items: const [
              DropdownMenuItem(
                value: 'pt-BR',
                child: Text('Português (Brasil)'),
              ),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (value) {
              if (value != null) {
                unawaited(settings.setLanguage(value));
              }
            },
          ),
          const SizedBox(height: 20),
          Text(
            tr('Países das suas rádios'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Misture rádios de vários países no mesmo catálogo. A escolha fica salva neste dispositivo.',
            ),
          ),
          if (widget.onboarding)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr(
                  'A sugestão usa a região do dispositivo, sem GPS ou consulta ao seu IP.',
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              ActionChip(
                label: Text(tr('Mundo todo')),
                onPressed: () {
                  settings.setCodes([]);
                  widget.changed?.call();
                },
              ),
              ...settings.codes.map(
                (c) => InputChip(
                  label: Text(settings.name(c)),
                  onDeleted: () {
                    settings.setCodes(
                      settings.codes.where((x) => x != c).toList(),
                    );
                    widget.changed?.call();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Buscar país…'),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: codes.length,
              itemBuilder: (context, index) {
                final code = codes[index],
                    checked = settings.codes.contains(code);
                return CheckboxListTile(
                  dense: true,
                  title: Text(settings.name(code)),
                  subtitle: Text(code),
                  value: checked,
                  onChanged: !checked && settings.codes.length >= 8
                      ? null
                      : (_) {
                          settings.setCodes(
                            checked
                                ? settings.codes
                                      .where((c) => c != code)
                                      .toList()
                                : [...settings.codes, code],
                          );
                          widget.changed?.call();
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Até 8 países por vez · sem seleção: mundo todo'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

Future<void> countryDialog(
  BuildContext context,
  AppPreferences settings,
  VoidCallback changed, {
  bool onboarding = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: !onboarding,
  builder: (ctx) => PopScope(
    canPop: !onboarding,
    child: AlertDialog(
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: CountrySettings(
            settings: settings,
            changed: changed,
            onboarding: onboarding,
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            if (onboarding) {
              await settings.finishSetup();
            }
            if (ctx.mounted) {
              Navigator.pop(ctx);
            }
          },
          child: Text(tr(onboarding ? 'Começar a ouvir' : 'Concluir')),
        ),
      ],
    ),
  ),
);

class PodcastsPage extends StatefulWidget {
  final PodcastStore store;
  final RadioStore radio;
  final AppPreferences settings;
  const PodcastsPage({
    super.key,
    required this.store,
    required this.radio,
    required this.settings,
  });
  @override
  State<PodcastsPage> createState() => _PodcastsPageState();
}

class _PodcastsPageState extends State<PodcastsPage> {
  final search = TextEditingController();
  String section = 'Descobrir', language = '';
  @override
  void initState() {
    super.initState();
    if (widget.store.results.isEmpty || widget.store.lastCountry != country) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(widget.store.search('', country));
        }
      });
    }
  }

  String get country => widget.settings.codes.firstOrNull ?? 'US';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget cover(PodcastShow show) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 54,
      height: 54,
      child: show.artwork.isEmpty
          ? const Icon(Icons.podcasts)
          : Image.network(
              show.artwork,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.podcasts),
            ),
    ),
  );
  Future<void> addRSS() async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Adicionar por RSS')),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('Endereço RSS'),
            hintText: 'https://exemplo.com/podcast.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () {
              if (webURL(input.text) != null) {
                Navigator.pop(ctx, input.text.trim());
              }
            },
            child: Text(tr('Abrir')),
          ),
        ],
      ),
    );
    input.dispose();
    if (result != null) {
      await widget.store.open(PodcastShow(title: 'Podcast', feed: result));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store, feed = store.opened;
      final shows = section == 'Favoritos' ? store.favorites : store.results;
      final count = feed != null
          ? feed.episodes.length
          : section == 'Continuar ouvindo'
          ? (store.lastEpisode == null ? 0 : 1)
          : shows.length;
      return ListView.builder(
        itemCount: 1 + (count == 0 ? 1 : count),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feed == null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ...['Descobrir', 'Favoritos', 'Continuar ouvindo'].map(
                        (s) => ChoiceChip(
                          label: Text(tr(s)),
                          selected: section == s,
                          onSelected: (_) => setState(() => section = s),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.rss_feed, size: 18),
                        label: Text(tr('Adicionar por RSS')),
                        onPressed: addRSS,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (section == 'Descobrir') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: search,
                            decoration: InputDecoration(
                              hintText: tr('Buscar podcasts…'),
                              prefixIcon: const Icon(Icons.search),
                            ),
                            onSubmitted: (v) =>
                                store.search(v, country, language: language),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: store.searching
                              ? null
                              : () => store.search(
                                  search.text,
                                  country,
                                  language: language,
                                ),
                          child: Text(tr('Buscar')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => countryDialog(
                            context,
                            widget.settings,
                            () {
                              widget.radio.countryCodes = widget.settings.codes;
                              store.search(
                                search.text,
                                country,
                                language: language,
                              );
                            },
                          ),
                          icon: const Icon(Icons.public),
                          label: Text(widget.settings.name(country)),
                        ),
                        DropdownButton<String>(
                          isExpanded: true,
                          value: language,
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                tr('Todos os idiomas'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const DropdownMenuItem(
                              value: 'pt',
                              child: Text('Português'),
                            ),
                            const DropdownMenuItem(
                              value: 'en',
                              child: Text('English'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => language = v ?? '');
                            store.search(
                              search.text,
                              country,
                              language: language,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  TextButton.icon(
                    onPressed: store.closeFeed,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(tr('Podcasts')),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: cover(feed.show),
                    title: Text(
                      feed.show.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      feed.show.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: tr('Favoritar'),
                      onPressed: () => store.favorite(feed.show),
                      icon: Icon(
                        store.favorites.any((s) => s.feed == feed.show.feed)
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                    ),
                  ),
                ],
                if (store.loading || store.searching)
                  const LinearProgressIndicator(),
                infoMessage(store.error),
              ],
            );
          }
          if (count == 0) {
            return store.loading || store.searching
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        tr(
                          section == 'Continuar ouvindo'
                              ? 'Seu próximo episódio começa aqui.'
                              : section == 'Favoritos'
                              ? 'Seus podcasts favoritos aparecem aqui.'
                              : 'Nenhum podcast encontrado.',
                        ),
                      ),
                    ),
                  );
          }
          if (feed != null) {
            final episode = feed.episodes[index - 1];
            return Card(
              child: ListTile(
                title: Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  episode.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: tr('Ouvir episódio'),
                  onPressed: () => store.play(feed.show, episode, widget.radio),
                  icon: const Icon(Icons.play_circle_fill),
                ),
                onTap: () => store.play(feed.show, episode, widget.radio),
              ),
            );
          }
          if (section == 'Continuar ouvindo') {
            return ListTile(
              leading: const Icon(Icons.play_circle),
              title: Text(store.lastEpisode!.title),
              subtitle: Text(store.lastShow!.title),
              onTap: () =>
                  store.play(store.lastShow!, store.lastEpisode!, widget.radio),
            );
          }
          final show = shows[index - 1];
          return Card(
            child: ListTile(
              leading: cover(show),
              title: Text(
                show.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                show.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => store.open(show),
              trailing: IconButton(
                tooltip: tr('Favoritar'),
                onPressed: () => store.favorite(show),
                icon: Icon(
                  store.favorites.any((s) => s.feed == show.feed)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class MusicPage extends StatefulWidget {
  final MusicStore store;
  final RadioStore radio;
  const MusicPage({super.key, required this.store, required this.radio});
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> edit([MusicProfile? profile]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => MusicForm(store: widget.store, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final tracks = store.active?.kind == 'folder'
          ? store.tracks
                .where(
                  (t) => '${t.title} ${t.artist}'.toLowerCase().contains(
                    search.text.toLowerCase(),
                  ),
                )
                .toList()
          : store.tracks;
      final items = store.active == null
          ? <MusicItem>[]
          : store.showingTracks
          ? tracks
          : store.albums;
      final footer = store.active?.kind == 'folder' || store.hasMore;
      return ListView.builder(
        itemCount: 1 + items.length + (footer ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      tr('Sua música, por perto.'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    FilledButton.icon(
                      onPressed: store.working ? null : () => edit(),
                      icon: const Icon(Icons.add),
                      label: Text(tr('Adicionar')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'Ouça músicas de uma pasta do dispositivo ou conecte sua biblioteca online.',
                  ),
                ),
                const SizedBox(height: 16),
                if (store.profiles.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.library_music, size: 38),
                          const SizedBox(height: 12),
                          Text(
                            tr('Sua coleção merece um lugar aqui.'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              'Adicione uma pasta de músicas do seu dispositivo ou conecte um servidor. Seus arquivos permanecem onde estão, sem precisar copiar ou enviar.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => edit(),
                            child: Text(tr('Adicionar minhas músicas')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ...store.profiles.map(
                  (p) => Card(
                    child: ListTile(
                      leading: Icon(
                        p.kind == 'folder' ? Icons.folder : Icons.dns_outlined,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        tr(
                          store.active?.id == p.id
                              ? 'Conectado'
                              : p.local
                              ? 'Pasta deste dispositivo'
                              : p.kind == 'folder'
                              ? 'Pasta compartilhada na rede'
                              : p.kind == 'jellyfin'
                              ? 'Jellyfin'
                              : 'Navidrome / Subsonic',
                        ),
                      ),
                      onTap: store.working ? null : () => store.connect(p),
                      trailing: PopupMenuButton<String>(
                        enabled: !store.working,
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              edit(p);
                            case 'remove':
                              store.remove(p, widget.radio);
                            case 'disconnect':
                              store.disconnect(widget.radio);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(tr('Editar conexão')),
                          ),
                          if (store.active?.id == p.id)
                            PopupMenuItem(
                              value: 'disconnect',
                              child: Text(tr('Desconectar')),
                            ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(tr('Remover conexão')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (store.working) const LinearProgressIndicator(),
                infoMessage(store.error),
                if (store.active != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Sua biblioteca'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (store.showingTracks && store.active!.kind != 'folder')
                    TextButton(
                      onPressed: store.showAlbums,
                      child: Text(tr('Ver álbuns')),
                    ),
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: tr('Buscar músicas na biblioteca…'),
                      suffixIcon: store.active!.kind == 'folder'
                          ? null
                          : IconButton(
                              onPressed: () =>
                                  store.openAlbum(null, search: search.text),
                              icon: const Icon(Icons.search),
                            ),
                    ),
                    onChanged: store.active!.kind == 'folder'
                        ? (_) => setState(() {})
                        : null,
                    onSubmitted: (value) {
                      if (store.active!.kind != 'folder') {
                        store.openAlbum(null, search: value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (store.showingTracks && tracks.isEmpty && !store.working)
                    Text(
                      tr(
                        'Nenhuma faixa encontrada. Tente outro nome ou escolha outra pasta.',
                      ),
                    ),
                ],
              ],
            );
          }
          if (index > items.length) {
            return store.active?.kind == 'folder'
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      tr(
                        'Até 5.000 arquivos por pasta. Para coleções maiores, use um servidor de música.',
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: store.working ? null : store.loadMore,
                    child: Text(tr('Carregar mais álbuns')),
                  );
          }
          final item = items[index - 1];
          return Card(
            child: ListTile(
              leading: Icon(
                store.showingTracks ? Icons.play_arrow : Icons.album,
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                store.showingTracks
                    ? [
                        item.artist,
                        item.album,
                      ].where((s) => s.isNotEmpty).join(' · ')
                    : item.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => store.showingTracks
                  ? store.play(item, widget.radio)
                  : store.openAlbum(item),
            ),
          );
        },
      );
    },
  );
}

class MusicForm extends StatefulWidget {
  final MusicStore store;
  final MusicProfile? profile;
  const MusicForm({super.key, required this.store, this.profile});
  @override
  State<MusicForm> createState() => _MusicFormState();
}

class _MusicFormState extends State<MusicForm> {
  late final name = TextEditingController(text: widget.profile?.name ?? '');
  late final address = TextEditingController(
    text: widget.profile?.address ?? '',
  );
  late final username = TextEditingController(
    text: widget.profile?.username ?? '',
  );
  final password = TextEditingController();
  late bool local = widget.profile?.local ?? true;
  late String kind =
      widget.profile?.kind == 'folder' && widget.profile?.local == true
      ? 'subsonic'
      : widget.profile?.kind ?? 'subsonic';
  late String network = widget.profile?.network ?? 'local',
      folder = widget.profile?.folder ?? '';
  String folderName = '', message = '';
  bool busy = false, success = false;
  late final id =
      widget.profile?.id ?? 'music-${DateTime.now().microsecondsSinceEpoch}';
  MusicProfile get profile => MusicProfile(
    id: id,
    name: name.text.trim().isEmpty ? tr('Minha biblioteca') : name.text.trim(),
    kind: local ? 'folder' : kind,
    address: local ? '' : address.text.trim(),
    username: local ? '' : username.text.trim(),
    network: local ? 'local' : network,
    folder: folder,
    local: local,
  );
  @override
  void dispose() {
    name.dispose();
    address.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    try {
      final result = await DeviceMusic.choose();
      if (result != null && mounted) {
        setState(() {
          folder = result['uri'];
          folderName = result['name'];
          message = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = tr(
            'Não foi possível selecionar a pasta. Tente novamente.',
          ),
        );
      }
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      obscureText: secret,
      decoration: InputDecoration(
        labelText: tr(label),
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        if (message.isNotEmpty) {
          setState(() => message = '');
        }
      },
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(tr('Conectar minha música')),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.folder_outlined),
                    label: Text(tr('Pasta deste dispositivo')),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.dns_outlined),
                    label: Text(tr('Servidor de música')),
                  ),
                ],
                selected: {local},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() {
                        local = v.first;
                        message = '';
                      }),
              ),
              const SizedBox(height: 20),
              AbsorbPointer(
                absorbing: busy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field(name, 'Nome da biblioteca'),
                    if (!local) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: kind,
                        decoration: InputDecoration(
                          labelText: tr('Tipo de servidor'),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'subsonic',
                            child: Text(
                              'Navidrome / Subsonic',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 'jellyfin',
                            child: Text('Jellyfin'),
                          ),
                          DropdownMenuItem(
                            value: 'folder',
                            child: Text(
                              tr('Pasta compartilhada na rede'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => kind = v ?? 'subsonic'),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: network,
                        decoration: InputDecoration(
                          labelText: tr('Como você acessa?'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'local',
                            child: Text(tr('Rede local')),
                          ),
                          const DropdownMenuItem(
                            value: 'tailscale',
                            child: Text('Tailscale'),
                          ),
                          const DropdownMenuItem(
                            value: 'internet',
                            child: Text('Internet'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => network = v ?? 'local'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tr(
                          network == 'tailscale'
                              ? 'Conecte o Tailscale neste dispositivo e no servidor. Use o IP 100.x.x.x ou o nome MagicDNS, incluindo a porta do serviço.'
                              : network == 'internet'
                              ? 'Use o endereço HTTPS público do seu servidor.'
                              : 'Use o endereço do servidor na sua rede Wi-Fi ou Ethernet, incluindo a porta do serviço.',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (local || kind == 'folder') ...[
                      Text(
                        tr(
                          folder.isEmpty
                              ? 'Nenhuma pasta selecionada'
                              : 'Pasta salva nesta conexão',
                        ),
                      ),
                      if (folderName.isNotEmpty) Text(folderName),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: choose,
                        icon: const Icon(Icons.folder_open),
                        label: Text(tr('Escolher pasta…')),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          local
                              ? 'Escolha uma pasta deste dispositivo. Suas músicas aparecem aqui sem copiar os arquivos. A pasta precisa continuar disponível para tocar.'
                              : 'Para pastas de rede, use um provedor de arquivos compatível instalado no Android e selecione a pasta pelo seletor do sistema. Você também pode usar Navidrome ou Jellyfin.',
                        ),
                      ),
                    ] else ...[
                      field(
                        address,
                        'Endereço do servidor',
                        hint: kind == 'jellyfin'
                            ? 'http://servidor:8096'
                            : 'http://servidor:4533',
                      ),
                      field(username, 'Usuário'),
                      field(
                        password,
                        'Senha',
                        secret: true,
                        hint: widget.profile != null
                            ? tr(
                                'Deixe em branco para manter a credencial salva',
                              )
                            : null,
                      ),
                      Text(
                        tr(
                          'Credenciais protegidas pelo sistema do dispositivo.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: success
                          ? Theme.of(context).colorScheme.primary
                          : Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(tr('Cancelar')),
        ),
        OutlinedButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    message = '';
                  });
                  try {
                    await widget.store.test(profile, password.text);
                    if (mounted) {
                      setState(() {
                        success = true;
                        message = tr(
                          'Conexão validada. Você já pode salvar e abrir a biblioteca.',
                        );
                      });
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        success = false;
                        message = tr(
                          'Não foi possível conectar. Confira a pasta, endereço e credenciais.',
                        );
                      });
                    }
                  } finally {
                    if (mounted) {
                      setState(() => busy = false);
                    }
                  }
                },
          child: Text(tr(local ? 'Verificar pasta' : 'Testar conexão')),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  final saved = await widget.store.save(profile, password.text);
                  if (!context.mounted) {
                    return;
                  }
                  if (saved) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      busy = false;
                      success = false;
                      message = tr(
                        widget.store.error ?? 'Não foi possível conectar.',
                      );
                    });
                  }
                },
          child: Text(tr('Salvar e abrir')),
        ),
      ],
    ),
  );
}
