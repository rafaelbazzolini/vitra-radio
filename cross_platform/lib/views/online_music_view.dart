import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/online_music.dart';
import '../core/music.dart';
import '../core/radio_store.dart';
import '../core/preferences.dart';
import 'library_views.dart';

// Online discovery is temporarily hidden; existing playlist metadata is preserved.
class MusicLibraryPage extends StatelessWidget {
  final MusicStore music;
  final OnlineMusicStore online;
  final RadioStore radio;
  const MusicLibraryPage({
    super.key,
    required this.music,
    required this.online,
    required this.radio,
  });
  @override
  Widget build(BuildContext context) => MusicPage(store: music, radio: radio);
}

class OnlineMusicPage extends StatefulWidget {
  final OnlineMusicStore store;
  final RadioStore radio;
  final bool playlistsOnly;
  const OnlineMusicPage({
    super.key,
    required this.store,
    required this.radio,
    required this.playlistsOnly,
  });
  @override
  State<OnlineMusicPage> createState() => _OnlineMusicPageState();
}

class _OnlineMusicPageState extends State<OnlineMusicPage> {
  final search = TextEditingController();
  late final clientID = TextEditingController(text: widget.store.clientID);
  String source = 'Internet Archive', field = 'Tudo', genre = '';
  String? selected;
  OnlineMusicStore get store => widget.store;
  @override
  void dispose() {
    search.dispose();
    clientID.dispose();
    super.dispose();
  }

