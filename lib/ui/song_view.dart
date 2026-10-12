import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../data/import_export.dart';
import '../l10n.dart';
import '../models.dart';
import '../music/chordpro.dart';
import '../music/transpose.dart';
import '../platform/platform.dart';
import 'key_dialog.dart';
import 'settings_page.dart';
import 'song_body.dart';
import 'song_editor.dart';

/// The performance view: the current song (or set note) with live controls.
class SongView extends StatefulWidget {
  const SongView({
    super.key,
    required this.state,
    required this.fullscreen,
    required this.onFullscreen,
    this.onMenu,
  });

  final AppState state;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;

  /// Opens the library drawer; null when the library is always visible.
  final VoidCallback? onMenu;

  @override
  State<SongView> createState() => _SongViewState();
}

class _SongViewState extends State<SongView> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _beat = ValueNotifier<int>(-1);
  Timer? _metronome;
  Timer? _scrollDelay;
  bool _scrolling = false;
  String? _shown; // id of what is displayed, to reset on change
  String? _parsedFor;
  SongDoc? _doc;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _metronome?.cancel();
    _scrollDelay?.cancel();
    _scroll.dispose();
    _focus.dispose();
    _beat.dispose();
    super.dispose();
  }

  void _onState() {
    final id = state.currentItem?.id ?? state.currentSong?.id;
    if (id != _shown) {
      _shown = id;
      _stopScroll();
      _stopMetronome();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      setWakeLock(state.settings.keepAwake && id != null);
    }
    if (mounted) setState(() {});
  }

  SongDoc _parse(Song song) {
    final stamp = '${song.id}|${song.content.hashCode}';
    if (_parsedFor != stamp) {
      _doc = parseChordPro(song.content);
      _parsedFor = stamp;
    }
    return _doc!;
  }

  // ---- autoscroll --------------------------------------------------------

  void _toggleScroll(Song song) {
    if (_scrolling) return _stopScroll();
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final left = max - _scroll.offset;
    if (left <= 0) return;
    final total = song.duration > 0 ? song.duration : state.settings.autoscrollSeconds;
    setState(() => _scrolling = true);
    _scrollDelay = Timer(Duration(seconds: _scroll.offset == 0 ? state.settings.autoscrollDelay : 0), () {
      if (!_scroll.hasClients) return;
      final ms = (total * 1000 * left / (max == 0 ? 1 : max)).round().clamp(500, 3600000);
      _scroll.animateTo(max, duration: Duration(milliseconds: ms), curve: Curves.linear).whenComplete(() {
        if (mounted && _scrolling) setState(() => _scrolling = false);
      });
    });
  }

  void _stopScroll() {
    _scrollDelay?.cancel();
    if (!_scrolling) return;
    _scrolling = false;
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset); // cancels the animation
    if (mounted) setState(() {});
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    _stopScroll();
    final p = _scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.85).clamp(0.0, p.maxScrollExtent);
    // At the end of a song, paging forward moves on through the set.
    if (direction > 0 && p.pixels >= p.maxScrollExtent - 1 && state.hasNext) return state.next();
    if (direction < 0 && p.pixels <= 0 && state.hasPrevious) return state.previous();
    _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ---- metronome ---------------------------------------------------------

  void _toggleMetronome(Song song) {
    if (_metronome != null) return _stopMetronome();
    if (song.tempo <= 0) return;
    final beats = int.tryParse(song.timeSig.split('/').first) ?? 4;
    var n = 0;
    void tick() {
      _beat.value = n % beats;
      if (state.settings.metronomeSound) playClick(accent: n % beats == 0);
      n++;
    }

    tick();
    _metronome = Timer.periodic(Duration(microseconds: (60000000 / song.tempo).round()), (_) => tick());
    setState(() {});
  }

  void _stopMetronome() {
    _metronome?.cancel();
    _metronome = null;
    _beat.value = -1;
    if (mounted) setState(() {});
  }

  // ---- actions -----------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space) {
      _page(1);
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) {
      _page(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      state.next();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      state.previous();
    } else if (k == LogicalKeyboardKey.escape && widget.fullscreen) {
      _setFullscreen(false);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _setFullscreen(bool on) {
    setFullscreen(on);
    widget.onFullscreen(on);
  }

  Future<void> _zoom(Song song, double factor) async {
    song.zoom = factor == 0 ? 1 : (song.zoom * factor).clamp(0.5, 3.0);
    await state.saveSong(song, touch: false);
  }

  Future<void> _edit(Song? song) async {
    final saved = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => SongEditor(state: state, song: song)),
    );
    if (saved != null && state.currentSet == null) state.showSong(saved.id);
  }

  void _export(Song song) {
    downloadFile('${safeFileName(song.title)}.cho', utf8.encode(songToChordPro(song)), 'text/plain');
  }

  @override
  Widget build(BuildContext context) {
    final song = state.currentSong;
    final item = state.currentItem;
    final set = state.currentSet;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (item != null && item.type == SetItemType.note) {
      body = _NoteBody(item: item);
    } else if (song == null) {
      body = _Empty(onNew: state.canEdit ? () => _edit(null) : null, onMenu: widget.onMenu);
    } else {
      final written = parseKey(song.key);
      final shift = state.transpose - state.capo;
      body = LayoutBuilder(builder: (context, box) {
        final pad = box.maxWidth > 700 ? 32.0 : 16.0;
        return SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pad, 16, pad + 56, 120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.fullscreen) _FullscreenTitle(song: song),
            _MetaLine(song: song, transpose: state.transpose, capo: state.capo),
            if (item != null && item.text.trim().isNotEmpty) _NoteBanner(text: item.text),
            if (item == null && song.notes.trim().isNotEmpty) _NoteBanner(text: song.notes),
            const SizedBox(height: 12),
            SongBody(
              doc: _parse(song),
              settings: state.settings,
              sectionOrder: state.sectionOrder,
              shift: shift,
              songKey: written,
              zoom: song.zoom,
            ),
            if (song.copyright.isNotEmpty)
              Text('© ${song.copyright}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
        );
      });
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: widget.fullscreen ? null : _appBar(song, item),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focus.requestFocus,
          child: Stack(children: [
            Positioned.fill(child: body),
            if (song != null)
              Positioned(
                right: 8,
                bottom: set != null ? 12 : 16,
                child: _LiveButtons(
                  scrolling: _scrolling,
                  metronome: _metronome != null,
                  hasTempo: song.tempo > 0,
                  fullscreen: widget.fullscreen,
                  beat: _beat,
                  onScroll: () => _toggleScroll(song),
                  onMetronome: () => _toggleMetronome(song),
                  onZoomIn: () => _zoom(song, 1.1),
                  onZoomOut: () => _zoom(song, 1 / 1.1),
                  onZoomReset: () => _zoom(song, 0),
                  onFullscreen: () => _setFullscreen(!widget.fullscreen),
                ),
              )
            else if (widget.fullscreen)
              Positioned(
                right: 8,
                bottom: 16,
                child: IconButton.filledTonal(
                    onPressed: () => _setFullscreen(false), icon: const Icon(Icons.fullscreen_exit)),
              ),
          ]),
        ),
        bottomNavigationBar: set == null ? null : _SetBar(state: state, set: set),
      ),
    );
  }

  PreferredSizeWidget _appBar(Song? song, SetItem? item) {
    final title = song?.title ?? (item != null ? (item.title.isEmpty ? tr('Nota', 'Note') : item.title) : 'WorshipStudio');
    final shownKey = song == null ? null : parseKey(song.key)?.shift(state.transpose);
    return AppBar(
      leading: widget.onMenu == null
          ? null
          : IconButton(icon: const Icon(Icons.menu), tooltip: tr('Libreria', 'Library'), onPressed: widget.onMenu),
      titleSpacing: widget.onMenu == null ? 16 : 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, overflow: TextOverflow.ellipsis),
        if (song != null && song.artist.isNotEmpty)
          Text(song.artist,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      actions: [
        if (song != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.music_note, size: 18),
              label: Text([
                shownKey?.name ?? (state.transpose == 0 ? tr('Tonalità', 'Key') : _signed(state.transpose)),
                if (state.capo > 0) 'C${state.capo}',
              ].join(' · ')),
              tooltip: tr('Tonalità e capotasto', 'Key and capo'),
              onPressed: () => showKeyDialog(context, state),
            ),
          ),
          if (state.canEdit)
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: tr('Modifica', 'Edit'), onPressed: () => _edit(song)),
        ],
        PopupMenuButton<String>(
          tooltip: tr('Altro', 'More'),
          onSelected: (v) {
            switch (v) {
              case 'new':
                _edit(null);
              case 'export':
                _export(song!);
              case 'chords':
                state.settings.showChords = !state.settings.showChords;
                state.saveSettings();
              case 'settings':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(state: state)));
            }
          },
          itemBuilder: (_) => [
            if (state.canEdit) PopupMenuItem(value: 'new', child: _menuRow(Icons.add, tr('Nuovo brano', 'New song'))),
            if (song != null) ...[
              PopupMenuItem(
                  value: 'chords',
                  child: _menuRow(
                      state.settings.showChords ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      state.settings.showChords ? tr('Nascondi accordi', 'Hide chords') : tr('Mostra accordi', 'Show chords'))),
              PopupMenuItem(value: 'export', child: _menuRow(Icons.download_outlined, tr('Esporta ChordPro', 'Export ChordPro'))),
            ],
            const PopupMenuDivider(),
            PopupMenuItem(value: 'settings', child: _menuRow(Icons.settings_outlined, tr('Impostazioni', 'Settings'))),
          ],
        ),
      ],
    );
  }
}

