/// ChordPro parser. Also accepts plain "chords over lyrics" text and
/// bare section headings such as `Verse 1:` or `[Chorus]`.
library;

import 'dart:math';

import 'transpose.dart';

enum SectionType { verse, chorus, bridge, prechorus, intro, outro, interlude, tag, tab, grid, other }

class Segment {
  final String? chord;
  final String lyric;
  const Segment(this.chord, this.lyric);
}

sealed class Line {
  const Line();
}

class LyricLine extends Line {
  final List<Segment> segments;
  const LyricLine(this.segments);

  bool get hasChords => segments.any((s) => s.chord != null);
  bool get hasLyrics => segments.any((s) => s.lyric.trim().isNotEmpty);
  String get lyrics => segments.map((s) => s.lyric).join();
}

enum CommentStyle { normal, italic, box }

class CommentLine extends Line {
  final String text;
  final CommentStyle style;
  const CommentLine(this.text, this.style);
}

/// Preformatted line (tab / grid), rendered monospaced.
class RawLine extends Line {
  final String text;
  const RawLine(this.text);
}

class EmptyLine extends Line {
  const EmptyLine();
}

class Section {
  final SectionType type;
  final String label;
  final List<Line> lines = [];
  Section(this.type, this.label);

  /// Number in the label (`Verse 2` -> 2), if any.
  int? get number {
    final m = RegExp(r'(\d+)').firstMatch(label);
    return m == null ? null : int.parse(m.group(1)!);
  }

  bool get isEmpty => lines.every((l) => l is EmptyLine);
}

class SongDoc {
  final Map<String, String> meta = {};
  final List<Section> sections = [];

  String? get title => meta['title'];

  Iterable<String> get chords sync* {
    for (final s in sections) {
      for (final l in s.lines) {
        if (l is LyricLine) {
          for (final seg in l.segments) {
            if (seg.chord != null) yield seg.chord!;
          }
        }
      }
    }
  }
}

const _aliases = {
  't': 'title',
  'st': 'subtitle',
  'c': 'comment',
  'ci': 'comment_italic',
  'cb': 'comment_box',
  'soc': 'start_of_chorus',
  'eoc': 'end_of_chorus',
  'sov': 'start_of_verse',
  'eov': 'end_of_verse',
  'sob': 'start_of_bridge',
  'eob': 'end_of_bridge',
  'sot': 'start_of_tab',
  'eot': 'end_of_tab',
  'sog': 'start_of_grid',
  'eog': 'end_of_grid',
};

const _metaKeys = {
  'title', 'subtitle', 'artist', 'composer', 'lyricist', 'copyright', 'album',
  'year', 'key', 'time', 'tempo', 'duration', 'capo', 'ccli', 'number', //
};

const _sectionNames = <String, SectionType>{
  'verse': SectionType.verse,
  'strofa': SectionType.verse,
  'chorus': SectionType.chorus,
  'refrain': SectionType.chorus,
  'ritornello': SectionType.chorus,
  'rit': SectionType.chorus,
  'coro': SectionType.chorus,
  'bridge': SectionType.bridge,
  'ponte': SectionType.bridge,
  'special': SectionType.bridge,
  'pre-chorus': SectionType.prechorus,
  'prechorus': SectionType.prechorus,
  'pre chorus': SectionType.prechorus,
  'pre-ritornello': SectionType.prechorus,
  'intro': SectionType.intro,
  'outro': SectionType.outro,
  'ending': SectionType.outro,
  'finale': SectionType.outro,
  'coda': SectionType.outro,
  'interlude': SectionType.interlude,
  'instrumental': SectionType.interlude,
  'strumentale': SectionType.interlude,
  'interludio': SectionType.interlude,
  'solo': SectionType.interlude,
  'turnaround': SectionType.interlude,
  'tag': SectionType.tag,
  'vamp': SectionType.tag,
};

final _directiveRe = RegExp(r'^\s*\{\s*([^:}\s]+)\s*(?::\s*(.*?))?\s*\}\s*$');
final _headingRe = RegExp(r'^\s*\[?\s*([A-Za-zÀ-ÿ\- ]+?)\s*(\d+)?\s*\]?\s*:?\s*$');
final _chordTokenRe = RegExp(r'\S+');

