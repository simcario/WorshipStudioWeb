import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models.dart';
import 'seeds.dart';

/// In-memory library backed by a sembast database (IndexedDB on the web).
class AppState extends ChangeNotifier {
  AppState._(this._db);

  final Database _db;
  static final _songStore = stringMapStoreFactory.store('songs');
  static final _setStore = stringMapStoreFactory.store('sets');
  static final _folderStore = stringMapStoreFactory.store('folders');
  static final _prefs = stringMapStoreFactory.store('prefs');

  final Map<String, Song> _songs = {};
  final Map<String, SongSet> _sets = {};
  final Map<String, Folder> _folders = {};
  AppSettings settings = AppSettings();

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
    final last = await _prefs.record('last').get(_db);
    final lastSong = last?['songId'] as String?;
    if (lastSong != null && _songs.containsKey(lastSong)) songId = lastSong;
  }

  // ---- queries -----------------------------------------------------------

  List<Song> get songs => _songs.values.toList();
  List<Folder> get folders => _folders.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  Song? song(String? id) => id == null ? null : _songs[id];
  SongSet? set(String? id) => id == null ? null : _sets[id];

  /// Pinned sets first, then most recent date first.
  List<SongSet> get sets => _sets.values.toList()
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.date.compareTo(a.date);
    });

  List<String> get allTags {
    final tags = <String>{for (final s in _songs.values) ...s.tags};
    return tags.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Songs matching [query] (title, artist, tags, lyrics), [folderId] and [tag].
  List<Song> search({String query = '', String? folderId, String? tag}) {
    final q = _fold(query.trim());
    final list = _songs.values.where((s) {
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
    _prefs.record('last').put(_db, {'songId': id});
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

  Future<void> saveSong(Song s, {bool touch = true}) async {
    if (touch) s.modified = DateTime.now();
    _songs[s.id] = s;
    await _songStore.record(s.id).put(_db, s.toJson());
    notifyListeners();
  }

  Future<void> deleteSongs(Iterable<String> ids) async {
    final gone = ids.toSet();
    await _db.transaction((txn) async {
      for (final id in gone) {
        _songs.remove(id);
        await _songStore.record(id).delete(txn);
      }
      for (final set in _sets.values) {
        final before = set.items.length;
        set.items.removeWhere((i) => i.type == SetItemType.song && gone.contains(i.songId));
        if (set.items.length != before) await _setStore.record(set.id).put(txn, set.toJson());
      }
    });
    if (gone.contains(songId)) songId = null;
    if (currentSet != null && setIndex >= currentSet!.items.length) setIndex = currentSet!.items.length - 1;
    notifyListeners();
  }

  Future<void> saveSet(SongSet s) async {
    s.modified = DateTime.now();
    _sets[s.id] = s;
    await _setStore.record(s.id).put(_db, s.toJson());
    notifyListeners();
  }

  Future<void> deleteSet(String id) async {
    _sets.remove(id);
    await _setStore.record(id).delete(_db);
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

  Future<void> saveFolder(Folder f) async {
    _folders[f.id] = f;
    await _folderStore.record(f.id).put(_db, f.toJson());
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    _folders.remove(id);
    await _db.transaction((txn) async {
      await _folderStore.record(id).delete(txn);
      for (final s in _songs.values.where((s) => s.folderIds.contains(id))) {
        s.folderIds.remove(id);
        await _songStore.record(s.id).put(txn, s.toJson());
      }
    });
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await _prefs.record('settings').put(_db, settings.toJson());
    notifyListeners();
  }

  // ---- backup ------------------------------------------------------------

  Map<String, Object?> exportBackup() => {
        'app': 'WorshipStudio',
        'version': 1,
        'exported': DateTime.now().toIso8601String(),
        'songs': [for (final s in _songs.values) s.toJson()],
        'sets': [for (final s in _sets.values) s.toJson()],
        'folders': [for (final f in _folders.values) f.toJson()],
      };

  /// Merges a backup into the library; items with the same id are replaced.
  Future<({int songs, int sets})> importBackup(Map<String, Object?> data) async {
    List<Map<String, Object?>> maps(String key) =>
        [for (final e in (data[key] as List? ?? const [])) Map<String, Object?>.from(e as Map)];
    final songs = maps('songs').map(Song.fromJson).toList();
    final sets = maps('sets').map(SongSet.fromJson).toList();
    final folders = maps('folders').map(Folder.fromJson).toList();
    await _db.transaction((txn) async {
      for (final f in folders) {
        _folders[f.id] = f;
        await _folderStore.record(f.id).put(txn, f.toJson());
      }
      for (final s in songs) {
        _songs[s.id] = s;
        await _songStore.record(s.id).put(txn, s.toJson());
      }
      for (final s in sets) {
        _sets[s.id] = s;
        await _setStore.record(s.id).put(txn, s.toJson());
      }
    });
    notifyListeners();
    return (songs: songs.length, sets: sets.length);
  }

  Future<void> resetLibrary() async {
    await _db.transaction((txn) async {
      await _songStore.delete(txn);
      await _setStore.delete(txn);
      await _folderStore.delete(txn);
    });
    _songs.clear();
    _sets.clear();
    _folders.clear();
    songId = null;
    setId = null;
    setIndex = -1;
    notifyListeners();
  }
}