String _signed(int n) => n > 0 ? '+$n' : '$n';

Widget _menuRow(IconData icon, String text) =>
    Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(text))]);

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.song, required this.transpose, required this.capo});

  final Song song;
  final int transpose;
  final int capo;

  @override
  Widget build(BuildContext context) {
    final key = parseKey(song.key)?.shift(transpose);
    final parts = [
      if (key != null) '${tr('Tonalità', 'Key')} ${key.name}',
      if (capo > 0) '${tr('Capotasto', 'Capo')} $capo',
      if (song.tempo > 0) '${song.tempo} BPM',
      if (song.timeSig.isNotEmpty) song.timeSig,
      if (song.duration > 0) formatDuration(song.duration),
    ];
    if (parts.isEmpty && song.subtitle.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (song.subtitle.isNotEmpty) Text(song.subtitle, style: style),
      if (parts.isNotEmpty) Text(parts.join('  ·  '), style: style),
    ]);
  }
}

class _FullscreenTitle extends StatelessWidget {
  const _FullscreenTitle({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          [song.title, if (song.artist.isNotEmpty) song.artist].join(' — '),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      );
}

class _NoteBanner extends StatelessWidget {
  const _NoteBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.sticky_note_2_outlined, size: 18, color: scheme.onTertiaryContainer),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer))),
      ]),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.item});

  final SetItem item;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title.isEmpty ? tr('Nota', 'Note') : item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(item.text, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5)),
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onNew, this.onMenu});

  final VoidCallback? onNew; // null in a library the user may only read
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.library_music_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 16),
          Text(tr('Nessun brano selezionato', 'No song selected'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
            if (onMenu != null)
              OutlinedButton.icon(
                  onPressed: onMenu, icon: const Icon(Icons.menu), label: Text(tr('Apri la libreria', 'Open library'))),
            if (onNew != null)
              FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add), label: Text(tr('Nuovo brano', 'New song'))),
          ]),
        ]),
      ),
    );
  }
}