(SectionType, String)? _heading(String line) {
  if (line.length > 30) return null;
  final m = _headingRe.firstMatch(line);
  if (m == null) return null;
  final type = _sectionNames[m.group(1)!.toLowerCase()];
  if (type == null) return null;
  // A bare word needs a bracket, colon or number to count as a heading,
  // unless it stands alone on the line (it always does here).
  final label = [m.group(1)!.trim(), if (m.group(2) != null) m.group(2)!].join(' ');
  return (type, label);
}

/// True when every token on the line is a chord (or bar / repeat mark).
bool isChordLine(String line) {
  final tokens = _chordTokenRe.allMatches(line).map((m) => m.group(0)!).toList();
  if (tokens.isEmpty) return false;
  var chords = 0;
  for (final t in tokens) {
    if (isChord(t)) {
      chords++;
    } else if (!RegExp(r'^(\||/|%|-|x\d+|\(?N\.?C\.?\)?|\d+x)$', caseSensitive: false).hasMatch(t)) {
      return false;
    }
  }
  return chords > 0;
}

/// Merges a chord line and the lyric line beneath it into ChordPro.
String mergeChordLine(String chordLine, String lyricLine) {
  final lyric = lyricLine.padRight(chordLine.length);
  final out = StringBuffer();
  var pos = 0;
  for (final m in _chordTokenRe.allMatches(chordLine)) {
    out.write(lyric.substring(pos, m.start));
    out.write('[${m.group(0)}]');
    pos = m.start;
  }
  out.write(lyric.substring(pos));
  return out.toString().trimRight();
}

/// Whether [line] opens (true) or closes (false) a tab / grid block.
bool? _rawBlock(String line) {
  final d = _directiveRe.firstMatch(line);
  if (d == null) return null;
  final name = d.group(1)!.toLowerCase();
  return switch (_aliases[name] ?? name) {
    'start_of_tab' || 'start_of_grid' => true,
    'end_of_tab' || 'end_of_grid' => false,
    _ => null,
  };
}

/// Whether [line], sitting under a chord line, is the lyric it belongs to.
bool _isLyricUnderChords(String line) =>
    line.trim().isNotEmpty &&
    !isChordLine(line) &&
    !line.trimLeft().startsWith('{') &&
    _heading(line) == null;

/// Converts "chords over lyrics" text to ChordPro. ChordPro input is
/// returned unchanged apart from chord-only lines being bracketed.
String chordsOverLyricsToChordPro(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var raw = false; // inside a tab / grid block
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    raw = _rawBlock(line) ?? raw;
    if (!raw && !line.contains('[') && !line.trimLeft().startsWith('{') && isChordLine(line)) {
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      final nextIsLyric = _isLyricUnderChords(next);
      if (nextIsLyric) {
        out.add(mergeChordLine(line, next));
        i++;
      } else {
        out.add(mergeChordLine(line, ''));
      }
    } else {
      out.add(line);
    }
  }
  return out.join('\n');
}

/// Splits a ChordPro line into the chord line and the lyric line beneath
/// it. Returns null when the line cannot be laid out without changing it.
(String, String)? _splitChordLine(String line) {
  final chords = StringBuffer();
  final lyric = StringBuffer();
  for (final seg in _parseLyricLine(line)) {
    final chord = seg.chord;
    if (chord != null) {
      if (chord.isEmpty || chord.contains(RegExp(r'\s'))) return null;
      // Keep one space between chords that sit closer than their width.
      final col = chords.isEmpty ? lyric.length : max(lyric.length, chords.length + 1);
      if (col > lyric.length) {
        // Padding in the middle of a word would change the lyrics.
        final sung = lyric.toString();
        final midWord = sung.isNotEmpty && !sung.endsWith(' ') && seg.lyric.isNotEmpty && !seg.lyric.startsWith(' ');
        if (midWord) return null;
        lyric.write(' ' * (col - lyric.length));
      }
      chords.write(' ' * (col - chords.length));
      chords.write(chord);
    }
    lyric.write(seg.lyric);
  }
  return (chords.toString(), lyric.toString().trimRight());
}

