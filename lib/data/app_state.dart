import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models.dart';
import 'seeds.dart';

/// A local change that has not been stored in the cloud yet.
class PendingChange {
  PendingChange(this.kind, this.id, this.groupId, this.deleted, this.modified, this.stamp);

  final String kind; // songs | sets | folders
  final String id;
  final String groupId;
  final bool deleted;
  final DateTime modified;
  final int stamp; // tells a newer change to the same item apart

  String get key => '$kind/$id';

  factory PendingChange.fromJson(Map<String, Object?> j) => PendingChange(
        j['kind'] as String,
        j['id'] as String,
        j['groupId'] as String? ?? '',
        j['deleted'] == true,
        DateTime.tryParse(j['modified'] as String? ?? '') ?? DateTime.now(),
        (j['stamp'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
        'kind': kind,
        'id': id,
        'groupId': groupId,
        'deleted': deleted,
        'modified': modified.toIso8601String(),
        'stamp': stamp,
      };
}

/// In-memory library backed by a sembast database (IndexedDB on the web).
///
/// Every song and set belongs to a library: the personal one (groupId == '')
/// or a group's. [scope] is the library on screen. Changes are recorded as
/// [PendingChange]s for the cloud sync in cloud.dart to send.
class AppState extends ChangeNotifier {
  AppState._(this._db);

  final Database _db;
  static final _songStore = stringMapStoreFactory.store('songs');
  static final _setStore = stringMapStoreFactory.store('sets');
  static final _folderStore = stringMapStoreFactory.store('folders');
  static final _prefs = stringMapStoreFactory.store('prefs');
  static final _pendingStore = stringMapStoreFactory.store('pending');

  final Map<String, Song> _songs = {};
  final Map<String, SongSet> _sets = {};
  final Map<String, Folder> _folders = {};
  final Map<String, PendingChange> _pending = {};
  AppSettings settings = AppSettings();

  /// Library on screen: '' for the personal one, otherwise a group id.
  String scope = '';

  /// Groups whose songs and sets this user may change (set by the cloud service).
  Set<String> writableGroups = {};

  /// Whether changes are queued for the cloud; on once an account is linked.
  bool trackChanges = false;
  int _stamp = 0;

  // What is on screen.
  String? songId;
  String? setId;
  int setIndex = -1;

  static Future<AppState> open(DatabaseFactory factory, [String name = 'worship_studio.db']) async {
    final state = AppState._(await factory.openDatabase(name));
    await state._load();
    return state;
  }

  Future<void> _load() async {
    for (final r in await _songStore.find(_db)) {
      final s = Song.fromJson(r.value);
      _songs[s.id] = s;
    }
    for (final r in await _setStore.find(_db)) {
      final s = SongSet.fromJson(r.value);
      _sets[s.id] = s;
    }
    for (final r in await _folderStore.find(_db)) {
      final f = Folder.fromJson(r.value);
      _folders[f.id] = f;
    }
    final prefs = await _prefs.record('settings').get(_db);
    if (prefs != null) settings = AppSettings.fromJson(prefs);
    final seeded = await _prefs.record('seeded').get(_db);
    if (seeded == null) {
      for (final s in seedSongs()) {
        await saveSong(s, touch: false);
      }
      await _prefs.record('seeded').put(_db, {'done': true});
    }
    for (final r in await _pendingStore.find(_db)) {
      final p = PendingChange.fromJson(r.value);
      _pending[p.key] = p;
    }
    trackChanges = (await _prefs.record('cloud').get(_db))?['uid'] != null;
    final last = await _prefs.record('last').get(_db);
    scope = last?['scope'] as String? ?? '';
    final lastSong = last?['songId'] as String?;
    if (lastSong != null && _songs[lastSong]?.groupId == scope) songId = lastSong;
  }

  Future<Map<String, Object?>?> readPref(String key) => _prefs.record(key).get(_db);
  Future<void> writePref(String key, Map<String, Object?> value) => _prefs.record(key).put(_db, value);

  // ---- queries -----------------------------------------------------------

  List<Song> get songs => _songs.values.where((s) => s.groupId == scope).toList();

  /// Folders exist only in the personal library.
  List<Folder> get folders =>
      scope.isEmpty ? (_folders.values.toList()..sort((a, b) => a.order.compareTo(b.order))) : [];

  bool get canEdit => scope.isEmpty || writableGroups.contains(scope);
  Song? song(String? id) => id == null ? null : _songs[id];
  SongSet? set(String? id) => id == null ? null : _sets[id];

  /// Pinned sets first, then most recent date first.
  List<SongSet> get sets => _sets.values.where((s) => s.groupId == scope).toList()
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.date.compareTo(a.date);
    });