class _LiveButtons extends StatelessWidget {
  const _LiveButtons({
    required this.scrolling,
    required this.metronome,
    required this.hasTempo,
    required this.fullscreen,
    required this.beat,
    required this.onScroll,
    required this.onMetronome,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onFullscreen,
  });

  final bool scrolling, metronome, hasTempo, fullscreen;
  final ValueNotifier<int> beat;
  final VoidCallback onScroll, onMetronome, onZoomIn, onZoomOut, onZoomReset, onFullscreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tip, VoidCallback onTap, {bool active = false, VoidCallback? onLong}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onLongPress: onLong,
            child: active
                ? IconButton.filled(onPressed: onTap, icon: Icon(icon), tooltip: tip)
                : IconButton.filledTonal(onPressed: onTap, icon: Icon(icon), tooltip: tip),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      button(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, tr('Schermo intero', 'Full screen'), onFullscreen),
      button(Icons.zoom_in, tr('Ingrandisci', 'Zoom in'), onZoomIn, onLong: onZoomReset),
      button(Icons.zoom_out, tr('Riduci (tieni premuto: reimposta)', 'Zoom out (hold: reset)'), onZoomOut, onLong: onZoomReset),
      if (hasTempo)
        ValueListenableBuilder<int>(
          valueListenable: beat,
          builder: (context, b, _) => Stack(alignment: Alignment.topRight, children: [
            button(Icons.av_timer, tr('Metronomo', 'Metronome'), onMetronome, active: metronome),
            if (b >= 0)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: b == 0 ? scheme.error : scheme.tertiary,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
          ]),
        ),
      button(scrolling ? Icons.pause : Icons.play_arrow, tr('Scorrimento automatico', 'Auto-scroll'), onScroll,
          active: scrolling),
    ]);
  }
}

/// Previous / next navigation shown while playing from a set.
class _SetBar extends StatelessWidget {
  const _SetBar({required this.state, required this.set});

  final AppState state;
  final SongSet set;

  String _title(SetItem i) => i.type == SetItemType.note
      ? (i.title.isEmpty ? tr('Nota', 'Note') : i.title)
      : state.song(i.songId)?.title ?? '?';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = state.hasNext ? set.items[state.setIndex + 1] : null;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(children: [
            IconButton(
                onPressed: state.hasPrevious ? state.previous : null,
                icon: const Icon(Icons.skip_previous),
                tooltip: tr('Precedente', 'Previous')),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${set.name}  ${state.setIndex + 1}/${set.items.length}',
                    overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                if (next != null)
                  Text('${tr('Prossimo', 'Next')}: ${_title(next)}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            IconButton(
                onPressed: state.hasNext ? state.next : null,
                icon: const Icon(Icons.skip_next),
                tooltip: tr('Successivo', 'Next')),
          ]),
        ),
      ),
    );
  }
}
