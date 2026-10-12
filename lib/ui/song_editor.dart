import 'dart:math';

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../music/chordpro.dart';
import '../music/transpose.dart';
import 'song_body.dart';

/// Create or edit a song: metadata, content (ChordPro or chords over
/// lyrics) and a live preview.
/// Pops with the saved [Song], or null when cancelled.
class SongEditor extends StatefulWidget {
  const SongEditor({super.key, required this.state, this.song});

  final AppState state;
  final Song? song;

  @override
  State<SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<SongEditor> with TickerProviderStateMixin {
  /// From this width up the preview sits beside the editor instead of in a tab.
  static const _wideWidth = 900.0;

  late final Song _song = widget.song?.copy() ?? Song();
  late final _tabs = TabController(length: 3, vsync: this);
  late final _wideTabs = TabController(length: 2, vsync: this); // no preview tab
  late final _title = TextEditingController(text: _song.title);
  late final _subtitle = TextEditingController(text: _song.subtitle);
  late final _artist = TextEditingController(text: _song.artist);
  late final _tempo = TextEditingController(text: _song.tempo > 0 ? '${_song.tempo}' : '');
  late final _time = TextEditingController(text: _song.timeSig);
  late final _duration = TextEditingController(text: _song.duration > 0 ? formatDuration(_song.duration) : '');
  late final _number = TextEditingController(text: _song.songNumber > 0 ? '${_song.songNumber}' : '');
  late final _tags = TextEditingController(text: _song.tags.join(', '));
  late final _order = TextEditingController(text: _song.sectionOrder);
  late final _copyright = TextEditingController(text: _song.copyright);
  late final _url = TextEditingController(text: _song.url);
  late final _notes = TextEditingController(text: _song.notes);
  late final _content = TextEditingController(text: _format(_song.content));
  final _contentFocus = FocusNode();
  bool _dirty = false;

  /// Chords are written on the line above the lyrics rather than inline.
  late bool _chordsOver = widget.state.settings.chordsOverLyrics;

  String _format(String text) => _chordsOver ? chordProToChordsOverLyrics(text) : chordsOverLyricsToChordPro(text);

  void _setChordsOver(bool value) {
    if (value == _chordsOver) return;
    setState(() => _chordsOver = value);
    final text = _format(_content.text);
    if (text != _content.text) _content.text = text;
    widget.state.settings.chordsOverLyrics = value;
    widget.state.saveSettings();
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _subtitle, _artist, _tempo, _time, _duration, _number, _tags, _order, _copyright, _url, _notes, _content]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [_title, _subtitle, _artist, _tempo, _time, _duration, _number, _tags, _order, _copyright, _url, _notes, _content]) {
      c.dispose();
    }
    _tabs.dispose();
    _wideTabs.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  int _parseDuration(String v) {
    final parts = v.split(':').map((p) => int.tryParse(p.trim()) ?? 0);
    return parts.fold(0, (acc, p) => acc * 60 + p);
  }

  /// Copies the form fields into [_song].
  void _collect() {
    _song
      ..title = _title.text.trim()
      ..subtitle = _subtitle.text.trim()
      ..artist = _artist.text.trim()
      ..tempo = int.tryParse(_tempo.text.trim()) ?? 0
      ..timeSig = _time.text.trim()
      ..duration = _parseDuration(_duration.text)
      ..songNumber = int.tryParse(_number.text.trim()) ?? 0
      ..tags = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList()
      ..sectionOrder = _order.text.trim()
      ..copyright = _copyright.text.trim()
      ..url = _url.text.trim()
      ..notes = _notes.text.trim()
      ..content = _content.text;
  }