  List<String> get allTags {
    final tags = <String>{for (final s in songs) ...s.tags};
    return tags.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Songs matching [query] (title, artist, tags, lyrics), [folderId] and [tag].
  List<Song> search({String query = '', String? folderId, String? tag}) {
    final q = _fold(query.trim());
    final list = _songs.values.where((s) {
      if (s.groupId != scope) return false;
      if (folderId != null && !s.folderIds.contains(folderId)) return false;
      if (tag != null && !s.tags.contains(tag)) return false;
      if (q.isEmpty) return true;
      return _fold(s.title).contains(q) ||
          _fold(s.artist).contains(q) ||
          s.tags.any((t) => _fold(t).contains(q)) ||
          (s.songNumber > 0 && s.songNumber.toString() == q) ||
          _fold(s.content).contains(q);
    }).toList();
    int byTitle(Song a, Song b) => _fold(a.title).compareTo(_fold(b.title));
    switch (settings.sort) {
      case SongSort.title:
        list.sort(byTitle);
      case SongSort.artist:
        list.sort((a, b) {
          final c = _fold(a.artist).compareTo(_fold(b.artist));
          return c != 0 ? c : byTitle(a, b);
        });
      case SongSort.modified:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case SongSort.number:
        list.sort((a, b) {
          final c = a.songNumber.compareTo(b.songNumber);
          return c != 0 ? c : byTitle(a, b);
        });
    }
    return list;
  }

  static const _accents = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
  static const _plain = 'aaaaaaeeeeiiiiooooouuuucn';

  static String _fold(String s) {
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final i = _accents.indexOf(ch);
      out.write(i < 0 ? ch : _plain[i]);
    }
    return out.toString();
  }

  // ---- display context ---------------------------------------------------

  SongSet? get currentSet => set(setId);

  SetItem? get currentItem {
    final s = currentSet;
    if (s == null || setIndex < 0 || setIndex >= s.items.length) return null;
    return s.items[setIndex];
  }

  Song? get currentSong {
    final item = currentItem;
    if (item != null) return item.type == SetItemType.song ? song(item.songId) : null;
    return song(songId);
  }

  int get transpose => currentItem?.transpose ?? currentSong?.transpose ?? 0;
  int get capo => currentItem?.capo ?? currentSong?.capo ?? 0;

  String get sectionOrder {
    final item = currentItem;
    if (item != null && item.sectionOrder.isNotEmpty) return item.sectionOrder;
    return currentSong?.sectionOrder ?? '';
  }

  void showSong(String id) {
    songId = id;
    setId = null;
    setIndex = -1;
    _prefs.record('last').put(_db, {'songId': id, 'scope': scope});
    notifyListeners();
  }

  void setScope(String groupId) {
    if (scope == groupId) return;
    scope = groupId;
    songId = null;
    setId = null;
    setIndex = -1;
    _prefs.record('last').put(_db, {'songId': null, 'scope': scope});
    notifyListeners();
  }

  void showSetItem(String set, int index) {
    setId = set;
    setIndex = index;
    notifyListeners();
  }

  bool get hasNext => currentSet != null && setIndex < currentSet!.items.length - 1;
  bool get hasPrevious => currentSet != null && setIndex > 0;

  void next() {
    if (hasNext) showSetItem(setId!, setIndex + 1);
  }

  void previous() {
    if (hasPrevious) showSetItem(setId!, setIndex - 1);
  }

  /// Transposition is stored on the set item when playing from a set, so the
  /// same song can sit in different keys in different sets.
  Future<void> setTranspose(int value) async {
    final item = currentItem;
    if (item != null) {
      item.transpose = value;
      await saveSet(currentSet!);
    } else if (currentSong case final s?) {
      s.transpose = value;
      await saveSong(s);
    }
  }

