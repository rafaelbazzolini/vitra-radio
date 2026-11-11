import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/models.dart';
import 'core/radio_store.dart';
import 'core/updates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = RadioStore(await SharedPreferences.getInstance());
  runApp(VitraApp(store: store));
}

class VitraApp extends StatefulWidget {
  final RadioStore store;
  const VitraApp({super.key, required this.store});
  @override
  State<VitraApp> createState() => _VitraAppState();
}

class _VitraAppState extends State<VitraApp> with WidgetsBindingObserver {
  final updates = UpdateService();
  Timer? timer;
  final search = TextEditingController();
  RadioStore get radio => widget.store;
  static const pages = [
    'Início',
    'Todas as rádios',
    'Meus streams',
    'Temas',
    'Automação',
    'Sobre',
  ];
  static const icons = [
    Icons.home_rounded,
    Icons.radio,
    Icons.dns_outlined,
    Icons.palette_outlined,
    Icons.event_repeat,
    Icons.info_outline,
  ];
  static const skins = ['Vitra', 'Receiver', 'Studio', 'Heritage', 'Signal 90'];
  Color get accent => switch (radio.skin) {
    'Studio' => const Color(0xff285f91),
    'Heritage' => const Color(0xffefc47e),
    'Signal 90' => const Color(0xff72e6cd),
    _ => const Color(0xffc3f47a),
  };
  Color get background => switch (radio.skin) {
    'Studio' => const Color(0xffbbc6cf),
    'Heritage' => const Color(0xff33251d),
    'Signal 90' => const Color(0xff1b222c),
    _ => const Color(0xff101713),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(updates.initializeNotifications().then((_) => updates.check()));
    timer = Timer.periodic(const Duration(hours: 1), (_) => updates.check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      radio.evaluateSchedule();
      unawaited(updates.check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    search.dispose();
    updates.dispose();
    radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([radio, updates]),
    builder: (context, _) {
      final light = radio.skin == 'Studio';
      return MaterialApp(
        title: 'Vitra Radio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: light ? Brightness.light : Brightness.dark,
          colorSchemeSeed: accent,
          scaffoldBackgroundColor: background,
          fontFamily: radio.skin == 'Signal 90' ? 'monospace' : null,
        ),
        home: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
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
                              'SUA FREQUÊNCIA',
                              style: TextStyle(
                                color: accent,
                                letterSpacing: 3,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              radio.page == 'Início'
                                  ? 'O seu dia tem trilha.'
                                  : radio.page,
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
                        tooltip: 'Escolher tema',
                        initialValue: radio.skin,
                        onSelected: radio.chooseSkin,
                        itemBuilder: (_) => skins
                            .map(
                              (s) => CheckedPopupMenuItem(
                                value: s,
                                checked: s == radio.skin,
                                child: Text(s),
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
                              if (wide) const Text(' Tema'),
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
                            'Nova versão: ${updates.availableVersion}',
                          ),
                          subtitle: const Text(
                            'Atualização publicada a partir do main.',
                          ),
                          trailing: TextButton(
                            onPressed: updates.openRelease,
                            child: const Text('Atualizar'),
                          ),
                        ),
                      ),
                    ),
                  if (radio.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        radio.error!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  Expanded(
                    child: switch (radio.page) {
                      'Início' => home(context, wide),
                      'Todas as rádios' => catalog(context, wide),
                      'Meus streams' => streams(context),
                      'Temas' => themes(),
                      'Automação' => automation(context),
                      _ => about(context),
                    },
                  ),
                ],
              ),
            );
            return Scaffold(
              appBar: wide
                  ? null
                  : AppBar(
                      title: const Text('vitra radio'),
                      backgroundColor: background,
                    ),
              drawer: wide
                  ? null
                  : Drawer(child: navigation(context, drawer: true)),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (wide)
                            SizedBox(width: 212, child: navigation(context)),
                          Expanded(child: content),
                        ],
                      ),
                    ),
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
  Widget navigation(BuildContext context, {bool drawer = false}) => Container(
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: accent.withValues(alpha: .08))),
    ),
    padding: const EdgeInsets.fromLTRB(12, 36, 12, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 40),
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
              const Text(
                'vitra',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
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
              title: Text(pages[i], style: const TextStyle(fontSize: 13)),
              onTap: () {
                radio.navigate(pages[i]);
                if (drawer) Navigator.pop(context);
              },
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Sua biblioteca fica neste dispositivo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
  Widget home(BuildContext context, bool wide) => ListView(
    children: [
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
              radio.playing ? '● NO AR AGORA' : 'SINTONIZE SEU MOMENTO',
              style: TextStyle(color: accent, fontSize: 10, letterSpacing: 2),
            ),
            const SizedBox(height: 18),
            Text(
              radio.selected?.name ?? 'Uma boa trilha\nmuda tudo.',
              style: TextStyle(
                fontSize: wide ? 38 : 28,
                fontWeight: FontWeight.w600,
                height: 1.15,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              radio.selected?.genre ??
                  'Busque uma rádio ou adicione seu próprio stream.\nSem conta, sem uma seleção pré-carregada.',
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
                radio.selected == null
                    ? 'Encontrar rádios'
                    : radio.playing
                    ? 'Pausar rádio'
                    : 'Ouvir rádio',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'Favoritas',
            label: Text('Favoritas'),
            icon: Icon(Icons.favorite_border),
          ),
          ButtonSegment(
            value: 'Recentes',
            label: Text('Recentes'),
            icon: Icon(Icons.history),
          ),
        ],
        selected: {radio.section},
        onSelectionChanged: (v) => radio.chooseSection(v.first),
      ),
      const SizedBox(height: 18),
      if (radio.visible.isEmpty)
        empty(
          radio.section == 'Favoritas'
              ? 'Suas favoritas moram aqui.'
              : 'Seu histórico começa quando você ouvir uma rádio.',
        ),
      ...radio.visible.map(stationTile),
    ],
  );
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
        [
          station.genre,
          station.location,
        ].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => radio.play(station),
      trailing: IconButton(
        tooltip: 'Favoritar',
        onPressed: () => radio.favorite(station),
        icon: Icon(
          radio.favorites.contains(station.id)
              ? Icons.favorite
              : Icons.favorite_border,
          color: accent,
        ),
      ),
    ),
  );
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(child: Text(text, textAlign: TextAlign.center)),
  );
  Widget catalog(BuildContext context, bool wide) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nome da rádio',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => radio.search(v),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: radio.searching ? null : () => radio.search(search.text),
            child: const Text('Buscar'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => addStream(context),
          icon: const Icon(Icons.add_link),
          label: const Text('Adicionar stream por URL'),
        ),
      ),
      if (radio.searching) const LinearProgressIndicator(),
      Expanded(
        child: radio.results.isEmpty
            ? empty('Pesquise no catálogo mundial Radio Browser.')
            : ListView(children: radio.results.map(stationTile).toList()),
      ),
    ],
  );
  Widget streams(BuildContext context) => ListView(
    children: [
      const Text(
        'Sua música, por perto.',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Adicione a URL direta de um stream de rádio ou música. Funciona por rede local, internet ou Tailscale quando o servidor está acessível pelo dispositivo. O aplicativo não configura a VPN.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => addStream(context),
        icon: const Icon(Icons.add_link),
        label: const Text('Adicionar stream'),
      ),
      const SizedBox(height: 20),
      ...radio.library.map(stationTile),
    ],
  );
  Future<void> addStream(BuildContext context) async {
    final name = TextEditingController(), url = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Adicionar rádio'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'URL direta do stream',
                    hintText: 'https://servidor/stream',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
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
              child: const Text('Salvar nas favoritas'),
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
      const Text(
        'Uma nova cara para o seu som.',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 18),
      ...skins.map(
        (s) => Card(
          child: ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(s),
            subtitle: Text(
              s == 'Heritage'
                  ? 'Madeira e âmbar'
                  : s == 'Studio'
                  ? 'Alumínio e azul'
                  : s == 'Signal 90'
                  ? 'Digital e luminoso'
                  : 'Escuro e contemporâneo',
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
      const Text(
        'Sua rádio. Na hora certa.',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Horário local do dispositivo. Sobreposições retomam a faixa anterior. Datas específicas têm prioridade. A execução exige que o processo esteja ativo; não acorda o aparelho nem promete execução com o app suspenso.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: radio.library.isEmpty ? null : () => scheduleDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Programar rádio'),
      ),
      const SizedBox(height: 18),
      ...radio.schedules.map(
        (r) => Card(
          child: ListTile(
            title: Text(
              '${RadioSchedule.time(r.start)} — ${RadioSchedule.time(r.end)} · ${radio.library.where((s) => s.id == r.stationId).firstOrNull?.name ?? 'Rádio removida'}',
            ),
            subtitle: Text(
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
          title: const Text('Programar rádio'),
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
                    decoration: const InputDecoration(labelText: 'Rádio'),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: from,
                          decoration: const InputDecoration(
                            labelText: 'Início · HH:mm',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: to,
                          decoration: const InputDecoration(
                            labelText: 'Término · HH:mm',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Semanal')),
                      ButtonSegment(
                        value: true,
                        label: Text('Data específica'),
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
                          label: Text(['S', 'T', 'Q', 'Q', 'S', 'S', 'D'][i]),
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
                    Text(error!, style: const TextStyle(color: Colors.orange)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    from.dispose();
    to.dispose();
  }

  Widget about(BuildContext context) => ListView(
    children: [
      const Text(
        'Vitra Radio',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 14),
      const Text(
        'Rádio pela internet, com uma biblioteca que fica só no seu dispositivo. Projeto aberto, sem contas e sem telemetria própria.',
      ),
      const SizedBox(height: 20),
      ListTile(
        leading: const Icon(Icons.system_update),
        title: Text(
          updates.availableVersion == null
              ? 'Verificar atualizações'
              : 'Atualização ${updates.availableVersion} disponível',
        ),
        subtitle: Text(
          updates.error ??
              'Versão instalada: ${updates.currentVersion} · canal main',
        ),
        onTap: updates.check,
        trailing: updates.checking
            ? const CircularProgressIndicator()
            : const Icon(Icons.refresh),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Text('Ativar notificações de atualização'),
        subtitle: const Text(
          'Requer permissão do sistema. Consultas ao abrir, retornar ao app e a cada hora enquanto ativo.',
        ),
        onTap: () async {
          await updates.requestNotificationPermission();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Preferência salva. A permissão final é controlada pelo sistema.',
                ),
              ),
            );
          }
        },
      ),
      TextButton(
        onPressed: updates.openRelease,
        child: const Text('Versões e código no GitHub'),
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No iOS, a atualização instalável depende de TestFlight/App Store e assinatura Apple. Esta edição compartilhada ainda não inclui todos os recursos avançados do app nativo de macOS.',
        ),
      ),
    ],
  );
  Widget transport(BuildContext context, bool wide) => Container(
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .055),
      border: Border(top: BorderSide(color: accent.withValues(alpha: .10))),
    ),
    padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 12),
    child: Row(
      children: [
        Icon(Icons.graphic_eq, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                radio.selected?.name ?? 'Escolha sua rádio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                radio.busy
                    ? 'Conectando…'
                    : radio.playing
                    ? 'Ao vivo'
                    : 'Pronto para ouvir',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => radio.skip(-1),
          icon: const Icon(Icons.skip_previous),
        ),
        FilledButton(
          onPressed: radio.selected == null ? null : radio.toggle,
          child: Icon(radio.playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          onPressed: () => radio.skip(1),
          icon: const Icon(Icons.skip_next),
        ),
        if (wide)
          SizedBox(
            width: 130,
            child: Slider(value: radio.volume, onChanged: radio.setVolume),
          ),
      ],
    ),
  );
}
