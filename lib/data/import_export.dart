import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models.dart';
import '../music/chordpro.dart';
import '../music/transpose.dart';

const songExtensions = ['cho', 'crd', 'chordpro', 'chopro', 'chord', 'pro', 'txt', 'onsong'];
const backupExtensions = ['json', 'wsbackup', 'sbp', 'sbpbackup'];

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _baseName(String name) {
  final slash = name.lastIndexOf(RegExp(r'[\\/]'));
  final file = name.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  return dot <= 0 ? file : file.substring(0, dot);
}

String decodeText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes(bytes.buffer.asUint16List(bytes.offsetInBytes + 2, (bytes.length - 2) ~/ 2));
  }
  try {
    final s = utf8.decode(bytes);
    return s.startsWith('﻿') ? s.substring(1) : s;
  } on FormatException {
    return latin1.decode(bytes);
  }
}

int _seconds(String v) {
  final parts = v.split(':').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  return parts.fold(0, (acc, p) => acc * 60 + p);
}

final _headerRe = RegExp(r'^(key|tempo|bpm|time|capo|duration|copyright|ccli|artist)\s*:\s*(.+)$', caseSensitive: false);

/// Builds a song from a text file. OnSong-style headers (title on the first
/// line, artist on the second, then `Key: G` lines) are folded into
/// ChordPro directives first.
Song songFromText(String text, String fileName) {
  var content = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (_ext(fileName) == 'onsong' && !RegExp(r'\{\s*(t|title)\s*:').hasMatch(content)) {
    final lines = content.split('\n');
    final head = <String>[];
    var i = 0;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    var n = 0;
    for (; i < lines.length && lines[i].trim().isNotEmpty; i++, n++) {
      final line = lines[i].trim();
      final m = _headerRe.firstMatch(line);
      if (m != null) {
        final name = m.group(1)!.toLowerCase();
        head.add('{${name == 'bpm' ? 'tempo' : name}: ${m.group(2)!.trim()}}');
      } else if (n == 0) {
        head.add('{title: $line}');
      } else if (n == 1) {
        head.add('{artist: $line}');
      } else {
        break;
      }
    }
    content = [...head, '', ...lines.skip(i)].join('\n');
  }
  final doc = parseChordPro(content);
  final m = doc.meta;
  final key = parseKey(m['key'])?.name ?? detectKey(doc.chords.toList()) ?? '';
  return Song(
    title: (m['title'] ?? '').isNotEmpty ? m['title']! : _baseName(fileName),
    subtitle: m['subtitle'] ?? '',
    artist: m['artist'] ?? m['composer'] ?? '',
    key: key,
    capo: int.tryParse(m['capo'] ?? '') ?? 0,
    tempo: int.tryParse(RegExp(r'\d+').firstMatch(m['tempo'] ?? '')?.group(0) ?? '') ?? 0,
    timeSig: m['time'] ?? '',
    duration: m['duration'] == null ? 0 : _seconds(m['duration']!),
    copyright: m['copyright'] ?? '',
    songNumber: int.tryParse(m['number'] ?? '') ?? 0,
    content: content.trim(),
  );
}

/// ChordPro text for [song], with its metadata written as directives when
/// the content does not already carry them.
String songToChordPro(Song song) {
  final meta = parseChordPro(song.content).meta;
  final head = <String>[
    if (!meta.containsKey('title') && song.title.isNotEmpty) '{title: ${song.title}}',
    if (!meta.containsKey('subtitle') && song.subtitle.isNotEmpty) '{subtitle: ${song.subtitle}}',
    if (!meta.containsKey('artist') && song.artist.isNotEmpty) '{artist: ${song.artist}}',
    if (!meta.containsKey('key') && song.key.isNotEmpty) '{key: ${song.key}}',
    if (!meta.containsKey('capo') && song.capo > 0) '{capo: ${song.capo}}',
    if (!meta.containsKey('tempo') && song.tempo > 0) '{tempo: ${song.tempo}}',
    if (!meta.containsKey('time') && song.timeSig.isNotEmpty) '{time: ${song.timeSig}}',
    if (!meta.containsKey('copyright') && song.copyright.isNotEmpty) '{copyright: ${song.copyright}}',
  ];
  return [...head, if (head.isNotEmpty) '', chordsOverLyricsToChordPro(song.content).trim(), ''].join('\n');
}

String safeFileName(String name) {
  final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
  return clean.isEmpty ? 'song' : clean;
}

/// Reads a backup file into the WorshipStudio backup shape.
/// Accepts our own JSON and, best effort, SongbookPro `.sbp` archives.
Map<String, Object?> readBackup(Uint8List bytes, String fileName) {
  final ext = _ext(fileName);
  final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (!isZip && (ext == 'json' || ext == 'wsbackup')) {
    final data = jsonDecode(decodeText(bytes));
    if (data is! Map || data['songs'] is! List) throw const FormatException('Not a backup file');
    return Map<String, Object?>.from(data);
  }
  if (!isZip) throw const FormatException('Unsupported backup file');
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('datafile.txt')).firstOrNull;
  if (entry == null) throw const FormatException('dataFile.txt not found in archive');
  final text = decodeText(entry.content);
  final start = text.indexOf('{');
  if (start < 0) throw const FormatException('No data in archive');
  return _fromSongbookPro(Map<String, Object?>.from(jsonDecode(text.substring(start)) as Map));
}

