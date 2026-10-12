import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../music/transpose.dart';
import '../platform/platform.dart';
import 'import_ui.dart';
import 'settings_page.dart';
import 'song_editor.dart';

/// Library panel: songs and sets. Sits beside the song on wide screens and
/// in a drawer on narrow ones.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.state, this.onPicked});

  final AppState state;

  /// Called after something was chosen for display (closes the drawer).
  final VoidCallback? onPicked;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  String? _openSet; // set shown in detail inside the Sets tab

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TabBar(controller: _tabs, tabs: [
                  Tab(text: tr('Brani', 'Songs')),
                  Tab(text: tr('Scalette', 'Sets')),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: tr('Impostazioni', 'Settings'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(state: state))),
              ),
            ]),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                _SongsTab(state: state, onPicked: widget.onPicked),
                state.set(_openSet) == null
                    ? _SetsList(state: state, onOpen: (id) => setState(() => _openSet = id))
                    : _SetDetail(
                        state: state,
                        set: state.set(_openSet)!,
                        onBack: () => setState(() => _openSet = null),
                        onPicked: widget.onPicked,
                      ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Songs

class _SongsTab extends StatefulWidget {
  const _SongsTab({required this.state, this.onPicked});

  final AppState state;
  final VoidCallback? onPicked;

  @override
  State<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<_SongsTab> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  String? _folder;
  String? _tag;
  final _selected = <String>{};

  AppState get state => widget.state;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _newSong() async {
    final song = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => SongEditor(state: state)),
    );
    if (song == null) return;
    if (_folder != null) {
      song.folderIds.add(_folder!);
      await state.saveSong(song, touch: false);
    }
    state.showSong(song.id);
    widget.onPicked?.call();
  }

  Future<void> _addToSet(List<String> songIds) async {
    final set = await showDialog<SongSet>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('Aggiungi alla scaletta', 'Add to set')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, SongSet(name: tr('Nuova scaletta', 'New set'))),
            child: Row(children: [const Icon(Icons.add), const SizedBox(width: 12), Text(tr('Nuova scaletta', 'New set'))]),
          ),
          for (final s in state.sets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text('${s.name}  ·  ${formatDate(s.date)}'),
            ),
        ],
      ),
    );
    if (set == null) return;
    set.items.addAll([for (final id in songIds) SetItem(songId: id)]);
    await state.saveSet(set);
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Aggiunto a "${set.name}"', 'Added to "${set.name}"'))));
  }

  Future<void> _delete(List<String> ids) async {
    final ok = await confirm(
      context,
      ids.length == 1
          ? tr('Eliminare "${state.song(ids.first)?.title}"?', 'Delete "${state.song(ids.first)?.title}"?')
          : tr('Eliminare ${ids.length} brani?', 'Delete ${ids.length} songs?'),
      body: tr('I brani verranno rimossi anche dalle scalette.', 'The songs are removed from sets too.'),
    );
    if (!ok) return;
    await state.deleteSongs(ids);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _folders(Song song) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('Cartelle', 'Folders')),
          content: SizedBox(
            width: 320,
            child: ListView(shrinkWrap: true, children: [
              for (final f in state.folders)
                CheckboxListTile(
                  value: song.folderIds.contains(f.id),
                  title: Text(f.name),
                  onChanged: (v) {
                    v == true ? song.folderIds.add(f.id) : song.folderIds.remove(f.id);
                    state.saveSong(song, touch: false);
                    refresh(() {});
                  },
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(tr('Nuova cartella', 'New folder')),
                onTap: () async {
                  final name = await promptText(context, tr('Nuova cartella', 'New folder'));
                  if (name == null || name.isEmpty) return;
                  final folder = Folder(name: name, order: state.folders.length);
                  await state.saveFolder(folder);
                  song.folderIds.add(folder.id);
                  await state.saveSong(song, touch: false);
                  refresh(() {});
                },
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Chiudi', 'Close')))],
        ),
      ),
    );
  }

  Future<void> _folderMenu(Folder f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Rinomina', 'Rename')),
              onTap: () => Navigator.pop(context, 'rename')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Elimina cartella', 'Delete folder')),
              onTap: () => Navigator.pop(context, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = await promptText(context, tr('Rinomina cartella', 'Rename folder'), initial: f.name);
      if (name != null && name.isNotEmpty) await state.saveFolder(f..name = name);
    } else if (action == 'delete') {
      final ok = await confirm(context, tr('Eliminare la cartella "${f.name}"?', 'Delete folder "${f.name}"?'),
          body: tr('I brani non vengono eliminati.', 'Songs are not deleted.'));
      if (!ok) return;
      await state.deleteFolder(f.id);
      if (mounted && _folder == f.id) setState(() => _folder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final songs = state.search(query: _query.text, folderId: _folder, tag: _tag);
    final folders = state.folders;
    final tags = state.allTags;
    _selected.removeWhere((id) => state.song(id) == null);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Cerca titolo, artista, testo…', 'Search title, artist, lyrics…'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
            ),
          ),
          PopupMenuButton<SongSort>(
            icon: const Icon(Icons.sort),
            tooltip: tr('Ordina', 'Sort'),
            initialValue: state.settings.sort,
            onSelected: (v) {
              state.settings.sort = v;
              state.saveSettings();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: SongSort.title, child: Text(tr('Titolo', 'Title'))),
              PopupMenuItem(value: SongSort.artist, child: Text(tr('Artista', 'Artist'))),
              PopupMenuItem(value: SongSort.modified, child: Text(tr('Ultima modifica', 'Last modified'))),
              PopupMenuItem(value: SongSort.number, child: Text(tr('Numero', 'Number'))),
            ],
          ),
        ]),
      ),
      if (folders.isNotEmpty || tags.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in folders)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onLongPress: () => _folderMenu(f),
                    child: FilterChip(
                      avatar: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(f.name),
                      selected: _folder == f.id,
                      onSelected: (v) => setState(() => _folder = v ? f.id : null),
                    ),
                  ),
                ),
              for (final t in tags)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text('#$t'),
                    selected: _tag == t,
                    onSelected: (v) => setState(() => _tag = v ? t : null),
                  ),
                ),
            ],
          ),
        ),
      if (_selected.isNotEmpty)
        Material(
          color: scheme.secondaryContainer,
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
            Expanded(child: Text(tr('${_selected.length} selezionati', '${_selected.length} selected'))),
            IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: tr('Seleziona tutti', 'Select all'),
                onPressed: () => setState(() => _selected.addAll(songs.map((s) => s.id)))),
            IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: tr('Aggiungi alla scaletta', 'Add to set'),
                onPressed: () => _addToSet(_selected.toList())),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: tr('Elimina', 'Delete'),
                onPressed: () => _delete(_selected.toList())),
          ]),
        ),
      Expanded(
        child: songs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    state.songs.isEmpty
                        ? tr('La libreria è vuota.\nCrea un brano o importa dei file.',
                            'Your library is empty.\nCreate a song or import files.')
                        : tr('Nessun brano trovato', 'No songs found'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (context, i) {
                  final s = songs[i];
                  final current = state.currentSet == null && state.songId == s.id;
                  final key = parseKey(s.key)?.shift(s.transpose).name;
                  return ListTile(
                    dense: true,
                    selected: current,
                    selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
                    leading: _selected.isEmpty
                        ? null
                        : Checkbox(
                            value: _selected.contains(s.id),
                            onChanged: (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                          ),
                    title: Text(
                      s.songNumber > 0 ? '${s.songNumber}. ${s.title}' : s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                    subtitle: s.artist.isEmpty ? null : Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (key != null)
                        Text(key,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        onSelected: (v) async {
                          switch (v) {
                            case 'set':
                              _addToSet([s.id]);
                            case 'folders':
                              _folders(s);
                            case 'select':
                              setState(() => _selected.add(s.id));
                            case 'edit':
                              Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => SongEditor(state: state, song: s)));
                            case 'delete':
                              _delete([s.id]);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'set', child: Text(tr('Aggiungi alla scaletta…', 'Add to set…'))),
                          PopupMenuItem(value: 'folders', child: Text(tr('Cartelle…', 'Folders…'))),
                          PopupMenuItem(value: 'edit', child: Text(tr('Modifica', 'Edit'))),
                          PopupMenuItem(value: 'select', child: Text(tr('Seleziona', 'Select'))),
                          PopupMenuItem(value: 'delete', child: Text(tr('Elimina', 'Delete'))),
                        ],
                      ),
                    ]),
                    onLongPress: () => setState(() => _selected.add(s.id)),
                    onTap: () {
                      if (_selected.isNotEmpty) {
                        setState(() => _selected.contains(s.id) ? _selected.remove(s.id) : _selected.add(s.id));
                        return;
                      }
                      state.showSong(s.id);
                      widget.onPicked?.call();
                    },
                  );
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
                onPressed: _newSong, icon: const Icon(Icons.add), label: Text(tr('Nuovo', 'New'))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => importFiles(context, state),
                icon: const Icon(Icons.upload_file),
                label: Text(tr('Importa', 'Import'))),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: tr('Nuova cartella', 'New folder'),
            onPressed: () async {
              final name = await promptText(context, tr('Nuova cartella', 'New folder'));
              if (name != null && name.isNotEmpty) {
                await state.saveFolder(Folder(name: name, order: state.folders.length));
              }
            },
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Sets

