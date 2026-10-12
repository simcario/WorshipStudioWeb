import 'dart:math';

import 'music/transpose.dart';

final _rnd = Random();

/// Short random id, unique enough for a personal library.
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _rnd.nextInt(0x7fffffff).toRadixString(36).padLeft(7, '0');
  return '$t$r';
}

List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) e.toString()];

class Song {
  final String id;
  String title;
  String subtitle;
  String artist;
  String key; // '' when not set
  int capo;
  int transpose; // semitones applied on top of the written key
  int tempo; // bpm, 0 when not set
  String timeSig;
  int duration; // seconds, 0 when not set
  String content; // ChordPro, or chords over lyrics
  List<String> tags;
  List<String> folderIds;
  String copyright;
  String url;
  String notes;
  String sectionOrder;
  int songNumber;
  double zoom;
  DateTime modified;

  Song({
    String? id,
    this.title = '',
    this.subtitle = '',
    this.artist = '',
    this.key = '',
    this.capo = 0,
    this.transpose = 0,
    this.tempo = 0,
    this.timeSig = '',
    this.duration = 0,
    this.content = '',
    List<String>? tags,
    List<String>? folderIds,
    this.copyright = '',
    this.url = '',
    this.notes = '',
    this.sectionOrder = '',
    this.songNumber = 0,
    this.zoom = 1,
    DateTime? modified,
  })  : id = id ?? newId(),
        tags = tags ?? [],
        folderIds = folderIds ?? [],
        modified = modified ?? DateTime.now();

  factory Song.fromJson(Map<String, Object?> j) => Song(
        id: j['id'] as String?,
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        key: j['key'] as String? ?? '',
        capo: (j['capo'] as num?)?.toInt() ?? 0,
        transpose: (j['transpose'] as num?)?.toInt() ?? 0,
        tempo: (j['tempo'] as num?)?.toInt() ?? 0,
        timeSig: j['timeSig'] as String? ?? '',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        content: j['content'] as String? ?? '',
        tags: _strings(j['tags']),
        folderIds: _strings(j['folderIds']),
        copyright: j['copyright'] as String? ?? '',
        url: j['url'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        sectionOrder: j['sectionOrder'] as String? ?? '',
        songNumber: (j['songNumber'] as num?)?.toInt() ?? 0,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 1,
        modified: DateTime.tryParse(j['modified'] as String? ?? ''),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'artist': artist,
        'key': key,
        'capo': capo,
        'transpose': transpose,
        'tempo': tempo,
        'timeSig': timeSig,
        'duration': duration,
        'content': content,
        'tags': tags,
        'folderIds': folderIds,
        'copyright': copyright,
        'url': url,
        'notes': notes,
        'sectionOrder': sectionOrder,
        'songNumber': songNumber,
        'zoom': zoom,
        'modified': modified.toIso8601String(),
      };

  Song copy() => Song.fromJson(toJson());
}

enum SetItemType { song, note }

class SetItem {
  final String id;
  SetItemType type;
  String songId;
  int? transpose; // overrides the song's own value inside this set
  int? capo;
  String title; // for notes
  String text; // note body, or per-set notes on a song
  String sectionOrder;

  SetItem({
    String? id,
    this.type = SetItemType.song,
    this.songId = '',
    this.transpose,
    this.capo,
    this.title = '',
    this.text = '',
    this.sectionOrder = '',
  }) : id = id ?? newId();

  factory SetItem.fromJson(Map<String, Object?> j) => SetItem(
        id: j['id'] as String?,
        type: j['type'] == 'note' ? SetItemType.note : SetItemType.song,
        songId: j['songId'] as String? ?? '',
        transpose: (j['transpose'] as num?)?.toInt(),
        capo: (j['capo'] as num?)?.toInt(),
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        sectionOrder: j['sectionOrder'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'songId': songId,
        'transpose': transpose,
        'capo': capo,
        'title': title,
        'text': text,
        'sectionOrder': sectionOrder,
      };
}

class SongSet {
  final String id;
  String name;
  DateTime date;
  bool pinned;
  List<SetItem> items;
  DateTime modified;

  SongSet({String? id, this.name = '', DateTime? date, this.pinned = false, List<SetItem>? items, DateTime? modified})
      : id = id ?? newId(),
        date = date ?? DateTime.now(),
        items = items ?? [],
        modified = modified ?? DateTime.now();

