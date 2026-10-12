import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:worship_studio/data/app_state.dart';
import 'package:worship_studio/data/import_export.dart';
import 'package:worship_studio/main.dart';
import 'package:worship_studio/models.dart';
import 'package:worship_studio/music/chordpro.dart';
import 'package:worship_studio/music/transpose.dart';
import 'package:worship_studio/ui/song_editor.dart';

void main() {
  group('transpose', () {
    test('chords move by semitones with the right accidentals', () {
      expect(transposeChord('G', 2, flats: false), 'A');
      expect(transposeChord('Am7', 3, flats: false), 'Cm7');
      expect(transposeChord('D/F#', 1, flats: true), 'Eb/G');
      expect(transposeChord('Bbmaj7', -2, flats: true), 'Abmaj7');
      expect(transposeChord('Csus4', -1, flats: false), 'Bsus4');
      expect(transposeChord('N.C.', 5, flats: false), 'N.C.');
    });

    test('keys', () {
      expect(transposeKey('G', 2), 'A');
      expect(transposeKey('Em', 1), 'Fm');
      expect(transposeKey('B', 1), 'C');
      expect(parseKey('Eb')!.usesFlats, isTrue);
      expect(parseKey('E')!.usesFlats, isFalse);
    });

    test('notations', () {
      expect(formatChord('Bb', Notation.german), 'B');
      expect(formatChord('B7', Notation.german), 'H7');
      expect(formatChord('F#m', Notation.latin), 'Fa#m');
      expect(formatChord('D', Notation.nashville, key: parseKey('G')), '5');
      expect(formatChord('Em', Notation.nashville, key: parseKey('G')), '6m');
    });

    test('key detection', () {
      expect(detectKey(['G', 'C', 'G', 'D', 'Em', 'D', 'G']), 'G');
      expect(detectKey(['Am', 'F', 'C', 'G', 'Am']), 'Am');
      expect(detectKey([]), isNull);
    });
  });

  group('chordpro', () {
    test('directives, sections and chords', () {
      final doc = parseChordPro('''{t: My Song}
{artist: Someone}
{key: G}
{sov: Verse 1}
A[G]mazing [C]grace
{eov}
{soc}
[D]Sing
{eoc}
{c: Play softly}
''');
      expect(doc.meta['title'], 'My Song');
      expect(doc.meta['key'], 'G');
      expect(doc.sections.map((s) => s.type), [SectionType.verse, SectionType.chorus, SectionType.other]);
      expect(doc.sections.first.label, 'Verse 1');
      final line = doc.sections.first.lines.single as LyricLine;
      expect(line.segments.map((s) => s.chord), [null, 'G', 'C']);
      expect(line.lyrics, 'Amazing grace');
      expect(doc.chords, ['G', 'C', 'D']);
    });

    test('plain headings and blank lines split sections', () {
      final doc = parseChordPro('Verse 1:\n[G]One\n\n[Chorus]\n[C]Two\n\n[Am]\nThree');
      expect(doc.sections.map((s) => s.label), ['Verse 1', 'Chorus', '']);
      // `[Am]` alone is a chord line, not a heading.
      expect((doc.sections.last.lines.first as LyricLine).segments.first.chord, 'Am');
    });

    test('chords over lyrics are merged', () {
      expect(chordsOverLyricsToChordPro('G       C\nAmazing grace'), '[G]Amazing [C]grace');
      expect(chordsOverLyricsToChordPro('G   D'), '[G]    [D]');
      expect(chordsOverLyricsToChordPro('A [G]line'), 'A [G]line');
    });

    test('chordpro is laid out as chords over lyrics, and back', () {
      const over = 'G       C\nAmazing grace';
      expect(chordProToChordsOverLyrics('[G]Amazing [C]grace'), over);
      expect(chordProToChordsOverLyrics(over), over);
      expect(chordsOverLyricsToChordPro(over), '[G]Amazing [C]grace');
      // Chords closer than their width push the lyrics apart at a word break…
      expect(chordProToChordsOverLyrics('[Gsus4]a [C]b'), 'Gsus4 C\na     b');
      // …but never inside a word, and chords past the end need no lyric.
      expect(chordProToChordsOverLyrics('[Gsus4]a[C]b'), '[Gsus4]a[C]b');
      expect(chordProToChordsOverLyrics('soun[C]d [G]'), '    C G\nsound');
      // Whatever would read differently on the way back stays in ChordPro.
      const kept = '{title: T}\n[Chorus]\n[G]A\n[G] [D]\nplain\n{sot}\n[G]--3--\n{eot}';
      expect(chordProToChordsOverLyrics(kept), kept);
      expect(chordProToChordsOverLyrics('[G] [D]\n\n[Em]x'), 'G D\n\nEm\nx');
    });

    test('both notations parse to the same song', () {
      const src = '{sov: Verse 1}\nA[G]mazing [C/E]grace, how [G]sweet\n[Em]That saved a [D]wretch [D7]\n{eov}\n[G]  [C]';
      final over = chordProToChordsOverLyrics(src);
      expect(over, isNot(contains('[')));
      String dump(String s) => [
            for (final sec in parseChordPro(s).sections)
              for (final l in sec.lines.whereType<LyricLine>())
                l.segments.map((g) => '${g.chord}:${g.lyric.trim()}').join('|')
          ].join('\n');
      expect(dump(over), dump(src));
    });

    test('hidden blocks and tabs', () {
      final doc = parseChordPro('{x_sbp_hide}\nsecret\n{x_sbp_show}\n{sot}\ne|--3--|\n{eot}');
      expect(doc.sections.single.type, SectionType.tab);
      expect((doc.sections.single.lines.single as RawLine).text, 'e|--3--|');
    });

    test('section order', () {
      final doc = parseChordPro('Verse 1:\na\n\nChorus:\nb\n\nVerse 2:\nc\n\nBridge:\nd');
      final ordered = applySectionOrder(doc.sections, 'V1 C1 V2 C B1 C1');
      expect(ordered.map((s) => s.label), ['Verse 1', 'Chorus', 'Verse 2', 'Chorus', 'Bridge', 'Chorus']);
      expect(applySectionOrder(doc.sections, ''), doc.sections);
      expect(sectionCode(doc.sections[2], doc.sections), 'V2');
    });
  });

  group('import / export', () {
    test('ChordPro file', () {
      final s = songFromText('{title: Hello}\n{artist: Me}\n{tempo: 96 bpm}\n{capo: 2}\n[D]La [A]la [D]la', 'x.cho');
      expect((s.title, s.artist, s.tempo, s.capo, s.key), ('Hello', 'Me', 96, 2, 'D'));
    });

    test('OnSong headers', () {
      final s = songFromText('Hello\nMe\nKey: A\nTempo: 100\n\nVerse 1:\n[A]La', 'x.onsong');
      expect((s.title, s.artist, s.key, s.tempo), ('Hello', 'Me', 'A', 100));
    });

    test('file name is the fallback title; export adds directives', () {
      final s = songFromText('[C]La la', r'C:\songs\My Tune.txt');
      expect(s.title, 'My Tune');
      expect(songToChordPro(s), startsWith('{title: My Tune}\n{key: C}\n\n[C]La la'));
    });

    test('SongbookPro archive', () {
      final data = jsonEncode({
        'songs': [
          {'Id': 5, 'name': 'One', 'author': 'A', 'key': 10, 'Capo': 1, 'KeyShift': 2, 'type': 1, 'content': '[G]x', '_tags': '["t"]', 'Deleted': 0},
          {'Id': 6, 'name': 'Gone', 'type': 1, 'content': 'x', 'Deleted': 1},
        ],
        'sets': [
          {'details': {'name': 'Sunday', 'date': '2026-01-04T00:00:00'}, 'contents': [{'SongId': 5, 'Order': 0, 'keyOfset': 3}]},
        ],
        'folders': [],
      });
      final zip = ZipEncoder().encode(Archive()..addFile(ArchiveFile.string('dataFile.txt', '1.0\n$data')));
      final backup = readBackup(Uint8List.fromList(zip), 'lib.sbp');
      final songs = (backup['songs'] as List).cast<Map>();
      expect(songs.single['title'], 'One');
      expect(songs.single['key'], 'G');
      expect(songs.single['tags'], ['t']);
      final set = (backup['sets'] as List).single as Map;
      expect(set['name'], 'Sunday');
      expect(((set['items'] as List).single as Map)['transpose'], 3);
    });
  });

  group('app state', () {
    late AppState state;
    setUp(() async => state = await AppState.open(newDatabaseFactoryMemory(), 'test.db'));

    test('seeds once, searches, and transposes per set item', () async {
      expect(state.songs, isNotEmpty);
      expect(state.search(query: 'amazing').single.title, 'Amazing Grace');
      final song = state.songs.first;
      final set = SongSet(name: 'S', items: [SetItem(songId: song.id)]);
      await state.saveSet(set);
      state.showSetItem(set.id, 0);
      await state.setTranspose(2);
      expect(state.transpose, 2);
      expect(song.transpose, 0);
      await state.deleteSongs([song.id]);
      expect(state.set(set.id)!.items, isEmpty);
    });

    test('backup round trip', () async {
      final backup = jsonDecode(jsonEncode(state.exportBackup())) as Map<String, Object?>;
      await state.resetLibrary();
      expect(state.songs, isEmpty);
      final result = await state.importBackup(backup);
      expect(result.songs, 2);
      expect(state.songs.length, 2);
    });

    test('each library shows its own songs; copies go across', () async {
      final personal = state.songs.length;
      final song = state.songs.first;
      state.writableGroups = {'g1'};
      state.setScope('g1');
      expect(state.songs, isEmpty);
      expect(state.canEdit, isTrue);
      await state.saveSong(Song(title: 'Group song'));
      expect(state.songs.single.groupId, 'g1');
      final set = SongSet(name: 'Sunday', items: [SetItem(songId: state.songs.single.id)]);
      await state.saveSet(set);
      // Copying the set to the personal library brings its song along, once.
      final copy = await state.copySet(set, '');
      await state.copySet(set, '');
      state.setScope('');
      expect(state.songs.length, personal + 1);
      expect(state.song(copy.items.single.songId)!.groupId, '');
      expect(state.song(song.id), isNotNull);
      state.setScope('g2');
      expect(state.canEdit, isFalse);
    });

    test('changes are queued for the cloud and merged with what comes back', () async {
      expect(state.pendingChanges, isEmpty); // nothing is tracked before an account is linked
      await state.markAllPending();
      expect(state.pendingChanges.length, state.songs.length);
      await state.clearPending(state.pendingChanges);

      final song = state.songs.first;
      await state.saveSong(song..title = 'Mine');
      final sent = state.pendingChanges.single;
      expect((sent.kind, sent.id, sent.deleted), ('songs', song.id, false));

      // An older cloud version loses to the local edit, a newer one wins.
      final older = song.modified.subtract(const Duration(minutes: 1)).toIso8601String();
      await state.applyRemote('', 'songs', [{...song.toJson(), 'title': 'Old', 'modified': older}]);
      expect(state.song(song.id)!.title, 'Mine');
      final newer = song.modified.add(const Duration(minutes: 1)).toIso8601String();
      await state.applyRemote('', 'songs', [{...song.toJson(), 'title': 'Theirs', 'modified': newer}]);
      expect(state.song(song.id)!.title, 'Theirs');
      expect(state.pendingChanges, isEmpty);

      // An edit made while the previous one was being sent stays queued.
      await state.saveSong(state.song(song.id)!..title = 'A');
      final first = state.pendingChanges.single;
      await state.saveSong(state.song(song.id)!..title = 'B');
      await state.clearPending([first]);
      expect(state.pendingChanges, hasLength(1));

      // Deletions travel as tombstones, in both directions.
      await state.deleteSongs([song.id]);
      expect(state.pendingChanges.single.deleted, isTrue);
      final other = state.songs.first;
      await state.applyRemote('', 'songs', [{'id': other.id, 'deleted': true, 'modified': newer}]);
      expect(state.song(other.id), isNull);

      // A group's songs arrive in its library and go when the user leaves it.
      await state.applyRemote('g1', 'songs', [Song(title: 'Shared').toJson()]);
      state.setScope('g1');
      expect(state.songs.single.title, 'Shared');
      await state.keepGroups({});
      expect(state.scope, '');
      expect(state.songs.where((s) => s.title == 'Shared'), isEmpty);
    });
  });

  testWidgets('shows the library and a song on a wide screen', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(() => AppState.open(newDatabaseFactoryMemory(), 'w.db')))!;
    await tester.pumpWidget(WorshipStudioApp(state: state));
    expect(find.text('Amazing Grace'), findsOneWidget);
    await tester.tap(find.text('Amazing Grace'));
    await tester.pumpAndSettle();
    expect(find.text('VERSE 1'), findsOneWidget);
    expect(find.textContaining('Em'), findsWidgets);
  });

  testWidgets('the editor switches between ChordPro and chords over lyrics', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(() => AppState.open(newDatabaseFactoryMemory(), 'e.db')))!;
    final song = Song(title: 'T', content: '[G]Amazing [C]grace, how sweet the sound that saved a wretch like me');
    await tester.pumpWidget(MaterialApp(home: SongEditor(state: state, song: song)));
    String text() => tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(text(), song.content);
    await tester.runAsync(() async {
      await tester.tap(find.text('Accordi sopra'));
      await tester.pump();
    });
    expect(text(), 'G       C\nAmazing grace, how sweet the sound that saved a wretch like me');
    expect(state.settings.chordsOverLyrics, isTrue);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.tap(find.text('ChordPro'));
      await tester.pump();
    });
    expect(text(), song.content);
  });

  testWidgets('the editor previews beside the text on a wide screen', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(() => AppState.open(newDatabaseFactoryMemory(), 'ew.db')))!;
    await tester.pumpWidget(MaterialApp(home: SongEditor(state: state, song: Song(title: 'T', content: 'Verse 1:\n[G]One'))));
    expect(find.text('Anteprima'), findsNothing);
    expect(find.text('VERSE 1'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)).dx, lessThan(tester.getTopLeft(find.text('VERSE 1')).dx));
    await tester.enterText(find.byType(TextField), 'Chorus:\n[C]Two');
    await tester.pump();
    expect(find.text('VERSE 1'), findsNothing);
    expect(find.text('CHORUS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a drawer on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(() => AppState.open(newDatabaseFactoryMemory(), 'p.db')))!;
    await tester.pumpWidget(WorshipStudioApp(state: state));
    expect(find.text('Amazing Grace'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amazing Grace'));
    await tester.pumpAndSettle();
    expect(find.text('VERSE 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
