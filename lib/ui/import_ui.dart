import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/import_export.dart';
import '../l10n.dart';
import '../platform/platform.dart';

/// Lets the user pick song files and/or backups and adds them to the library.
Future<void> importFiles(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [...songExtensions, ...backupExtensions],
  );
  if (files.isEmpty) return;
  var songs = 0, sets = 0;
  final failed = <String>[];
  String? first;
  for (final file in files) {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      if (backupExtensions.contains(ext)) {
        final result = await state.importBackup(readBackup(bytes, file.name));
        songs += result.songs;
        sets += result.sets;
      } else {
        final song = songFromText(decodeText(bytes), file.name);
        await state.saveSong(song);
        first ??= song.id;
        songs++;
      }
    } catch (_) {
      failed.add(file.name);
    }
  }
  if (first != null && songs == 1) state.showSong(first);
  messenger.showSnackBar(SnackBar(
    content: Text([
      tr('Importati: $songs brani', 'Imported: $songs songs') + (sets > 0 ? tr(', $sets scalette', ', $sets sets') : ''),
      if (failed.isNotEmpty) tr('Non importati: ${failed.join(', ')}', 'Failed: ${failed.join(', ')}'),
    ].join('\n')),
  ));
}

void exportBackupFile(AppState state) {
  final now = DateTime.now();
  final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  downloadFile('WorshipStudio-$stamp.wsbackup', utf8.encode(jsonEncode(state.exportBackup())), 'application/json');
}

Future<bool> confirm(BuildContext context, String title, {String? body, String? action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Annulla', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action ?? tr('Elimina', 'Delete'))),
      ],
    ),
  );
  return ok ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String initial = '', String? hint, int lines = 1}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: lines,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        onSubmitted: lines == 1 ? (v) => Navigator.pop(context, v.trim()) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annulla', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