class _SetsList extends StatelessWidget {
  const _SetsList({required this.state, required this.onOpen});

  final AppState state;
  final ValueChanged<String> onOpen;

  Future<void> _create(BuildContext context) async {
    final name = await promptText(context, tr('Nuova scaletta', 'New set'), hint: tr('Nome', 'Name'));
    if (name == null) return;
    final set = SongSet(name: name.isEmpty ? tr('Scaletta', 'Set') : name);
    await state.saveSet(set);
    onOpen(set.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sets = state.sets;
    return Column(children: [
      Expanded(
        child: sets.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr('Nessuna scaletta.\nCreane una per organizzare i brani di un incontro.',
                        'No sets yet.\nCreate one to line up the songs for a service.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: sets.length,
                itemBuilder: (context, i) {
                  final s = sets[i];
                  return ListTile(
                    leading: Icon(s.pinned ? Icons.push_pin : Icons.queue_music,
                        color: s.pinned ? scheme.primary : scheme.onSurfaceVariant),
                    selected: state.setId == s.id,
                    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${formatDate(s.date)}  ·  ${s.items.length} ${tr('elementi', 'items')}'),
                    onTap: () => onOpen(s.id),
                  );
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: Text(tr('Nuova scaletta', 'New set'))),
        ),
      ),
    ]);
  }
}

class _SetDetail extends StatelessWidget {
  const _SetDetail({required this.state, required this.set, required this.onBack, this.onPicked});