  Future<void> setCapo(int value) async {
    final item = currentItem;
    if (item != null) {
      item.capo = value;
      await saveSet(currentSet!);
    } else if (currentSong case final s?) {
      s.capo = value;
      await saveSong(s);
    }
  }

  // ---- mutations ---------------------------------------------------------

  /// Queues a change for the cloud. Changes to a group the user may only read
  /// stay on this device (a different key or zoom, say).
  Future<void> _mark(DatabaseClient db, String kind, String id, String groupId,
      {bool deleted = false, DateTime? modified}) async {
    if (!trackChanges || (groupId.isNotEmpty && !writableGroups.contains(groupId))) return;
    final p = PendingChange(kind, id, groupId, deleted, modified ?? DateTime.now(), ++_stamp);
    _pending[p.key] = p;
    await _pendingStore.record(p.key).put(db, p.toJson());
  }

  Future<void> _putSong(DatabaseClient db, Song s) async {
    _songs[s.id] = s;
    await _songStore.record(s.id).put(db, s.toJson());
    await _mark(db, 'songs', s.id, s.groupId, modified: s.modified);
  }

  Future<void> _putSet(DatabaseClient db, SongSet s) async {
    _sets[s.id] = s;
    await _setStore.record(s.id).put(db, s.toJson());
    await _mark(db, 'sets', s.id, s.groupId, modified: s.modified);
  }

  /// New songs and sets go to the library on screen.
  Future<void> saveSong(Song s, {bool touch = true}) async {
    if (touch) s.modified = DateTime.now();
    if (!_songs.containsKey(s.id)) s.groupId = scope;
    await _putSong(_db, s);
    notifyListeners();
  }

  Future<void> deleteSongs(Iterable<String> ids) async {
    final gone = ids.toSet();
    await _db.transaction((txn) async {
      for (final id in gone) {
        final song = _songs.remove(id);
        await _songStore.record(id).delete(txn);
        if (song != null) await _mark(txn, 'songs', id, song.groupId, deleted: true);
      }
      for (final set in _sets.values) {
        final before = set.items.length;
        set.items.removeWhere((i) => i.type == SetItemType.song && gone.contains(i.songId));
        if (set.items.length != before) {
          set.modified = DateTime.now();
          await _putSet(txn, set);
        }
      }
    });
    if (gone.contains(songId)) songId = null;
    if (currentSet != null && setIndex >= currentSet!.items.length) setIndex = currentSet!.items.length - 1;
    notifyListeners();
  }

  Future<void> saveSet(SongSet s) async {
    s.modified = DateTime.now();
    if (!_sets.containsKey(s.id)) s.groupId = scope;
    await _putSet(_db, s);
    notifyListeners();
  }

  Future<void> deleteSet(String id) async {
    final set = _sets.remove(id);
    await _setStore.record(id).delete(_db);
    if (set != null) await _mark(_db, 'sets', id, set.groupId, deleted: true);
    if (setId == id) {
      setId = null;
      setIndex = -1;
    }
    notifyListeners();
  }

  Future<SongSet> duplicateSet(SongSet source) async {
    final copy = SongSet.fromJson(source.toJson()..remove('id'))
      ..name = '${source.name} (2)'
      ..pinned = false;
    copy.items = [for (final i in source.items) SetItem.fromJson(i.toJson()..remove('id'))];
    await saveSet(copy);
    return copy;
  }

  /// Copies a song into another library, reusing an identical one already there.
  Future<Song> copySong(Song source, String groupId) async {
    final same = _songs.values
        .where((s) => s.groupId == groupId && s.title == source.title && s.content == source.content)
        .firstOrNull;
    if (same != null) return same;
    final copy = Song.fromJson(source.toJson()..remove('id'))
      ..groupId = groupId
      ..folderIds = []
      ..modified = DateTime.now();
    await _putSong(_db, copy);
    notifyListeners();
    return copy;
  }

