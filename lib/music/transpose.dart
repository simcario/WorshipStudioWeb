/// Chord parsing, transposition, notation conversion and key detection.
library;

const _sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const _flat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

/// Conventional spelling of each major / minor key, indexed by pitch class.
const majorKeys = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const minorKeys = ['Cm', 'C#m', 'Dm', 'D#m', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'Bbm', 'Bm'];

/// Every key offered in pickers.
const allKeys = [...majorKeys, ...minorKeys];

enum Notation { standard, latin, german, nashville }

const _latin = {'C': 'Do', 'D': 'Re', 'E': 'Mi', 'F': 'Fa', 'G': 'Sol', 'A': 'La', 'B': 'Si'};
const _nashville = ['1', 'b2', '2', 'b3', '3', '4', 'b5', '5', 'b6', '6', 'b7', '7'];

final _chordRe = RegExp(r'^([A-G](?:#|b)?)([^/]*)(?:/([A-G](?:#|b)?))?$');
final _qualityRe = RegExp(
    r'^(?:m|min|maj|M|dim|aug|sus|add|\+|-|°|ø|Δ|[0-9]|#|b|\(|\)|,|no|omit|alt)*$');

/// Pitch class (0 = C) of a note name such as `F#` or `Bb`, or null.
int? noteIndex(String note) {
  final s = _sharp.indexOf(note);
  if (s >= 0) return s;
  final f = _flat.indexOf(note);
  if (f >= 0) return f;
  return switch (note) { 'Cb' => 11, 'B#' => 0, 'E#' => 5, 'Fb' => 4, _ => null };
}

class ParsedChord {
  final String root;
  final String quality;
  final String? bass;
  const ParsedChord(this.root, this.quality, this.bass);

  bool get isMinor =>
      quality.startsWith('m') && !quality.startsWith('maj') || quality.startsWith('-');
}

/// Parses a chord symbol. Returns null for anything that is not a chord
/// (`N.C.`, `|`, `x4`, plain words…).
ParsedChord? parseChord(String text) {
  final m = _chordRe.firstMatch(text.trim());
  if (m == null) return null;
  final quality = m.group(2)!;
  if (!_qualityRe.hasMatch(quality)) return null;
  return ParsedChord(m.group(1)!, quality, m.group(3));
}

bool isChord(String text) => parseChord(text) != null;

class KeyInfo {
  final int root;
  final bool minor;
  const KeyInfo(this.root, this.minor);

  String get name => (minor ? minorKeys : majorKeys)[root];

  /// Whether chords in this key are conventionally spelled with flats.
  bool get usesFlats {
    final n = name;
    if (n.length > 1 && n[1] == 'b') return true;
    return const ['F', 'Dm', 'Gm', 'Cm', 'Fm'].contains(n);
  }

  KeyInfo shift(int semitones) => KeyInfo((root + semitones) % 12, minor);
}

KeyInfo? parseKey(String? key) {
  if (key == null) return null;
  final c = parseChord(key.trim());
  if (c == null) return null;
  final idx = noteIndex(c.root);
  if (idx == null) return null;
  return KeyInfo(idx, c.isMinor);
}

String transposeKey(String key, int semitones) =>
    parseKey(key)?.shift(semitones).name ?? key;

String _note(int index, bool flats) => (flats ? _flat : _sharp)[((index % 12) + 12) % 12];

/// Transposes [chord] by [semitones]. Non-chords are returned unchanged.
String transposeChord(String chord, int semitones, {required bool flats}) {
  if (semitones % 12 == 0) return chord;
  final p = parseChord(chord);
  if (p == null) return chord;
  final root = _note(noteIndex(p.root)! + semitones, flats);
  final bass = p.bass == null ? '' : '/${_note(noteIndex(p.bass!)! + semitones, flats)}';
  return '$root${p.quality}$bass';
}

/// Converts a (standard notation) chord for display in [notation].
String formatChord(String chord, Notation notation, {KeyInfo? key}) {
  if (notation == Notation.standard) return chord;
  final p = parseChord(chord);
  if (p == null) return chord;
  String conv(String note) {
    switch (notation) {
      case Notation.latin:
        return _latin[note[0]]! + note.substring(1);
      case Notation.german:
        if (note == 'B') return 'H';
        if (note == 'Bb') return 'B';
        return note;
      case Notation.nashville:
        if (key == null) return note;
        // In a minor key, number against the relative major.
        final tonic = key.minor ? key.root + 3 : key.root;
        return _nashville[((noteIndex(note)! - tonic) % 12 + 12) % 12];
      case Notation.standard:
        return note;
    }
  }

  final bass = p.bass == null ? '' : '/${conv(p.bass!)}';
  return '${conv(p.root)}${p.quality}$bass';
}

/// Guesses the key from the chords of a song, in order of appearance.
/// Returns null when there is nothing to go on.
String? detectKey(List<String> chords) {
  final parsed = [for (final c in chords) ?parseChord(c)];
  if (parsed.isEmpty) return null;
  // Diatonic triads of a major key: offset -> isMinor.
  const major = {0: false, 2: true, 4: true, 5: false, 7: false, 9: true};
  String? best;
  var bestScore = -1.0;
  for (var root = 0; root < 12; root++) {
    for (final minor in [false, true]) {
      // A minor key shares the triads of its relative major.
      final base = minor ? (root + 3) % 12 : root;
      var score = 0.0;
      for (final p in parsed) {
        final off = ((noteIndex(p.root)! - base) % 12 + 12) % 12;
        if (major[off] == p.isMinor) score += 1;
      }
      bool tonic(ParsedChord p) => noteIndex(p.root) == root && p.isMinor == minor;
      if (tonic(parsed.first)) score += parsed.length * 0.2 + 1;
      if (tonic(parsed.last)) score += parsed.length * 0.2 + 1;
      if (score > bestScore) {
        bestScore = score;
        best = KeyInfo(root, minor).name;
      }
    }
  }
  return best;
}