  final AppState state;
  final SongSet set;
  final VoidCallback onBack;
  final VoidCallback? onPicked;

  int get _totalSeconds =>
      set.items.fold(0, (sum, i) => sum + (i.type == SetItemType.song ? state.song(i.songId)?.duration ?? 0 : 0));

  Future<void> _addSongs(BuildContext context) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SongPicker(state: state),
    );
    if (picked == null || picked.isEmpty) return;
    set.items.addAll([for (final id in picked) SetItem(songId: id)]);
    await state.saveSet(set);
  }

  Future<void> _addNote(BuildContext context, [SetItem? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final text = TextEditingController(text: existing?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Nota', 'Note')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: InputDecoration(
                    labelText: tr('Titolo', 'Title'),
                    hintText: tr('es. Preghiera, Annunci', 'e.g. Prayer, Announcements'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: text,
                maxLines: 5,
                decoration: InputDecoration(labelText: tr('Testo', 'Text'), border: const OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Annulla', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Salva', 'Save'))),
        ],
      ),
    );
    if (ok != true) return;
    if (existing != null) {
      existing
        ..title = title.text.trim()
        ..text = text.text.trim();
    } else {
      set.items.add(SetItem(type: SetItemType.note, title: title.text.trim(), text: text.text.trim()));
    }
    await state.saveSet(set);
  }

  Future<void> _itemNotes(BuildContext context, SetItem item) async {
    final text = await promptText(context, tr('Note per questa scaletta', 'Notes for this set'),
        initial: item.text, lines: 4);
    if (text == null) return;
    item.text = text;
    await state.saveSet(set);
  }

  Future<void> _pickDate(BuildContext context) async {
    final d = await showDatePicker(
        context: context, initialDate: set.date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    set.date = d;
    await state.saveSet(set);
  }

  void _export() {
    final songIds = {for (final i in set.items) if (i.type == SetItemType.song) i.songId};
    final data = {
      'app': 'WorshipStudio',
      'version': 1,
      'songs': [for (final id in songIds) ?state.song(id)?.toJson()],
      'sets': [set.toJson()],
      'folders': <Object>[],
    };
    downloadFile('${set.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '')}.wsbackup', utf8.encode(jsonEncode(data)),
        'application/json');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _totalSeconds;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), tooltip: tr('Tutte le scalette', 'All sets'), onPressed: onBack),
          Expanded(
            child: InkWell(
              onTap: () async {
                final name = await promptText(context, tr('Nome della scaletta', 'Set name'), initial: set.name);
                if (name != null && name.isNotEmpty) await state.saveSet(set..name = name);
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(set.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  [formatDate(set.date), if (total > 0) formatDuration(total)].join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'date':
                  _pickDate(context);
                case 'pin':
                  state.saveSet(set..pinned = !set.pinned);
                case 'duplicate':
                  await state.duplicateSet(set);
                  onBack();
                case 'export':
                  _export();
                case 'delete':
                  if (await confirm(context, tr('Eliminare "${set.name}"?', 'Delete "${set.name}"?'))) {
                    await state.deleteSet(set.id);
                    onBack();
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'date', child: Text(tr('Cambia data', 'Change date'))),
              PopupMenuItem(value: 'pin', child: Text(set.pinned ? tr('Rimuovi fissaggio', 'Unpin') : tr('Fissa in alto', 'Pin'))),
              PopupMenuItem(value: 'duplicate', child: Text(tr('Duplica', 'Duplicate'))),
              PopupMenuItem(value: 'export', child: Text(tr('Esporta / condividi', 'Export / share'))),
              PopupMenuItem(value: 'delete', child: Text(tr('Elimina', 'Delete'))),
            ],
          ),
        ]),
      ),
      const Divider(height: 8),
      Expanded(
        child: set.items.isEmpty
            ? Center(
                child: Text(tr('Scaletta vuota', 'Empty set'), style: TextStyle(color: scheme.onSurfaceVariant)))
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: set.items.length,
                onReorderItem: (from, to) {
                  // Keep the highlighted item the same one after the move.
                  final shown = state.setId == set.id ? state.currentItem : null;
                  set.items.insert(to, set.items.removeAt(from));
                  if (shown != null) state.setIndex = set.items.indexOf(shown);
                  state.saveSet(set);
                },
                itemBuilder: (context, i) {
                  final item = set.items[i];
                  final song = item.type == SetItemType.song ? state.song(item.songId) : null;
                  final isNote = item.type == SetItemType.note;
                  final key = song == null ? null : parseKey(song.key)?.shift(item.transpose ?? song.transpose).name;
                  final capo = item.capo ?? song?.capo ?? 0;
                  final number = state.settings.numberSetItems ? '${i + 1}. ' : '';
                  return ListTile(
                    key: ValueKey(item.id),
                    dense: true,
                    selected: state.setId == set.id && state.setIndex == i,
                    selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    title: Text(
                      isNote
                          ? '$number${item.title.isEmpty ? tr('Nota', 'Note') : item.title}'
                          : '$number${song?.title ?? tr('(brano mancante)', '(missing song)')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontStyle: isNote ? FontStyle.italic : null),
                    ),
                    subtitle: isNote
                        ? (item.text.isEmpty ? null : Text(item.text, maxLines: 1, overflow: TextOverflow.ellipsis))
                        : Text(
                            [
                              ?key,
                              if (capo > 0) 'Capo $capo',
                              if (song != null && song.artist.isNotEmpty) song.artist,
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      onSelected: (v) {
                        switch (v) {
                          case 'notes':
                            isNote ? _addNote(context, item) : _itemNotes(context, item);
                          case 'remove':
                            final shown = state.setId == set.id ? state.currentItem : null;
                            set.items.removeAt(i);
                            if (state.setId == set.id) {
                              final at = shown == null ? -1 : set.items.indexOf(shown);
                              state.setIndex = at >= 0 ? at : (state.setIndex.clamp(-1, set.items.length - 1));
                            }
                            state.saveSet(set);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'notes', child: Text(isNote ? tr('Modifica nota', 'Edit note') : tr('Note…', 'Notes…'))),
                        PopupMenuItem(value: 'remove', child: Text(tr('Rimuovi dalla scaletta', 'Remove from set'))),
                      ],
                    ),
                    onTap: () {
                      state.showSetItem(set.id, i);
                      onPicked?.call();
                    },
                  );
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
                onPressed: () => _addSongs(context),
                icon: const Icon(Icons.playlist_add),
                label: Text(tr('Brani', 'Songs'))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => _addNote(context),
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: Text(tr('Nota', 'Note'))),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.play_arrow),
            tooltip: tr('Avvia scaletta', 'Start set'),
            onPressed: set.items.isEmpty
                ? null
                : () {
                    state.showSetItem(set.id, 0);
                    onPicked?.call();
                  },
          ),
        ]),
      ),
    ]);
  }
}

/// Multi-select song chooser used to fill a set.
class _SongPicker extends StatefulWidget {
  const _SongPicker({required this.state});

  final AppState state;

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  String _query = '';
  final _picked = <String>[];

  @override
  Widget build(BuildContext context) {
    final songs = widget.state.search(query: _query);
    return AlertDialog(
      title: Text(tr('Aggiungi brani', 'Add songs')),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr('Cerca…', 'Search…'),
                  border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final s = songs[i];
                return CheckboxListTile(
                  dense: true,
                  value: _picked.contains(s.id),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: s.artist.isEmpty ? null : Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  secondary: s.key.isEmpty ? null : Text(s.key),
                  onChanged: (v) => setState(() => v == true ? _picked.add(s.id) : _picked.remove(s.id)),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annulla', 'Cancel'))),
        FilledButton(
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
            child: Text(tr('Aggiungi (${_picked.length})', 'Add (${_picked.length})'))),
      ],
    );
  }
}