  /// Copies a set and the songs it uses into another library.
  Future<SongSet> copySet(SongSet source, String groupId) async {
    final copy = SongSet.fromJson(source.toJson()..remove('id'))
      ..groupId = groupId
      ..pinned = false
      ..modified = DateTime.now();
    copy.items = [];
    for (final i in source.items) {
      final item = SetItem.fromJson(i.toJson()..remove('id'));
      if (item.type == SetItemType.song) {
        final song = _songs[item.songId];
        if (song == null) continue;
        item.songId = (await copySong(song, groupId)).id;
      }
      copy.items.add(item);
    }
    await _putSet(_db, copy);
    notifyListeners();
    return copy;
  }

  Future<void> saveFolder(Folder f) async {
    _folders[f.id] = f;
    await _folderStore.record(f.id).put(_db, f.toJson());
    await _mark(_db, 'folders', f.id, '');
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    _folders.remove(id);
    await _db.transaction((txn) async {
      await _folderStore.record(id).delete(txn);
      await _mark(txn, 'folders', id, '', deleted: true);
      for (final s in _songs.values.where((s) => s.folderIds.contains(id))) {
        s.folderIds.remove(id);
        await _putSong(txn, s);
      }
    });
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await _prefs.record('settings').put(_db, settings.toJson());
    notifyListeners();
  }

  // ---- backup ------------------------------------------------------------

  /// The library on screen.
  Map<String, Object?> exportBackup() => {
        'app': 'WorshipStudio',
        'version': 1,
        'exported': DateTime.now().toIso8601String(),
        'songs': [for (final s in songs) s.toJson()],
        'sets': [for (final s in sets) s.toJson()],
        'folders': [for (final f in folders) f.toJson()],
      };

  /// Merges a backup into the library on screen; items with the same id are
  /// replaced, unless they belong to another library, in which case the
  /// imported ones get new ids.
  Future<({int songs, int sets})> importBackup(Map<String, Object?> data) async {
    List<Map<String, Object?>> maps(String key) =>
        [for (final e in (data[key] as List? ?? const [])) Map<String, Object?>.from(e as Map)];
    final renamed = <String, String>{};
    final songs = [
      for (final j in maps('songs'))
        if (_songs[j['id']] case final other? when other.groupId != scope)
          Song.fromJson({...j}..remove('id'))
        else
          Song.fromJson(j)
    ];
    for (final (i, j) in maps('songs').indexed) {
      if (j['id'] case final String id when id != songs[i].id) renamed[id] = songs[i].id;
    }
    final sets = [
      for (final j in maps('sets'))
        if (_sets[j['id']] case final other? when other.groupId != scope)
          SongSet.fromJson({...j}..remove('id'))
        else
          SongSet.fromJson(j)
    ];
    final folders = scope.isEmpty ? maps('folders').map(Folder.fromJson).toList() : <Folder>[];
    await _db.transaction((txn) async {
      for (final f in folders) {
        _folders[f.id] = f;
        await _folderStore.record(f.id).put(txn, f.toJson());
        await _mark(txn, 'folders', f.id, '');
      }
      for (final s in songs) {
        s.groupId = scope;
        if (scope.isNotEmpty) s.folderIds = [];
        await _putSong(txn, s);
      }
      for (final s in sets) {
        s.groupId = scope;
        for (final i in s.items) {
          i.songId = renamed[i.songId] ?? i.songId;
        }
        await _putSet(txn, s);
      }
    });
    notifyListeners();
    return (songs: songs.length, sets: sets.length);
  }

  /// Empties the personal library (in the cloud too, at the next sync).
  Future<void> resetLibrary() async {
    await _db.transaction((txn) async {
      for (final s in _songs.values.where((s) => s.groupId.isEmpty).toList()) {
        _songs.remove(s.id);
        await _songStore.record(s.id).delete(txn);
        await _mark(txn, 'songs', s.id, '', deleted: true);
      }
      for (final s in _sets.values.where((s) => s.groupId.isEmpty).toList()) {
        _sets.remove(s.id);
        await _setStore.record(s.id).delete(txn);
        await _mark(txn, 'sets', s.id, '', deleted: true);
      }
      for (final id in _folders.keys.toList()) {
        _folders.remove(id);
        await _folderStore.record(id).delete(txn);
        await _mark(txn, 'folders', id, '', deleted: true);
      }
    });
    if (scope.isEmpty) {
      songId = null;
      setId = null;
      setIndex = -1;
    }
    notifyListeners();
  }