/// Converts ChordPro to "chords over lyrics" text: a line carrying
/// `[chords]` becomes a chord line and the lyric line beneath it.
/// Lines that would not convert back to the same thing stay in ChordPro.
String chordProToChordsOverLyrics(String text) {
  final lines = chordsOverLyricsToChordPro(text).split('\n');
  final out = <String>[];
  var raw = false; // inside a tab / grid block
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    raw = _rawBlock(line) ?? raw;
    final split = raw || !line.contains('[') || line.trimLeft().startsWith(RegExp(r'[{#]'))
        ? null
        : _splitChordLine(line);
    if (split == null || !isChordLine(split.$1)) {
      out.add(line);
      continue;
    }
    final (chords, lyric) = split;
    if (lyric.trim().isEmpty) {
      // A bare chord line would swallow a plain lyric line following it.
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      out.add(!next.contains('[') && _isLyricUnderChords(next) ? line : chords);
    } else if (_isLyricUnderChords(lyric)) {
      out
        ..add(chords)
        ..add(lyric);
    } else {
      out.add(line);
    }
  }
  return out.join('\n');
}

List<Segment> _parseLyricLine(String line) {
  final segs = <Segment>[];
  final re = RegExp(r'\[([^\]]*)\]');
  var pos = 0;
  String? chord;
  for (final m in re.allMatches(line)) {
    final before = line.substring(pos, m.start);
    if (before.isNotEmpty || chord != null) segs.add(Segment(chord, before));
    chord = m.group(1)!.trim();
    pos = m.end;
  }
  final rest = line.substring(pos);
  if (rest.isNotEmpty || chord != null) segs.add(Segment(chord, rest));
  return segs;
}

SongDoc parseChordPro(String source) {
  final doc = SongDoc();
  final lines = chordsOverLyricsToChordPro(source).split('\n');
  Section? current;
  var explicit = false; // inside {start_of_x} … {end_of_x}
  var hidden = false; // inside {x_sbp_hide} … {x_sbp_show}

  void close() {
    final c = current;
    if (c != null) {
      while (c.lines.isNotEmpty && c.lines.last is EmptyLine) {
        c.lines.removeLast();
      }
      if (c.lines.isNotEmpty || c.label.isNotEmpty) doc.sections.add(c);
    }
    current = null;
    explicit = false;
  }

  Section open(SectionType type, String label) {
    close();
    return current = Section(type, label);
  }

  Section ensure() => current ??= Section(SectionType.other, '');

  for (final raw in lines) {
    final line = raw.trimRight();
    final d = _directiveRe.firstMatch(line);
    if (d != null) {
      var name = d.group(1)!.toLowerCase();
      name = _aliases[name] ?? name;
      var value = d.group(2) ?? '';
      if (name == 'x_sbp_hide') {
        hidden = true;
      } else if (name == 'x_sbp_show') {
        hidden = false;
      } else if (name == 'meta') {
        final sp = value.indexOf(' ');
        if (sp > 0) doc.meta[value.substring(0, sp).toLowerCase()] = value.substring(sp + 1).trim();
      } else if (_metaKeys.contains(name)) {
        doc.meta.putIfAbsent(name, () => value);
      } else if (name.startsWith('start_of_')) {
        final kind = name.substring(9);
        final lm = RegExp(r'label\s*=\s*"([^"]*)"').firstMatch(value);
        if (lm != null) value = lm.group(1)!;
        final type = switch (kind) {
          'verse' => SectionType.verse,
          'chorus' => SectionType.chorus,
          'bridge' => SectionType.bridge,
          'tab' => SectionType.tab,
          'grid' => SectionType.grid,
          _ => _sectionNames[kind] ?? SectionType.other,
        };
        final label = value.isNotEmpty
            ? value
            : switch (type) {
                SectionType.tab || SectionType.grid => '',
                _ => kind[0].toUpperCase() + kind.substring(1),
              };
        open(type, label);
        explicit = true;
      } else if (name.startsWith('end_of_')) {
        close();
      } else if (name == 'chorus') {
        // Recall of the chorus: show a marker.
        if (!hidden) {
          open(SectionType.chorus, value.isEmpty ? 'Chorus' : value);
          close();
        }
      } else if (name.startsWith('comment') || name == 'highlight') {
        if (!hidden) {
          // A comment that names a section starts that section.
          final h = current == null || !explicit ? _heading(value) : null;
          if (h != null) {
            open(h.$1, h.$2);
          } else {
            ensure().lines.add(CommentLine(
                value,
                switch (name) {
                  'comment_italic' => CommentStyle.italic,
                  'comment_box' => CommentStyle.box,
                  _ => CommentStyle.normal,
                }));
          }
        }
      }
      continue; // unknown directives are ignored
    }
    if (hidden) continue;
    if (line.trimLeft().startsWith('#')) continue;

    final inRaw = current != null &&
        explicit &&
        (current!.type == SectionType.tab || current!.type == SectionType.grid);
    if (inRaw) {
      current!.lines.add(RawLine(line));
      continue;
    }
    if (line.trim().isEmpty) {
      if (explicit) {
        current!.lines.add(const EmptyLine());
      } else {
        close();
      }
      continue;
    }
    if (!explicit) {
      final h = _heading(line);
      // `[Am]` alone is a chord, not a heading.
      final bracketed = line.trim().startsWith('[') && line.trim().endsWith(']');
      final inner = bracketed ? line.trim().substring(1, line.trim().length - 1) : '';
      if (h != null && !(bracketed && isChord(inner))) {
        open(h.$1, h.$2);
        continue;
      }
    }
    // Tab-looking lines (e|---3---|) stay monospaced.
    if (RegExp(r'^[A-Ga-g]?[#b]?\s*\|?[-0-9|hpbr/\\~x().\s]{8,}$').hasMatch(line) &&
        line.contains('--')) {
      ensure().lines.add(RawLine(line));
      continue;
    }
    ensure().lines.add(LyricLine(_parseLyricLine(line)));
  }
  close();
  return doc;
}

