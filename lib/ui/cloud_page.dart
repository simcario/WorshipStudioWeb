import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../data/cloud.dart';
import '../l10n.dart';
import '../platform/platform.dart';
import 'import_ui.dart';

/// Message for an error code from Firebase or from the backend.
String cloudError(String code) => switch (code) {
      'unavailable' || 'network-request-failed' => tr('Connessione non disponibile.', 'No connection.'),
      'permission-denied' => tr('Accesso negato dal database.', 'Access denied by the database.'),
      'no-backend' => tr('Il server non è raggiungibile: gruppi e inviti non sono disponibili.',
          'The server cannot be reached: groups and invitations are unavailable.'),
      'unauthenticated' => tr('Sessione scaduta: accedi di nuovo.', 'Session expired: sign in again.'),
      'not-admin' => tr('Solo gli amministratori del gruppo possono farlo.', 'Only group administrators can do this.'),
      'last-admin' => tr('Il gruppo deve avere almeno un amministratore: nominane prima un altro.',
          'The group needs at least one administrator: appoint another one first.'),
      'already-member' => tr('Questa persona fa già parte del gruppo.', 'This person is already in the group.'),
      'invalid-email' => tr('Indirizzo email non valido.', 'Invalid email address.'),
      'invalid-name' => tr('Nome non valido (massimo 60 caratteri).', 'Invalid name (60 characters at most).'),
      'wrong-account' => tr('L\'invito è per un altro account.', 'The invitation is for another account.'),
      'not-found' => tr('Non trovato: forse è già stato rimosso.', 'Not found: it may have been removed already.'),
      'popup-blocked' => tr('Il browser ha bloccato la finestra di accesso.', 'The browser blocked the sign-in window.'),
      _ => tr('Operazione non riuscita ($code).', 'Something went wrong ($code).'),
    };

/// Runs a cloud action and reports its failure in a snackbar.
Future<bool> _guard(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } catch (e) {
    final code = Cloud.describe(e);
    // Closing the Google window is not an error.
    if (code != 'popup-closed-by-user' && code != 'cancelled-popup-request') {
      messenger.showSnackBar(SnackBar(content: Text(cloudError(code))));
    }
    return false;
  }
}

String _schedule(SyncConfig c) => switch (c.mode) {
      SyncMode.open => tr('all\'apertura dell\'app', 'when the app opens'),
      SyncMode.periodic => tr('ogni ${_interval(c.minutes)}', 'every ${_interval(c.minutes)}'),
      SyncMode.both =>
        tr('all\'apertura dell\'app e ogni ${_interval(c.minutes)}', 'when the app opens and every ${_interval(c.minutes)}'),
    };

String _interval(int minutes) => minutes % 60 == 0
    ? (minutes == 60 ? tr('ora', 'hour') : tr('${minutes ~/ 60} ore', '${minutes ~/ 60} hours'))
    : tr('$minutes minuti', '$minutes minutes');

String _time(DateTime d) =>
    '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget _avatar(String photo, String name) => CircleAvatar(
      foregroundImage: photo.isEmpty ? null : NetworkImage(photo),
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
    );

/// Account, sync, invitations, groups and (for app administrators) the sync schedule.
class CloudPage extends StatelessWidget {
  const CloudPage({super.key, required this.state, required this.cloud});

  final AppState state;
  final Cloud cloud;