  Future<void> runSearch() => store.search(
    source: source,
    text: search.text,
    field: field,
    genre: genre,
  );
  Future<String?> nameDialog({String? current}) async {
    final controller = TextEditingController(text: current ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr(current == null ? 'Nova playlist' : 'Renomear playlist'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(labelText: tr('Nome da playlist')),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(ctx, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text(tr('Salvar')),
          ),
        ],
      ),
    );
    // Dispose after the dialog route finishes animating, so its TextField has detached.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return value;
  }

  Future<void> newPlaylist() async {
    final name = await nameDialog();
    if (!mounted || name == null) {
      return;
    }
    setState(() => selected = store.create(name));
  }

  Future<void> addToPlaylist(OnlineMusicItem item) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Adicionar à playlist')),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title),
                for (final list in store.playlists)
                  ListTile(
                    title: Text(list.name),
                    leading: const Icon(Icons.queue_music),
                    onTap: () => Navigator.pop(ctx, list.id),
                  ),
                ListTile(
                  title: Text(tr('Nova playlist')),
                  leading: const Icon(Icons.add),
                  onTap: () => Navigator.pop(ctx, '__new__'),
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
        ],
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    if (choice == '__new__') {
      final name = await nameDialog();
      if (!mounted || name == null) {
        return;
      }
      final id = store.create(name);
      if (id != null) {
        store.add(item, id);
      }
    } else {
      store.add(item, choice);
    }
  }

  Future<void> playlistAction(String action, OnlinePlaylist list) async {
    if (action == 'rename') {
      final name = await nameDialog(current: list.name);
      if (mounted && name != null) {
        store.rename(list.id, name);
      }
    } else if (action == 'up') {
      store.movePlaylist(list.id, -1);
    } else if (action == 'down') {
      store.movePlaylist(list.id, 1);
    } else if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Excluir playlist?')),
          content: Text(tr('As faixas não serão removidas das fontes.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Excluir')),
            ),
          ],
        ),
      );
      if (mounted && yes == true) {
        store.delete(list.id);
        if (selected == list.id) {
          setState(() => selected = null);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final playlist = store.playlists
          .where((p) => p.id == selected)
          .firstOrNull;
      final items = widget.playlistsOnly
          ? (playlist?.tracks ?? <OnlineMusicItem>[])
          : store.opened == null
          ? store.results
          : store.tracks;
      final more =
          !widget.playlistsOnly && store.opened == null && store.hasMore;
      return ListView.builder(
        itemCount: 1 + items.length + (more ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    widget.playlistsOnly
                        ? 'Minhas playlists'
                        : 'Descobrir músicas',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Ouça online. Suas playlists ficam neste dispositivo.'),
                ),
                TextButton.icon(
                  onPressed: newPlaylist,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Nova playlist')),
                ),
                if (widget.playlistsOnly) ...[
                  if (store.playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        tr(
                          'Crie uma playlist e adicione músicas dos resultados da busca.',
                        ),
                      ),
                    ),
                  for (final list in store.playlists)
                    Card(
                      child: ListTile(
                        selected: selected == list.id,
                        leading: const Icon(Icons.queue_music),
                        title: Text(list.name),
                        subtitle: Text('${list.tracks.length} ${tr('faixas')}'),
                        onTap: () => setState(() => selected = list.id),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => playlistAction(action, list),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(tr('Renomear playlist')),
                            ),
                            PopupMenuItem(
                              value: 'up',
                              child: Text(tr('Mover para cima')),
                            ),
                            PopupMenuItem(
                              value: 'down',
                              child: Text(tr('Mover para baixo')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(tr('Excluir')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (playlist != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    FilledButton.icon(
                      onPressed: playlist.tracks.isEmpty || store.resolving
                          ? null
                          : () => store.play(
                              playlist.tracks.first,
                              playlist.tracks,
                              widget.radio,
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(tr('Ouvir playlist')),
                    ),
                    if (playlist.tracks.isEmpty)
                      Text(tr('Esta playlist ainda não tem músicas.')),
                  ],
                ] else ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Fonte')),
                    items: onlineSources
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        source = value;
                        if (source == 'Jamendo' && field == 'Compositor') {
                          field = 'Tudo';
                        }
                      });
                      store.clearSearch();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$source-$field'),
                    initialValue: field,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Pesquisar por')),
                    items: onlineFields
                        .where((f) => source != 'Jamendo' || f != 'Compositor')
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(
                              tr(f),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => field = value ?? 'Tudo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      labelText: tr('Música, artista ou compositor…'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onSubmitted: (_) => runSearch(),
                  ),
                  FilledButton(
                    onPressed: store.working ? null : runSearch,
                    child: Text(tr('Buscar')),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in onlineGenres)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(tr(onlineGenreTitle(item))),
                              selected: genre == item,
                              onSelected: (_) {
                                setState(() => genre = item);
                                unawaited(runSearch());
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (source == 'Jamendo')
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(tr('Conexão Jamendo')),
                      children: [
                        Text(
                          tr(
                            'O Jamendo precisa de um Client ID de aplicativo. O filtro Compositor está disponível apenas no Internet Archive; ele depende dos metadados publicados.',
                          ),
                        ),
                        TextField(
                          controller: clientID,
                          decoration: const InputDecoration(
                            labelText: 'Client ID',
                          ),
                          onSubmitted: store.setClientID,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await store.setClientID(clientID.text);
                                if (context.mounted) {
                                  FocusScope.of(context).unfocus();
                                }
                              },
                              child: Text(tr('Salvar')),
                            ),
                            TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse('https://devportal.jamendo.com/'),
                              ),
                              child: Text(
                                tr('Portal de desenvolvedores Jamendo'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        tr(
                          'O Archive pesquisa registros de músicas e álbuns. Cantor / artista usa o campo de autoria; Compositor depende dos metadados publicados.',
                        ),
                      ),
                    ),
                  if (store.opened != null) ...[
                    TextButton.icon(
                      onPressed: store.closeCollection,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(tr('Voltar aos resultados')),
                    ),
                    Text(
                      store.opened!.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => launchUrl(store.opened!.page),
                      child: Text(tr('Ver na fonte')),
                    ),
                  ],
                  if (items.isEmpty && !store.working)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        tr(
                          'Busque por música, artista ou categoria. No Internet Archive, abra um álbum para ver as faixas.',
                        ),
                      ),
                    ),
                ],
                if (store.working || store.resolving)
                  const LinearProgressIndicator(),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      tr(store.error!),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                if (store.notice != null) Text(tr(store.notice!)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    tr(
                      'Disponibilidade, autoria e categorias dependem dos dados da fonte. Nenhum arquivo de áudio é salvo para uso offline.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          }
          if (index > items.length) {
            return TextButton(
              onPressed: store.working ? null : store.more,
              child: Text(tr('Carregar mais')),
            );
          }
          final item = items[index - 1];
          return Card(
            child: ListTile(
              leading: Icon(
                item.isCollection
                    ? Icons.library_music
                    : Icons.play_circle_outline,
              ),
              title: Text(item.title),
              subtitle: Text(
                [
                  item.artist,
                  item.source,
                  item.isCollection ? tr('Ver faixas') : '',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              onTap: store.resolving
                  ? null
                  : () => item.isCollection
                        ? store.open(item)
                        : store.play(
                            item,
                            items.where((t) => !t.isCollection).toList(),
                            widget.radio,
                          ),
              trailing: item.isCollection
                  ? const Icon(Icons.chevron_right)
                  : PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'add') {
                          addToPlaylist(item);
                        } else if (action == 'source') {
                          launchUrl(item.page);
                        } else if (action == 'license') {
                          final url = onlineURL(item.license);
                          if (url != null) {
                            launchUrl(url);
                          }
                        } else if (playlist != null) {
                          if (action == 'remove') {
                            store.remove(item, playlist.id);
                          } else {
                            store.moveTrack(
                              item,
                              playlist.id,
                              action == 'up' ? -1 : 1,
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'add',
                          child: Text(tr('Adicionar à playlist')),
                        ),
                        if (widget.playlistsOnly) ...[
                          PopupMenuItem(
                            value: 'up',
                            child: Text(tr('Mover para cima')),
                          ),
                          PopupMenuItem(
                            value: 'down',
                            child: Text(tr('Mover para baixo')),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(tr('Remover da playlist')),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'source',
                          child: Text(tr('Ver na fonte')),
                        ),
                        if (onlineURL(item.license) != null)
                          PopupMenuItem(
                            value: 'license',
                            child: Text(tr('Licença')),
                          ),
                      ],
                    ),
            ),
          );
        },
      );
    },
  );
}