const _typeCodes = {
  'V': SectionType.verse,
  'C': SectionType.chorus,
  'B': SectionType.bridge,
  'P': SectionType.prechorus,
  'PC': SectionType.prechorus,
  'I': SectionType.intro,
  'O': SectionType.outro,
  'E': SectionType.outro,
  'IL': SectionType.interlude,
  'IN': SectionType.interlude,
  'T': SectionType.tag,
};

/// Reorders sections according to a spec such as `V1 C1 V2 C1 B1 C1`.
/// Unknown tokens are skipped; an empty or fully unmatched spec leaves the
/// song untouched.
List<Section> applySectionOrder(List<Section> sections, String order) {
  final tokens = order.trim().split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty);
  final result = <Section>[];
  for (final token in tokens) {
    final m = RegExp(r'^([A-Za-z]+)(\d+)?$').firstMatch(token);
    if (m == null) continue;
    final type = _typeCodes[m.group(1)!.toUpperCase()];
    if (type == null) continue;
    final n = m.group(2) == null ? null : int.parse(m.group(2)!);
    final ofType = sections.where((s) => s.type == type && !s.isEmpty).toList();
    if (ofType.isEmpty) continue;
    Section? match;
    if (n == null) {
      match = ofType.first;
    } else {
      match = ofType.where((s) => s.number == n).firstOrNull;
      // Unnumbered sections are addressed by position.
      match ??= ofType.every((s) => s.number == null) && n <= ofType.length ? ofType[n - 1] : null;
    }
    if (match != null) result.add(match);
  }
  return result.isEmpty ? sections : result;
}

/// Short code for a section (`Verse 2` -> `V2`), used to build section orders.
String sectionCode(Section s, List<Section> all) {
  final letter = switch (s.type) {
    SectionType.verse => 'V',
    SectionType.chorus => 'C',
    SectionType.bridge => 'B',
    SectionType.prechorus => 'P',
    SectionType.intro => 'I',
    SectionType.outro => 'O',
    SectionType.interlude => 'IL',
    SectionType.tag => 'T',
    _ => '',
  };
  if (letter.isEmpty) return '';
  final same = all.where((x) => x.type == s.type && !x.isEmpty).toList();
  final n = s.number ?? (same.every((x) => x.number == null) ? same.indexOf(s) + 1 : null);
  return n == null ? letter : '$letter$n';
}