/// Case-insensitive field lookup; SongbookPro mixes `Id`, `name`, `KeyShift`…
Object? _f(Map m, String name) {
  if (m.containsKey(name)) return m[name];
  final lower = name.toLowerCase();
  for (final e in m.entries) {
    if (e.key.toString().toLowerCase() == lower) return e.value;
  }
  return null;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';

List<String> _stringList(Object? v) {
  if (v is String && v.trim().startsWith('[')) {
    try {
      v = jsonDecode(v);
    } on FormatException {
      return [];
    }
  }
  return v is List ? [for (final e in v) '$e'] : [];
}

/// SongbookPro key enum: 0 = A … 11 = Ab (major), 12 = F#m … 15 = Am … 23 = Fm.
String _sbpKey(int value) {
  if (value < 0 || value > 23) return '';
  if (value < 12) return majorKeys[(value + 9) % 12];
  return minorKeys[(value - 15 + 9 + 12) % 12];
}

Map<String, Object?> _fromSongbookPro(Map<String, Object?> data) {
  List<Map> list(String key) => [for (final e in (_f(data, key) as List? ?? const [])) if (e is Map) e];
  final songs = <Song>[];
  final songIds = <String, String>{};
  final folderIds = <String, String>{};
  final folders = <Folder>[];
  for (final f in list('folders')) {
    if (_int(_f(f, 'Deleted')) != 0) continue;
    final folder = Folder(name: _str(_f(f, 'Name')), order: _int(_f(f, 'Order')));
    folderIds[_str(_f(f, 'Id'))] = folder.id;
    folders.add(folder);
  }
  for (final s in list('songs')) {
    if (_int(_f(s, 'Deleted')) != 0) continue;
    final content = _str(_f(s, 'content'));
    // type 1 is a ChordPro song; PDF / image songs carry no text.
    if (_int(_f(s, 'type')) != 1 && content.trim().isEmpty) continue;
    final song = Song(
      title: _str(_f(s, 'name')),
      subtitle: _str(_f(s, 'subTitle')),
      artist: _str(_f(s, 'author')),
      key: _sbpKey(_int(_f(s, 'key'))),
      capo: _int(_f(s, 'Capo')),
      transpose: _int(_f(s, 'KeyShift')),
      tempo: _int(_f(s, 'TempoInt')),
      timeSig: _str(_f(s, 'timeSig')),
      duration: _int(_f(s, 'Duration2')) > 0 ? _int(_f(s, 'Duration2')) : _int(_f(s, 'Duration')),
      content: content,
      tags: _stringList(_f(s, '_tags')),
      folderIds: [
        for (final id in _stringList(_f(s, '_folders'))) ?folderIds[id]
      ],
      copyright: _str(_f(s, 'Copyright')),
      url: _str(_f(s, 'Url')),
      notes: _str(_f(s, 'NotesText')),
      sectionOrder: _str(_f(s, 'SectionOrder')),
      songNumber: _int(_f(s, 'SongNumber')),
    );
    songIds[_str(_f(s, 'Id'))] = song.id;
    songs.add(song);
  }
  final sets = <SongSet>[];
  for (final s in list('sets')) {
    if (_int(_f(s, 'Deleted')) != 0) continue;
    final details = _f(s, 'details') is Map ? _f(s, 'details') as Map : s;
    final items = <(int, SetItem)>[];
    for (final i in (_f(s, 'contents') as List? ?? _f(s, 'items') as List? ?? const [])) {
      if (i is! Map || _int(_f(i, 'Deleted')) != 0) continue;
      final songId = songIds[_str(_f(i, 'SongId'))];
      final isSong = _f(i, 'ItemType') == null || _int(_f(i, 'ItemType')) == 1;
      if (isSong && songId == null) continue;
      items.add((
        _int(_f(i, 'Order')),
        isSong
            ? SetItem(
                songId: songId!,
                transpose: _f(i, 'keyOfset') == null ? null : _int(_f(i, 'keyOfset')),
                capo: _f(i, 'Capo') == null ? null : _int(_f(i, 'Capo')),
                text: _str(_f(i, 'NotesText')),
                sectionOrder: _str(_f(i, 'SectionOrder')),
              )
            : SetItem(type: SetItemType.note, title: 'Note', text: _str(_f(i, 'NotesText'))),
      ));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    sets.add(SongSet(
      name: _str(_f(details, 'name')),
      date: DateTime.tryParse(_str(_f(details, 'date'))),
      pinned: _int(_f(details, 'pinned')) != 0,
      items: [for (final i in items) i.$2],
    ));
  }
  return {
    'songs': [for (final s in songs) s.toJson()],
    'sets': [for (final s in sets) s.toJson()],
    'folders': [for (final f in folders) f.toJson()],
  };
}
