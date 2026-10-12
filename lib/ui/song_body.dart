import 'package:flutter/material.dart';

import '../models.dart';
import '../music/chordpro.dart';
import '../music/transpose.dart';

const _nbsp = ' ';

/// Renders a parsed song: sections, chords above lyrics, comments and tabs.
class SongBody extends StatelessWidget {
  const SongBody({
    super.key,
    required this.doc,
    required this.settings,
    this.sectionOrder = '',
    this.shift = 0,
    this.songKey,
    this.zoom = 1,
  });

  final SongDoc doc;
  final AppSettings settings;
  final String sectionOrder;

  /// Semitones applied to the written chords (transpose minus capo).
  final int shift;

  /// Key the song is written in, used to pick sharps or flats.
  final KeyInfo? songKey;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final size = settings.fontSize * zoom;
    final family = settings.monoLyrics ? 'RobotoMono' : null;
    final lyric = TextStyle(fontSize: size, height: 1.25, fontFamily: family, color: theme.colorScheme.onSurface);
    final chord = TextStyle(
      fontSize: size *
          switch (settings.chordSize) {
            ChordSize.small => 0.8,
            ChordSize.normal => 0.95,
            ChordSize.large => 1.1,
          },
      height: 1.2,
      fontFamily: family,
      fontWeight: settings.boldChords ? FontWeight.w700 : FontWeight.w500,
      color: Color(dark ? settings.chordColorDark : settings.chordColorLight),
    );
    final shownKey = songKey?.shift(shift);
    final flats = shownKey?.usesFlats ?? false;
    String show(String c) =>
        formatChord(transposeChord(c, shift, flats: flats), settings.notation, key: shownKey);

    final sections = applySectionOrder(doc.sections, sectionOrder);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sections) _section(context, s, lyric, chord, show),
      ],
    );
  }

  Widget _section(BuildContext context, Section s, TextStyle lyric, TextStyle chord, String Function(String) show) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (s.type) {
      SectionType.chorus => scheme.primary,
      SectionType.bridge => scheme.tertiary,
      SectionType.prechorus => scheme.secondary,
      _ => null,
    };
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (settings.showHeaders && s.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              s.label.toUpperCase(),
              style: TextStyle(
                fontSize: lyric.fontSize! * 0.72,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: accent ?? scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final l in s.lines) _line(context, l, lyric, chord, show),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: lyric.fontSize! * 0.9),
      child: accent == null
          ? body
          : Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
              child: body,
            ),
    );
  }

  Widget _line(BuildContext context, Line line, TextStyle lyric, TextStyle chord, String Function(String) show) {
    final scheme = Theme.of(context).colorScheme;
    switch (line) {
      case EmptyLine():
        return SizedBox(height: lyric.fontSize! * 0.6);
      case RawLine(:final text):
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(text.isEmpty ? ' ' : text,
              softWrap: false, style: lyric.copyWith(fontFamily: 'RobotoMono', fontSize: lyric.fontSize! * 0.85)),
        );
      case CommentLine(:final text, :final style):
        final t = Text(text,
            style: lyric.copyWith(
              fontSize: lyric.fontSize! * 0.9,
              fontStyle: style == CommentStyle.box ? FontStyle.normal : FontStyle.italic,
              color: scheme.onSurfaceVariant,
            ));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: style == CommentStyle.box
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: t,
                )
              : t,
        );
      case LyricLine():
        if (!line.hasChords || !settings.showChords) {
          final text = line.lyrics.trim();
          // A chord-only line disappears entirely when chords are hidden.
          return text.isEmpty && line.hasChords ? const SizedBox.shrink() : Text(text, style: lyric);
        }
        if (!line.hasLyrics) {
          return Text.rich(TextSpan(children: [
            for (final seg in line.segments) ...[
              if (seg.chord != null) TextSpan(text: show(seg.chord!), style: chord),
              TextSpan(
                  text: (seg.lyric.isEmpty ? ' ' : seg.lyric).replaceAll(' ', _nbsp),
                  style: chord.copyWith(fontWeight: FontWeight.normal)),
            ],
          ]));
        }
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final group in _wordGroups(line.segments))
              Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (i, seg) in group.indexed)
                  _piece(
                    context,
                    seg.chord == null ? _nbsp : '${show(seg.chord!)}$_nbsp',
                    seg.lyric.isEmpty ? _nbsp : seg.lyric.replaceAll(' ', _nbsp),
                    chord,
                    lyric,
                    midWord: i < group.length - 1 && seg.lyric.isNotEmpty,
                  ),
              ]),
          ],
        );
    }
  }
}

/// One chord with the lyric beneath it. When the chord is wider than a
/// syllable in the middle of a word, the gap is bridged with a hyphen.
Widget _piece(BuildContext context, String chordText, String lyricText, TextStyle chord, TextStyle lyric,
    {required bool midWord}) {
  Widget lyricWidget = Text(lyricText, style: lyric);
  if (midWord) {
    final scaler = MediaQuery.textScalerOf(context);
    double width(String text, TextStyle style) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final gap = width(chordText, chord) - width(lyricText, lyric);
    if (gap > lyric.fontSize! * 0.45) {
      lyricWidget = Row(mainAxisSize: MainAxisSize.min, children: [
        lyricWidget,
        SizedBox(width: gap, child: Center(child: Text('-', style: lyric))),
      ]);
    }
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [Text(chordText, style: chord), lyricWidget],
  );
}

/// Splits segments at word boundaries so the line can wrap between words
/// while a chord placed mid-word stays attached to its word.
List<List<Segment>> _wordGroups(List<Segment> segments) {
  final groups = <List<Segment>>[];
  var current = <Segment>[];
  void flush() {
    if (current.isNotEmpty) groups.add(current);
    current = [];
  }

  final wordRe = RegExp(r'\S*\s*');
  for (final seg in segments) {
    final parts = wordRe.allMatches(seg.lyric).map((m) => m.group(0)!).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      current.add(Segment(seg.chord, ''));
      flush();
      continue;
    }
    for (var i = 0; i < parts.length; i++) {
      current.add(Segment(i == 0 ? seg.chord : null, parts[i]));
      if (parts[i].endsWith(' ') || parts[i].endsWith('\t')) flush();
    }
  }
  flush();
  return groups;
}