  // ---- cloud sync (driven by cloud.dart) ---------------------------------

  List<PendingChange> get pendingChanges => _pending.values.toList();

  Map<String, Object?>? itemJson(String kind, String id) => switch (kind) {
        'songs' => _songs[id]?.toJson(),
        'sets' => _sets[id]?.toJson(),
        _ => _folders[id]?.toJson(),
      };

  /// Forgets the changes that were sent, unless the item changed again meanwhile.
  Future<void> clearPending(Iterable<PendingChange> sent) async {
    await _db.transaction((txn) async {
      for (final p in sent) {
        if (_pending[p.key]?.stamp != p.stamp) continue;
        _pending.remove(p.key);
        await _pendingStore.record(p.key).delete(txn);
      }
    });
  }

  /// Queues the whole personal library: used when an account is first linked.
  Future<void> markAllPending() async {
    trackChanges = true;
    await _db.transaction((txn) async {
      for (final s in _songs.values.where((s) => s.groupId.isEmpty)) {
        await _mark(txn, 'songs', s.id, '', modified: s.modified);
      }
      for (final s in _sets.values.where((s) => s.groupId.isEmpty)) {
        await _mark(txn, 'sets', s.id, '', modified: s.modified);
      }
      for (final f in _folders.values) {
        await _mark(txn, 'folders', f.id, '');
      }
    });
  }

  /// Applies documents read from the cloud to the library [groupId]. A local
  /// change still waiting to be sent wins unless the cloud one is more recent.
  Future<void> applyRemote(String groupId, String kind, List<Map<String, Object?>> docs) async {
    if (docs.isEmpty) return;
    await _db.transaction((txn) async {
      for (final doc in docs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        final key = '$kind/$id';
        final local = _pending[key];
        if (local != null) {
          final remote = DateTime.tryParse(doc['modified'] as String? ?? '');
          if (remote == null || !remote.isAfter(local.modified)) continue;
          _pending.remove(key);
          await _pendingStore.record(key).delete(txn);
        }
        final deleted = doc['deleted'] == true;
        final json = {...doc, 'groupId': groupId};
        switch (kind) {
          case 'songs':
            deleted ? _songs.remove(id) : _songs[id] = Song.fromJson(json);
            await (deleted ? _songStore.record(id).delete(txn) : _songStore.record(id).put(txn, _songs[id]!.toJson()));
          case 'sets':
            deleted ? _sets.remove(id) : _sets[id] = SongSet.fromJson(json);
            await (deleted ? _setStore.record(id).delete(txn) : _setStore.record(id).put(txn, _sets[id]!.toJson()));
          default:
            deleted ? _folders.remove(id) : _folders[id] = Folder.fromJson(json);
            await (deleted
                ? _folderStore.record(id).delete(txn)
                : _folderStore.record(id).put(txn, _folders[id]!.toJson()));
        }
      }
    });
    _fixDisplay();
    notifyListeners();
  }

  /// Removes the local copy of the groups the user is no longer a member of.
  Future<void> keepGroups(Set<String> ids) async {
    bool gone(String groupId) => groupId.isNotEmpty && !ids.contains(groupId);
    await _db.transaction((txn) async {
      for (final s in _songs.values.where((s) => gone(s.groupId)).toList()) {
        _songs.remove(s.id);
        await _songStore.record(s.id).delete(txn);
      }
      for (final s in _sets.values.where((s) => gone(s.groupId)).toList()) {
        _sets.remove(s.id);
        await _setStore.record(s.id).delete(txn);
      }
      for (final p in _pending.values.where((p) => gone(p.groupId)).toList()) {
        _pending.remove(p.key);
        await _pendingStore.record(p.key).delete(txn);
      }
    });
    if (gone(scope)) {
      scope = '';
      await _prefs.record('last').put(_db, {'songId': null, 'scope': ''});
    }
    _fixDisplay();
    notifyListeners();
  }

  void _fixDisplay() {
    if (songId != null && _songs[songId]?.groupId != scope) songId = null;
    final set = currentSet;
    if (setId != null && (set == null || set.groupId != scope)) {
      setId = null;
      setIndex = -1;
    } else if (set != null && setIndex >= set.items.length) {
      setIndex = set.items.length - 1;
    }
  }
}