  Future<void> _save() async {
    _collect();
    if (_song.title.isEmpty) {
      // Fall back to the {title} directive before complaining.
      _song.title = parseChordPro(_song.content).title ?? '';
    }
    if (_song.title.isEmpty) {
      _tabs.animateTo(1);
      _wideTabs.animateTo(1);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Il titolo è obbligatorio', 'A title is required'))));
      return;
    }
    await widget.state.saveSong(_song);
    if (mounted) Navigator.of(context).pop(_song);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Uscire senza salvare?', 'Leave without saving?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Annulla', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Esci', 'Leave'))),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Inserts [before]/[after] around the selection in the content field.
  void _insert(String before, [String after = '']) {
    final sel = _content.selection;
    final text = _content.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = text.substring(start, end);
    _content.value = TextEditingValue(
      text: text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection.collapsed(offset: start + before.length + selected.length),
    );
    _contentFocus.requestFocus();
  }

  void _detectKey() {
    final key = detectKey(parseChordPro(_content.text).chords.toList());
    if (key == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Nessun accordo trovato', 'No chords found'))));
      return;
    }
    setState(() {
      _song.key = key;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideWidth;
    final contentTab = Tab(text: tr('Testo', 'Content'));
    final detailsTab = Tab(text: tr('Dettagli', 'Details'));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.song == null ? tr('Nuovo brano', 'New song') : tr('Modifica brano', 'Edit song')),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(tr('Salva', 'Save'))),
            ),
          ],
          bottom: wide
              ? null
              : TabBar(controller: _tabs, tabs: [contentTab, detailsTab, Tab(text: tr('Anteprima', 'Preview'))]),
        ),
        body: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: Column(children: [
                    TabBar(controller: _wideTabs, tabs: [contentTab, detailsTab]),
                    Expanded(child: TabBarView(controller: _wideTabs, children: [_contentTab(), _detailsTab()])),
                  ]),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _previewTab()),
              ])
            : TabBarView(controller: _tabs, children: [_contentTab(), _detailsTab(), _previewTab()]),
      ),
    );
  }

  Widget _contentTab() {
    Widget chip(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(label: Text(label), onPressed: onTap, visualDensity: VisualDensity.compact),
        );
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                const ButtonSegment(value: false, label: Text('ChordPro')),
                ButtonSegment(value: true, label: Text(tr('Accordi sopra', 'Chords over lyrics'))),
              ],
              selected: {_chordsOver},
              onSelectionChanged: (s) => _setChordsOver(s.first),
            ),
          ),
          if (!_chordsOver) chip('[ ]', () => _insert('[', ']')),
          chip(tr('Strofa', 'Verse'), () => _insert('{start_of_verse}\n', '\n{end_of_verse}\n')),
          chip(tr('Ritornello', 'Chorus'), () => _insert('{start_of_chorus}\n', '\n{end_of_chorus}\n')),
          chip(tr('Bridge', 'Bridge'), () => _insert('{start_of_bridge}\n', '\n{end_of_bridge}\n')),
          chip(tr('Commento', 'Comment'), () => _insert('{comment: ', '}')),
          chip('Tab', () => _insert('{start_of_tab}\n', '\n{end_of_tab}\n')),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _chordsOver ? _unwrapped(_contentField()) : _contentField(),
        ),
      ),
    ]);
  }

  static const _contentFontSize = 15.0;

  Widget _contentField() {
    const example = 'Amazing grace, how sweet the sound';
    final hint = _chordsOver
        ? 'G              C         G\n$example'
        : 'A[G]mazing grace, how [C]sweet the [G]sound';
    return TextField(
      controller: _content,
      focusNode: _contentFocus,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontFamily: 'RobotoMono', fontSize: _contentFontSize, height: 1.4),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: tr('Incolla o scrivi il brano.\nEsempio:\n$hint', 'Paste or type the song.\nExample:\n$hint'),
      ),
    );
  }

  /// Lets [field] grow as wide as its longest line and scroll sideways:
  /// a wrapped line would no longer sit under its chords.
  Widget _unwrapped(Widget field) {
    return LayoutBuilder(
      builder: (context, box) => ValueListenableBuilder(
        valueListenable: _content,
        child: field,
        builder: (context, value, child) {
          final longest = value.text.split('\n').fold(0, (n, l) => max(n, l.length));
          // RobotoMono advances 0.6 em per character; the rest is padding.
          final width = longest * _contentFontSize * 0.6 + 48;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: max(box.maxWidth, width), height: box.maxHeight, child: child),
          );
        },
      ),
    );
  }

  Widget _detailsTab() {
    Widget field(TextEditingController c, String label, {String? hint, TextInputType? type, int lines = 1}) => TextField(
          controller: c,
          keyboardType: type,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        );
    const gap = SizedBox(height: 12, width: 12);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            field(_title, tr('Titolo', 'Title')),
            gap,
            field(_subtitle, tr('Sottotitolo', 'Subtitle')),
            gap,
            field(_artist, tr('Artista', 'Artist')),
            gap,
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_song.key),
                  initialValue: allKeys.contains(_song.key) ? _song.key : '',
                  decoration: InputDecoration(labelText: tr('Tonalità', 'Key'), border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr('Non impostata', 'Not set'))),
                    for (final k in allKeys) DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) => setState(() {
                    _song.key = v ?? '';
                    _dirty = true;
                  }),
                ),
              ),
              gap,
              OutlinedButton(onPressed: _detectKey, child: Text(tr('Rileva', 'Detect'))),
            ]),
            gap,
            Row(children: [
              Expanded(child: field(_tempo, 'BPM', type: TextInputType.number)),
              gap,
              Expanded(child: field(_time, tr('Tempo', 'Time'), hint: '4/4')),
              gap,
              Expanded(child: field(_duration, tr('Durata', 'Duration'), hint: 'mm:ss')),
            ]),
            gap,
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _song.capo,
                  decoration: InputDecoration(labelText: tr('Capotasto', 'Capo'), border: const OutlineInputBorder()),
                  items: [for (var i = 0; i < 12; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? '—' : '$i'))],
                  onChanged: (v) => setState(() {
                    _song.capo = v ?? 0;
                    _dirty = true;
                  }),
                ),
              ),
              gap,
              Expanded(child: field(_number, tr('Numero', 'Number'), type: TextInputType.number)),
            ]),
            gap,
            field(_tags, tr('Etichette', 'Tags'), hint: tr('separate da virgola', 'comma separated')),
            gap,
            field(_order, tr('Ordine delle sezioni', 'Section order'), hint: 'V1 C1 V2 C1 B1 C1'),
            gap,
            field(_notes, tr('Note', 'Notes'), lines: 3),
            gap,
            field(_copyright, 'Copyright'),
            gap,
            field(_url, tr('Link web', 'Web link'), type: TextInputType.url),
          ]),
        ),
      ),
    );
  }

  /// Follows the content and section order as they are typed.
  Widget _previewTab() {
    return ListenableBuilder(
      listenable: Listenable.merge([_content, _order]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SongBody(
          doc: parseChordPro(_content.text),
          settings: widget.state.settings,
          sectionOrder: _order.text,
          songKey: parseKey(_song.key),
        ),
      ),
    );
  }
}