  Future<void> _newGroup(BuildContext context) async {
    final name = await promptText(context, tr('Nuovo gruppo', 'New group'), hint: tr('Nome del gruppo', 'Group name'));
    if (name == null || name.isEmpty || !context.mounted) return;
    String? id;
    await _guard(context, () async => id = await cloud.createGroup(name));
    if (id != null && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupPage(state: state, cloud: cloud, groupId: id!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final user = cloud.user;
        final config = cloud.config;
        final pending = state.pendingChanges.length;

        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(text,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            );

        return Scaffold(
          appBar: AppBar(title: Text(tr('Account e gruppi', 'Account and groups'))),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                header(tr('Account', 'Account')),
                if (user == null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(tr(
                        'Accedi per conservare brani e scalette nel cloud, ritrovarli sugli altri tuoi dispositivi e condividerli con i gruppi. La libreria resta comunque su questo dispositivo e funziona offline.',
                        'Sign in to keep your songs and sets in the cloud, find them on your other devices and share them with groups. The library still lives on this device and works offline.')),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _guard(context, cloud.signIn),
                        icon: const Icon(Icons.login),
                        label: Text(tr('Accedi con Google', 'Sign in with Google')),
                      ),
                    ),
                  ),
                  if (!cloud.ready && cloud.lastError != null)
                    ListTile(
                      leading: Icon(Icons.cloud_off_outlined, color: scheme.error),
                      title: Text(cloudError(cloud.lastError!)),
                    ),
                ] else ...[
                  ListTile(
                    leading: _avatar(user.photoURL ?? '', user.displayName ?? user.email ?? ''),
                    title: Text(user.displayName ?? user.email ?? ''),
                    subtitle: Text(user.email ?? ''),
                    trailing: TextButton(onPressed: cloud.signOut, child: Text(tr('Esci', 'Sign out'))),
                  ),
                  ListTile(
                    leading: cloud.syncing
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(cloud.lastError == null ? Icons.cloud_done_outlined : Icons.sync_problem,
                            color: cloud.lastError == null ? null : scheme.error),
                    title: Text(cloud.lastError != null
                        ? cloudError(cloud.lastError!)
                        : cloud.lastSync == null
                            ? tr('Mai sincronizzato', 'Never synced')
                            : tr('Ultima sincronizzazione: ${_time(cloud.lastSync!)}', 'Last sync: ${_time(cloud.lastSync!)}')),
                    subtitle: Text([
                      tr('Sincronizzazione ${_schedule(config)}.', 'Syncs ${_schedule(config)}.'),
                      if (pending > 0) tr('$pending modifiche da inviare.', '$pending changes to send.'),
                    ].join(' ')),
                    trailing: FilledButton.tonal(
                      onPressed: cloud.syncing ? null : cloud.sync,
                      child: Text(tr('Sincronizza ora', 'Sync now')),
                    ),
                  ),
                  if (cloud.invites.isNotEmpty) header(tr('Inviti', 'Invitations')),
                  for (final invite in cloud.invites)
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(invite.groupName),
                      subtitle: Text(tr('Invito di ${invite.invitedBy}', 'Invited by ${invite.invitedBy}')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: () => _guard(context, () => cloud.declineInvite(invite)),
                          child: Text(tr('Rifiuta', 'Decline')),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => _guard(context, () => cloud.acceptInvite(invite)),
                          child: Text(tr('Accetta', 'Accept')),
                        ),
                      ]),
                    ),
                  header(tr('Gruppi', 'Groups')),
                  if (cloud.groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                          tr('Un gruppo ha una sua libreria di brani e scalette, visibile a chi inviti via email.',
                              'A group has its own library of songs and sets, visible to the people you invite by email.'),
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  for (final g in cloud.groups)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(g.name),
                      subtitle: Text([
                        tr('${g.members.length} membri', '${g.members.length} members'),
                        if (g.isAdmin(user.uid)) tr('amministratore', 'administrator'),
                      ].join('  ·  ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => GroupPage(state: state, cloud: cloud, groupId: g.id))),
                    ),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: Text(tr('Nuovo gruppo', 'New group')),
                    onTap: () => _newGroup(context),
                  ),
                  if (cloud.isAppAdmin || !config.exists) ...[
                    header(tr('Amministrazione', 'Administration')),
                    if (!config.exists)
                      ListTile(
                        title: Text(tr('L\'app non ha ancora un amministratore', 'The app has no administrator yet')),
                        subtitle: Text(tr(
                            'L\'amministratore decide quando le librerie di tutti gli utenti vengono sincronizzate con il cloud.',
                            'The administrator decides when every user\'s library is synced with the cloud.')),
                        trailing: FilledButton.tonal(
                          onPressed: () => _guard(context, () => cloud.saveConfig(config.mode, config.minutes)),
                          child: Text(tr('Diventa amministratore', 'Become administrator')),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(tr('Quando sincronizzare con il cloud (vale per tutti gli utenti):',
                            'When to sync with the cloud (applies to every user):')),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SegmentedButton<SyncMode>(
                          segments: [
                            ButtonSegment(value: SyncMode.open, label: Text(tr('Apertura app', 'App open'))),
                            ButtonSegment(value: SyncMode.periodic, label: Text(tr('Periodica', 'Periodic'))),
                            ButtonSegment(value: SyncMode.both, label: Text(tr('Entrambe', 'Both'))),
                          ],
                          selected: {config.mode},
                          onSelectionChanged: (v) => _guard(context, () => cloud.saveConfig(v.first, config.minutes)),
                        ),
                      ),
                      if (config.mode != SyncMode.open)
                        ListTile(
                          title: Text(tr('Intervallo', 'Interval')),
                          trailing: DropdownButton<int>(
                            value: config.minutes,
                            items: [
                              for (final m in {5, 15, 30, 60, 180, 720, config.minutes}.toList()..sort())
                                DropdownMenuItem(value: m, child: Text(_interval(m))),
                            ],
                            onChanged: (v) => _guard(context, () => cloud.saveConfig(config.mode, v ?? config.minutes)),
                          ),
                        ),
                    ],
                  ],
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Members, invitations and settings of one group.
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.state, required this.cloud, required this.groupId});

  final AppState state;
  final Cloud cloud;
  final String groupId;

  Future<void> _invite(BuildContext context, Group group) async {
    final email = await promptText(context, tr('Invita nel gruppo', 'Invite to the group'),
        hint: tr('Email dell\'account Google', 'Email of the Google account'));
    if (email == null || email.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    ({bool mailed, String link})? sent;
    await _guard(context, () async => sent = await cloud.invite(groupId, email));
    if (sent == null || !context.mounted) return;
    if (sent!.mailed) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Invito inviato a $email', 'Invitation sent to $email'))));
      return;
    }
    // No mail server on the backend: the administrator sends the text.
    final subject = tr('Invito nel gruppo "${group.name}" su WorshipStudio', 'Invitation to the group "${group.name}" on WorshipStudio');
    final body = tr(
        'Ti ho invitato nel gruppo "${group.name}" su WorshipStudio.\n\nApri ${sent!.link} e accedi con l\'account Google $email: troverai l\'invito da accettare.',
        'I invited you to the group "${group.name}" on WorshipStudio.\n\nOpen ${sent!.link} and sign in with the Google account $email to accept the invitation.');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Invito creato', 'Invitation created')),
        content: Text(tr(
            'L\'invio automatico delle email non è attivo: manda tu questo messaggio a $email.\n\n$body',
            'Automatic mail is not active: send this message to $email yourself.\n\n$body')),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: body));
              Navigator.pop(context);
            },
            child: Text(tr('Copia il testo', 'Copy the text')),
          ),
          FilledButton(
            onPressed: () {
              openUrl('mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
              Navigator.pop(context);
            },
            child: Text(tr('Apri l\'email', 'Open mail')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final group = cloud.group(groupId);
        if (group == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('Non fai più parte di questo gruppo.', 'You are no longer in this group.'))),
          );
        }
        final me = cloud.uid;
        final admin = group.isAdmin(me);

        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(text,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            );

        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              if (admin)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: tr('Rinomina', 'Rename'),
                  onPressed: () async {
                    final name = await promptText(context, tr('Nome del gruppo', 'Group name'), initial: group.name);
                    if (name == null || name.isEmpty || !context.mounted) return;
                    await _guard(context, () => cloud.updateGroup(groupId, name: name));
                  },
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                ListTile(
                  leading: const Icon(Icons.library_music_outlined),
                  title: Text(tr('Apri la libreria del gruppo', 'Open the group library')),
                  subtitle: Text(group.canEdit(me)
                      ? tr('Puoi aggiungere e modificare brani e scalette.', 'You can add and edit songs and sets.')
                      : tr('Puoi vedere brani e scalette.', 'You can view songs and sets.')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    state.setScope(groupId);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
                if (admin)
                  SwitchListTile(
                    secondary: const Icon(Icons.edit_note),
                    title: Text(tr('Tutti i membri possono modificare', 'Every member can edit')),
                    subtitle: Text(tr('Se disattivato, solo gli amministratori cambiano brani e scalette.',
                        'When off, only administrators change songs and sets.')),
                    value: group.membersCanEdit,
                    onChanged: (v) => _guard(context, () => cloud.updateGroup(groupId, membersCanEdit: v)),
                  ),
                header(tr('Membri (${group.members.length})', 'Members (${group.members.length})')),
                for (final m in group.members)
                  ListTile(
                    leading: _avatar(m.photo, m.name),
                    title: Text(m.uid == me ? tr('${m.name} (tu)', '${m.name} (you)') : m.name),
                    subtitle: Text([m.email, if (m.admin) tr('amministratore', 'administrator')].join('  ·  ')),
                    trailing: !admin
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'role') {
                                await _guard(context, () => cloud.setAdmin(groupId, m.uid, !m.admin));
                              } else if (await confirm(
                                  context, tr('Rimuovere ${m.name} dal gruppo?', 'Remove ${m.name} from the group?'),
                                  action: tr('Rimuovi', 'Remove'))) {
                                if (context.mounted) await _guard(context, () => cloud.removeMember(groupId, m.uid));
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'role',
                                  child: Text(m.admin
                                      ? tr('Revoca amministratore', 'Dismiss as administrator')
                                      : tr('Nomina amministratore', 'Make administrator'))),
                              if (m.uid != me)
                                PopupMenuItem(value: 'remove', child: Text(tr('Rimuovi dal gruppo', 'Remove from the group'))),
                            ],
                          ),
                  ),
                if (admin || group.invites.isNotEmpty) header(tr('Inviti in attesa', 'Pending invitations')),
                for (final e in group.invites.entries)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(e.value),
                    trailing: !admin
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: tr('Annulla l\'invito', 'Cancel the invitation'),
                            onPressed: () => _guard(context, () => cloud.revokeInvite(groupId, e.key)),
                          ),
                  ),
                if (admin)
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: Text(tr('Invita via email', 'Invite by email')),
                    subtitle: Text(tr('La persona accede con Google usando quell\'indirizzo e accetta l\'invito.',
                        'The person signs in with Google using that address and accepts the invitation.')),
                    onTap: () => _invite(context, group),
                  ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(tr('Esci dal gruppo', 'Leave the group')),
                  onTap: () async {
                    final ok = await confirm(context, tr('Uscire da "${group.name}"?', 'Leave "${group.name}"?'),
                        body: group.members.length == 1
                            ? tr('Sei l\'unico membro: il gruppo verrà eliminato con i suoi brani e scalette.',
                                'You are the only member: the group is deleted with its songs and sets.')
                            : tr('Brani e scalette del gruppo spariranno da questo dispositivo.',
                                'The group\'s songs and sets will disappear from this device.'),
                        action: tr('Esci', 'Leave'));
                    if (!ok || !context.mounted) return;
                    final navigator = Navigator.of(context);
                    if (await _guard(context, () => cloud.removeMember(groupId, me!))) navigator.pop();
                  },
                ),
                if (admin)
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                    title: Text(tr('Elimina il gruppo', 'Delete the group'), style: TextStyle(color: scheme.error)),
                    onTap: () async {
                      final ok = await confirm(context, tr('Eliminare "${group.name}"?', 'Delete "${group.name}"?'),
                          body: tr('Il gruppo, i suoi brani e le sue scalette verranno eliminati per tutti i membri.',
                              'The group, its songs and its sets will be deleted for every member.'));
                      if (!ok || !context.mounted) return;
                      final navigator = Navigator.of(context);
                      if (await _guard(context, () => cloud.deleteGroup(groupId))) navigator.pop();
                    },
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