  factory SongSet.fromJson(Map<String, Object?> j) => SongSet(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        pinned: j['pinned'] == true,
        items: [
          for (final i in (j['items'] as List? ?? const []))
            SetItem.fromJson(Map<String, Object?>.from(i as Map))
        ],
        modified: DateTime.tryParse(j['modified'] as String? ?? ''),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'date': date.toIso8601String(),
        'pinned': pinned,
        'items': [for (final i in items) i.toJson()],
        'modified': modified.toIso8601String(),
      };
}

class Folder {
  final String id;
  String name;
  int order;
  Folder({String? id, this.name = '', this.order = 0}) : id = id ?? newId();

  factory Folder.fromJson(Map<String, Object?> j) =>
      Folder(id: j['id'] as String?, name: j['name'] as String? ?? '', order: (j['order'] as num?)?.toInt() ?? 0);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'order': order};
}

enum SongSort { title, artist, modified, number }

enum ChordSize { small, normal, large }

class AppSettings {
  String themeMode = 'system'; // system | light | dark
  int accent = 0xFF3F6FD9;
  String locale = 'it';
  double fontSize = 18;
  bool showChords = true;
  ChordSize chordSize = ChordSize.normal;
  int chordColorLight = 0xFFB3261E;
  int chordColorDark = 0xFFFFB4A8;
  bool boldChords = true;
  bool showHeaders = true;
  bool monoLyrics = false;
  Notation notation = Notation.standard;
  int autoscrollSeconds = 180;
  int autoscrollDelay = 3;
  bool metronomeSound = true;
  bool keepAwake = true;
  bool numberSetItems = true;
  SongSort sort = SongSort.title;
  bool chordsOverLyrics = false; // editor writes chords on the line above, not inline

  AppSettings();

  factory AppSettings.fromJson(Map<String, Object?> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    final s = AppSettings();
    return s
      ..themeMode = j['themeMode'] as String? ?? s.themeMode
      ..accent = (j['accent'] as num?)?.toInt() ?? s.accent
      ..locale = j['locale'] as String? ?? s.locale
      ..fontSize = (j['fontSize'] as num?)?.toDouble() ?? s.fontSize
      ..showChords = j['showChords'] as bool? ?? s.showChords
      ..chordSize = pick(ChordSize.values, j['chordSize'], s.chordSize)
      ..chordColorLight = (j['chordColorLight'] as num?)?.toInt() ?? s.chordColorLight
      ..chordColorDark = (j['chordColorDark'] as num?)?.toInt() ?? s.chordColorDark
      ..boldChords = j['boldChords'] as bool? ?? s.boldChords
      ..showHeaders = j['showHeaders'] as bool? ?? s.showHeaders
      ..monoLyrics = j['monoLyrics'] as bool? ?? s.monoLyrics
      ..notation = pick(Notation.values, j['notation'], s.notation)
      ..autoscrollSeconds = (j['autoscrollSeconds'] as num?)?.toInt() ?? s.autoscrollSeconds
      ..autoscrollDelay = (j['autoscrollDelay'] as num?)?.toInt() ?? s.autoscrollDelay
      ..metronomeSound = j['metronomeSound'] as bool? ?? s.metronomeSound
      ..keepAwake = j['keepAwake'] as bool? ?? s.keepAwake
      ..numberSetItems = j['numberSetItems'] as bool? ?? s.numberSetItems
      ..sort = pick(SongSort.values, j['sort'], s.sort)
      ..chordsOverLyrics = j['chordsOverLyrics'] as bool? ?? s.chordsOverLyrics;
  }

  Map<String, Object?> toJson() => {
        'themeMode': themeMode,
        'accent': accent,
        'locale': locale,
        'fontSize': fontSize,
        'showChords': showChords,
        'chordSize': chordSize.name,
        'chordColorLight': chordColorLight,
        'chordColorDark': chordColorDark,
        'boldChords': boldChords,
        'showHeaders': showHeaders,
        'monoLyrics': monoLyrics,
        'notation': notation.name,
        'autoscrollSeconds': autoscrollSeconds,
        'autoscrollDelay': autoscrollDelay,
        'metronomeSound': metronomeSound,
        'keepAwake': keepAwake,
        'numberSetItems': numberSetItems,
        'sort': sort.name,
        'chordsOverLyrics': chordsOverLyrics,
      };
}
