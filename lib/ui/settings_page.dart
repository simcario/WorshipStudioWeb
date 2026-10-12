import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../music/chordpro.dart';
import '../music/transpose.dart';
import 'import_ui.dart';
import 'song_body.dart';

const _accents = [0xFF3F6FD9, 0xFF00897B, 0xFF7B4FD6, 0xFFC2410C, 0xFFB3261E, 0xFF5D6B2F, 0xFF8D6E63, 0xFFD81B60];
const _chordColors = [
  (0xFFB3261E, 0xFFFFB4A8),
  (0xFF1D4ED8, 0xFF9CC2FF),
  (0xFF00695C, 0xFF7FD9C8),
  (0xFF6D28D9, 0xFFCFB8FF),
  (0xFFB45309, 0xFFFFC978),
  (0xFF1F1F1F, 0xFFF2F2F2),
];

final _previewDoc = parseChordPro('''{start_of_verse: Verse 1}
A[G]mazing grace, how [C]sweet the [G]sound
That saved a wretch like [D]me
{end_of_verse}
{start_of_chorus}
I [G]once was lost, but [C]now am [G]found
{end_of_chorus}''');

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.settings;
        final scheme = Theme.of(context).colorScheme;
        final dark = Theme.of(context).brightness == Brightness.dark;
        void save(VoidCallback change) {
          change();
          state.saveSettings();
        }

        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(text,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            );

        Widget swatches(List<int> colors, int selected, ValueChanged<int> onPick) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < colors.length; i++)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onPick(i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(colors[i]),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colors[i] == selected ? scheme.onSurface : scheme.outlineVariant,
                            width: colors[i] == selected ? 3 : 1),
                      ),
                    ),
                  ),
              ]),
            );

        return Scaffold(
          appBar: AppBar(title: Text(tr('Impostazioni', 'Settings'))),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                header(tr('Aspetto', 'Appearance')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'system', label: Text(tr('Sistema', 'System'))),
                      ButtonSegment(value: 'light', label: Text(tr('Chiaro', 'Light'))),
                      ButtonSegment(value: 'dark', label: Text(tr('Scuro', 'Dark'))),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => save(() => s.themeMode = v.first),
                  ),
                ),
                const SizedBox(height: 16),
                swatches(_accents, s.accent, (i) => save(() => s.accent = _accents[i])),
                ListTile(
                  title: Text(tr('Lingua', 'Language')),
                  trailing: DropdownButton<String>(
                    value: s.locale,
                    items: const [
                      DropdownMenuItem(value: 'it', child: Text('Italiano')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (v) => save(() => s.locale = v ?? 'it'),
                  ),
                ),

                header(tr('Visualizzazione brano', 'Song display')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
                    child: SongBody(doc: _previewDoc, settings: s, songKey: const KeyInfo(7, false)),
                  ),
                ),
                ListTile(
                  title: Text(tr('Dimensione testo', 'Text size')),
                  subtitle: Slider(
                    value: s.fontSize,
                    min: 12,
                    max: 36,
                    divisions: 24,
                    label: s.fontSize.round().toString(),
                    onChanged: (v) => save(() => s.fontSize = v),
                  ),
                ),
                SwitchListTile(
                  title: Text(tr('Mostra accordi', 'Show chords')),
                  value: s.showChords,
                  onChanged: (v) => save(() => s.showChords = v),
                ),
                ListTile(
                  title: Text(tr('Dimensione accordi', 'Chord size')),
                  trailing: SegmentedButton<ChordSize>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ChordSize.small, label: Text('S')),
                      ButtonSegment(value: ChordSize.normal, label: Text('M')),
                      ButtonSegment(value: ChordSize.large, label: Text('L')),
                    ],
                    selected: {s.chordSize},
                    onSelectionChanged: (v) => save(() => s.chordSize = v.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(tr('Colore accordi', 'Chord colour'), style: Theme.of(context).textTheme.bodyLarge),
                ),
                swatches(
                  [for (final c in _chordColors) dark ? c.$2 : c.$1],
                  dark ? s.chordColorDark : s.chordColorLight,
                  (i) => save(() {
                    s.chordColorLight = _chordColors[i].$1;
                    s.chordColorDark = _chordColors[i].$2;
                  }),
                ),
                SwitchListTile(
                  title: Text(tr('Accordi in grassetto', 'Bold chords')),
                  value: s.boldChords,
                  onChanged: (v) => save(() => s.boldChords = v),
                ),
                SwitchListTile(
                  title: Text(tr('Intestazioni delle sezioni', 'Section headings')),
                  value: s.showHeaders,
                  onChanged: (v) => save(() => s.showHeaders = v),
                ),
                SwitchListTile(
                  title: Text(tr('Carattere a larghezza fissa', 'Monospaced font')),
                  value: s.monoLyrics,
                  onChanged: (v) => save(() => s.monoLyrics = v),
                ),
                ListTile(
                  title: Text(tr('Notazione', 'Notation')),
                  trailing: DropdownButton<Notation>(
                    value: s.notation,
                    items: [
                      DropdownMenuItem(value: Notation.standard, child: Text(tr('Standard (C D E)', 'Standard (C D E)'))),
                      DropdownMenuItem(value: Notation.latin, child: Text(tr('Latina (Do Re Mi)', 'Latin (Do Re Mi)'))),
                      DropdownMenuItem(value: Notation.german, child: Text(tr('Tedesca (H)', 'German (H)'))),
                      DropdownMenuItem(value: Notation.nashville, child: Text(tr('Nashville (1 4 5)', 'Nashville (1 4 5)'))),
                    ],
                    onChanged: (v) => save(() => s.notation = v ?? Notation.standard),
                  ),
                ),

                header(tr('Dal vivo', 'Live')),
                ListTile(
                  title: Text(tr('Durata scorrimento automatico', 'Auto-scroll duration')),
                  subtitle: Text(tr('Usata quando il brano non ha una durata: ${formatDuration(s.autoscrollSeconds)}',
                      'Used when the song has no duration: ${formatDuration(s.autoscrollSeconds)}')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: s.autoscrollSeconds > 30 ? () => save(() => s.autoscrollSeconds -= 15) : null),
                    IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: s.autoscrollSeconds < 900 ? () => save(() => s.autoscrollSeconds += 15) : null),
                  ]),
                ),
                ListTile(
                  title: Text(tr('Ritardo prima dello scorrimento', 'Delay before scrolling')),
                  trailing: DropdownButton<int>(
                    value: s.autoscrollDelay,
                    items: [for (final d in const [0, 3, 5, 10, 15, 30]) DropdownMenuItem(value: d, child: Text('$d s'))],
                    onChanged: (v) => save(() => s.autoscrollDelay = v ?? 0),
                  ),
                ),
                SwitchListTile(
                  title: Text(tr('Suono del metronomo', 'Metronome sound')),
                  value: s.metronomeSound,
                  onChanged: (v) => save(() => s.metronomeSound = v),
                ),
                SwitchListTile(
                  title: Text(tr('Mantieni lo schermo acceso', 'Keep the screen on')),
                  value: s.keepAwake,
                  onChanged: (v) => save(() => s.keepAwake = v),
                ),
                SwitchListTile(
                  title: Text(tr('Numera gli elementi della scaletta', 'Number set items')),
                  value: s.numberSetItems,
                  onChanged: (v) => save(() => s.numberSetItems = v),
                ),
                ListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(tr('Pedali e tastiera', 'Pedals and keyboard')),
                  subtitle: Text(tr(
                      '↓ / Pag↓ / Spazio: pagina avanti (a fine brano passa al successivo)\n↑ / Pag↑: pagina indietro\n→ / ←: brano successivo / precedente',
                      '↓ / PgDn / Space: page forward (moves to the next song at the end)\n↑ / PgUp: page back\n→ / ←: next / previous song')),
                ),

                header(tr('Libreria', 'Library')),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(tr('Esporta backup', 'Export backup')),
                  subtitle: Text(tr('${state.songs.length} brani, ${state.sets.length} scalette',
                      '${state.songs.length} songs, ${state.sets.length} sets')),
                  onTap: () => exportBackupFile(state),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: Text(tr('Importa brani o backup', 'Import songs or a backup')),
                  subtitle: const Text('.cho .chordpro .crd .pro .txt .onsong · .wsbackup · .sbp'),
                  onTap: () => importFiles(context, state),
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                  title: Text(tr('Svuota la libreria', 'Reset library'), style: TextStyle(color: scheme.error)),
                  onTap: () async {
                    final ok = await confirm(
                      context,
                      tr('Svuotare la libreria?', 'Reset the library?'),
                      body: tr(
                          'Tutti i brani, le scalette e le cartelle della libreria personale verranno eliminati da questo dispositivo e, se hai collegato un account, anche dal cloud. I gruppi non vengono toccati.',
                          'All songs, sets and folders of your personal library will be deleted from this device and, if an account is linked, from the cloud too. Groups are not affected.'),
                      action: tr('Svuota', 'Reset'),
                    );
                    if (ok) await state.resetLibrary();
                  },
                ),

                header(tr('Informazioni', 'About')),
                ListTile(
                  title: const Text('WorshipStudio 1.0.0'),
                  subtitle: Text(tr(
                      'I dati sono salvati su questo dispositivo, nel browser. Accedendo con Google dalla libreria vengono anche conservati nel cloud e condivisi con i tuoi gruppi.',
                      'Your data is saved on this device, in the browser. Sign in with Google from the library to keep it in the cloud too and share it with your groups.')),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
