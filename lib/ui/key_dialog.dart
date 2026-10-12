import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../l10n.dart';
import '../music/transpose.dart';

/// Bottom sheet to transpose the current song and set its capo.
Future<void> showKeyDialog(BuildContext context, AppState state) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ListenableBuilder(listenable: state, builder: (context, _) => _KeySheet(state: state)),
    );

class _KeySheet extends StatelessWidget {
  const _KeySheet({required this.state});

  final AppState state;

  /// Keeps the transposition in the -5…+6 range musicians expect.
  static int _normalise(int semitones) {
    final n = semitones % 12;
    return n > 6 ? n - 12 : n;
  }

  @override
  Widget build(BuildContext context) {
    final song = state.currentSong;
    if (song == null) return const SizedBox.shrink();
    final written = parseKey(song.key);
    final current = written?.shift(state.transpose);
    final shapes = written?.shift(state.transpose - state.capo);
    final text = Theme.of(context).textTheme;

    Widget stepper(String label, String value, VoidCallback? minus, VoidCallback? plus) => Row(children: [
          Expanded(child: Text(label, style: text.titleSmall)),
          IconButton.filledTonal(onPressed: minus, icon: const Icon(Icons.remove)),
          SizedBox(width: 56, child: Text(value, textAlign: TextAlign.center, style: text.titleMedium)),
          IconButton.filledTonal(onPressed: plus, icon: const Icon(Icons.add)),
        ]);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          stepper(
            tr('Trasposizione', 'Transpose'),
            state.transpose > 0 ? '+${state.transpose}' : '${state.transpose}',
            () => state.setTranspose(_normalise(state.transpose - 1)),
            () => state.setTranspose(_normalise(state.transpose + 1)),
          ),
          if (written != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < 12; i++)
                ChoiceChip(
                  label: Text(KeyInfo(i, written.minor).name),
                  selected: current!.root == i,
                  onSelected: (_) => state.setTranspose(_normalise(i - written.root)),
                ),
            ]),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr('Imposta la tonalità del brano nell\'editor per scegliere la tonalità per nome.',
                    'Set the song key in the editor to pick a key by name.'),
                style: text.bodySmall,
              ),
            ),
          const Divider(height: 32),
          stepper(
            tr('Capotasto', 'Capo'),
            '${state.capo}',
            state.capo > 0 ? () => state.setCapo(state.capo - 1) : null,
            state.capo < 11 ? () => state.setCapo(state.capo + 1) : null,
          ),
          if (state.capo > 0 && shapes != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr('Si suona con le posizioni di ${shapes.name}, suona in ${current!.name}.',
                    'Play ${shapes.name} shapes, sounds in ${current.name}.'),
                style: text.bodySmall,
              ),
            ),
          if (state.currentItem != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr('Le modifiche valgono solo per questa scaletta.', 'Changes apply to this set only.'),
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ]),
      ),
    );
  }
}
