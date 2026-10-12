import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'app_state.dart';

class Member {
  Member(this.uid, this.email, this.name, this.photo, this.admin);

  final String uid;
  final String email;
  final String name;
  final String photo;
  final bool admin;
}

/// A group of users sharing songs and sets, as stored in `groups/{id}`.
class Group {
  Group(this.id, this.name, this.membersCanEdit, this.members, this.invites);

  final String id;
  final String name;
  final bool membersCanEdit;
  final List<Member> members;
  final Map<String, String> invites; // pending: invite id -> email

  factory Group.fromJson(String id, Map<String, Object?> j) {
    final roles = Map<String, Object?>.from(j['roles'] as Map? ?? const {});
    final profiles = Map<String, Object?>.from(j['profiles'] as Map? ?? const {});
    final members = [
      for (final uid in (j['memberUids'] as List? ?? const []).cast<String>())
        () {
          final p = Map<String, Object?>.from(profiles[uid] as Map? ?? const {});
          final email = p['email'] as String? ?? '';
          final name = p['name'] as String? ?? '';
          return Member(uid, email, name.isEmpty ? email : name, p['photo'] as String? ?? '', roles[uid] == 'admin');
        }()
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Group(
      id,
      j['name'] as String? ?? '',
      j['membersCanEdit'] == true,
      members,
      {for (final e in (j['invites'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'membersCanEdit': membersCanEdit,
        'memberUids': [for (final m in members) m.uid],
        'roles': {for (final m in members) m.uid: m.admin ? 'admin' : 'member'},
        'profiles': {
          for (final m in members) m.uid: {'email': m.email, 'name': m.name, 'photo': m.photo}
        },
        'invites': invites,
      };

  bool isAdmin(String? uid) => members.any((m) => m.uid == uid && m.admin);
  bool canEdit(String? uid) => members.any((m) => m.uid == uid && (m.admin || membersCanEdit));
}

class Invite {
  Invite(this.id, this.groupId, this.groupName, this.invitedBy);

  final String id;
  final String groupId;
  final String groupName;
  final String invitedBy;
}

enum SyncMode { open, periodic, both }

/// When the library is stored in the cloud; decided by the app administrators
/// and kept in `config/app`.
class SyncConfig {
  SyncMode mode = SyncMode.both;
  int minutes = 15;
  List<String> admins = [];
  bool exists = false; // false until someone has claimed the administration

  SyncConfig();

  factory SyncConfig.fromJson(Map<String, Object?>? j, {required bool exists}) => SyncConfig()
    ..mode = SyncMode.values.where((m) => m.name == j?['mode']).firstOrNull ?? SyncMode.both
    ..minutes = max(1, (j?['minutes'] as num?)?.toInt() ?? 15)
    ..admins = [for (final a in (j?['admins'] as List? ?? const [])) '$a']
    ..exists = exists;

  Map<String, Object?> toJson() => {'mode': mode.name, 'minutes': minutes, 'admins': admins, 'exists': exists};
}

/// Error reported by the backend, as a short code (see server/index.js).
class ApiException implements Exception {
  ApiException(this.code);
  final String code;

  @override
  String toString() => code;
}

/// Google sign-in, sync of the local library with Firestore, and groups.
///
/// The library lives on the device (see [AppState]); [sync] sends what changed
/// here and fetches what changed elsewhere, on the schedule in [config].
/// Groups and invitations are changed through the backend in server/.
class Cloud extends ChangeNotifier {
  Cloud(this.state);

  final AppState state;

  /// Backend address when the app is not served by it (`--dart-define=API_BASE=…`).
  static const _apiBase = String.fromEnvironment('API_BASE');

  bool ready = false; // Firebase is loaded
  User? user;
  List<Group> groups = [];
  List<Invite> invites = [];
  SyncConfig config = SyncConfig();
  bool syncing = false;
  DateTime? lastSync;
  String? lastError;

  String? _uid; // account the local library is linked to
  Map<String, List<int>> _cursors = {}; // 'scope/kind' -> last updatedAt seen
  Timer? _timer;
  bool _opened = false;
  bool _starting = false;
  Future<void> _queue = Future.value();

  String? get uid => user?.uid;
  bool get isAppAdmin => user != null && config.admins.contains(user!.uid);
  Group? group(String id) => groups.where((g) => g.id == id).firstOrNull;

  /// Loads what is known from the last run, then starts Firebase. Safe to
  /// call again when the first attempt failed (first launch while offline).
  Future<void> init() async {
    if (ready || _starting) return;
    _starting = true;
    try {
      if (_uid == null) await _loadMeta();
      await Firebase.initializeApp(options: firebaseOptions);
      // The local copy is the sembast library, not Firestore's cache.
      FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
      ready = true;
      lastError = null;
      FirebaseAuth.instance.authStateChanges().listen(_onUser);
    } catch (e) {
      lastError = describe(e);
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _loadMeta() async {
    final meta = await state.readPref('cloud');
    if (meta == null) return;
    _uid = meta['uid'] as String?;
    _cursors = {
      for (final e in (meta['cursors'] as Map? ?? const {}).entries)
        '${e.key}': [for (final n in e.value as List) (n as num).toInt()]
    };
    groups = [
      for (final g in (meta['groups'] as List? ?? const []))
        Group.fromJson((g as Map)['id'] as String, Map<String, Object?>.from(g))
    ];
    final cfg = meta['config'] as Map?;
    if (cfg != null) config = SyncConfig.fromJson(Map<String, Object?>.from(cfg), exists: cfg['exists'] == true);
    lastSync = DateTime.tryParse(meta['lastSync'] as String? ?? '');
    _publishGroups();
  }

  Future<void> _saveMeta() => state.writePref('cloud', {
        'uid': _uid,
        'cursors': _cursors,
        'groups': [for (final g in groups) g.toJson()],
        'config': config.toJson(),
        'lastSync': lastSync?.toIso8601String(),
      });

  void _publishGroups() {
    state.writableGroups = {
      for (final g in groups)
        if (g.canEdit(_uid)) g.id
    };
  }

  Future<void> _onUser(User? u) async {
    user = u;
    _timer?.cancel();
    if (u == null) {
      invites = [];
      notifyListeners();
      return;
    }
    final linking = _uid != u.uid;
    if (linking) {
      // First account on this device, or a different one: start over and
      // send the library that is here.
      if (_uid != null) {
        groups = [];
        _publishGroups();
        await state.keepGroups({});
      }
      _uid = u.uid;
      _cursors = {};
      lastSync = null;
      await _saveMeta();
      await state.markAllPending();
    }
    final opening = !_opened;
    _opened = true;
    notifyListeners();
    await _run(() async {
      await _refresh();
      if (linking || (opening && config.mode != SyncMode.periodic)) await _syncData();
    });
  }

  void _arm() {
    _timer?.cancel();
    if (user == null || config.mode == SyncMode.open) return;
    _timer = Timer.periodic(Duration(minutes: config.minutes), (_) => sync());
  }

  /// Runs one cloud operation at a time.
  Future<void> _run(Future<void> Function() body) {
    return _queue = _queue.then((_) async {
      if (user == null) return;
      syncing = true;
      notifyListeners();
      try {
        await body();
        lastError = null;
      } catch (e) {
        lastError = describe(e);
      }
      syncing = false;
      await _saveMeta();
      notifyListeners();
    });
  }

  /// Short code for an error from Firebase, the backend or the network.
  static String describe(Object e) => switch (e) {
        FirebaseException() => e.code,
        ApiException() => e.code,
        TimeoutException() || http.ClientException() => 'unavailable',
        _ => '$e',
      };

  // ---- account -----------------------------------------------------------

  Future<void> signIn() async {
    await init();
    if (!ready) throw ApiException('unavailable');
    await FirebaseAuth.instance
        .signInWithPopup(GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
  }

  /// The library stays on the device and is synced again at the next sign-in.
  Future<void> signOut() => FirebaseAuth.instance.signOut();

  // ---- sync --------------------------------------------------------------

  /// Sends local changes to the cloud and fetches the others'.
  Future<void> sync() => _run(() async {
        await _refresh();
        await _syncData();
      });

  /// Reloads schedule, groups and invitations without touching the library.
  Future<void> refresh() => _run(_refresh);

  static const _server = GetOptions(source: Source.server);

  Future<void> _refresh() async {
    final db = FirebaseFirestore.instance;
    final cfg = await db.doc('config/app').get(_server);
    config = SyncConfig.fromJson(cfg.data(), exists: cfg.exists);
    final snap = await db.collection('groups').where('memberUids', arrayContains: user!.uid).get(_server);
    groups = [for (final d in snap.docs) Group.fromJson(d.id, d.data())]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _publishGroups();
    _arm();
    try {
      final list = await _api('GET', '/invites');
      invites = [
        for (final i in (list as List).cast<Map>())
          Invite('${i['id']}', '${i['groupId']}', '${i['groupName']}', '${i['invitedBy']}')
      ];
    } on ApiException catch (e) {
      // Without the backend (static hosting) the personal sync still works.
      if (e.code != 'no-backend' && e.code != 'unavailable') rethrow;
    }
  }

  CollectionReference<Map<String, dynamic>> _collection(String scope, String kind) =>
      FirebaseFirestore.instance.collection(scope.isEmpty ? 'users/${user!.uid}/$kind' : 'groups/$scope/$kind');

  Future<void> _syncData() async {
    final ids = {for (final g in groups) g.id};
    await state.keepGroups(ids);
    _cursors.removeWhere((key, _) {
      final scope = key.split('/').first;
      return scope.isNotEmpty && !ids.contains(scope);
    });
    for (final scope in ['', ...ids]) {
      for (final kind in [if (scope.isEmpty) 'folders', 'songs', 'sets']) {
        await _pull(scope, kind);
      }
    }
    await _push();
    lastSync = DateTime.now();
  }

  /// Fetches the documents written since the last pull. Deleted items remain
  /// in the cloud as `deleted: true` so the other devices learn about it.
  Future<void> _pull(String scope, String kind) async {
    final key = '$scope/$kind';
    Query<Map<String, dynamic>> query = _collection(scope, kind).orderBy('updatedAt');
    final cursor = _cursors[key];
    if (cursor != null) query = query.where('updatedAt', isGreaterThan: Timestamp(cursor[0], cursor[1]));
    final snap = await query.get(_server);
    Timestamp? last;
    final docs = <Map<String, Object?>>[];
    for (final d in snap.docs) {
      final data = d.data();
      final at = data.remove('updatedAt');
      if (at is Timestamp) last = at;
      docs.add({...data, 'id': d.id});
    }
    await state.applyRemote(scope, kind, docs);
    if (last != null) _cursors[key] = [last.seconds, last.nanoseconds];
  }

  Future<void> _push() async {
    final pending = state.pendingChanges;
    for (var i = 0; i < pending.length; i += 400) {
      final chunk = pending.sublist(i, min(i + 400, pending.length));
      final batch = FirebaseFirestore.instance.batch();
      var writes = 0;
      for (final p in chunk) {
        if (p.groupId.isNotEmpty && !state.writableGroups.contains(p.groupId)) continue; // lost the right meanwhile
        final json = p.deleted ? null : state.itemJson(p.kind, p.id);
        if (json == null && !p.deleted) continue;
        final modified = p.modified.toIso8601String();
        json?.remove('groupId'); // implied by where the document is
        batch.set(_collection(p.groupId, p.kind).doc(p.id), {
          'id': p.id,
          'modified': modified,
          ...?json,
          'deleted': json == null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        writes++;
      }
      if (writes > 0) await batch.commit();
      await state.clearPending(chunk);
    }
  }

  // ---- administration ----------------------------------------------------

  /// Saves the sync schedule for every user. Whoever saves it first becomes
  /// the app administrator (see firestore.rules).
  Future<void> saveConfig(SyncMode mode, int minutes) async {
    await FirebaseFirestore.instance.doc('config/app').set({
      'mode': mode.name,
      'minutes': minutes,
      'admins': config.exists ? config.admins : [user!.uid],
    });
    await refresh();
  }

  // ---- groups (through the backend) --------------------------------------

  Future<Object?> _api(String method, String path, [Map<String, Object?>? body]) async {
    final token = await user!.getIdToken();
    final request = http.Request(method, Uri.parse('${_apiBase.isEmpty ? Uri.base.origin : _apiBase}/api$path'))
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));
    } catch (_) {
      throw ApiException('unavailable');
    }
    // A static host answers every path with the app's own page.
    if (!(response.headers['content-type'] ?? '').contains('json')) throw ApiException('no-backend');
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) throw ApiException(data is Map ? '${data['error']}' : 'http-${response.statusCode}');
    return data;
  }

  Future<String> createGroup(String name) async {
    final created = await _api('POST', '/groups', {'name': name}) as Map;
    await refresh();
    return '${created['id']}';
  }

  Future<void> updateGroup(String id, {String? name, bool? membersCanEdit}) async {
    await _api('PATCH', '/groups/$id', {'name': ?name, 'membersCanEdit': ?membersCanEdit});
    await refresh();
  }

  Future<void> deleteGroup(String id) async {
    await _api('DELETE', '/groups/$id');
    await sync();
  }

  /// Invites [email] to the group. `mailed` is false when the backend has no
  /// mail server configured: the link must then be sent by hand.
  Future<({bool mailed, String link})> invite(String groupId, String email) async {
    final r = await _api('POST', '/groups/$groupId/invites', {'email': email}) as Map;
    await refresh();
    return (mailed: r['mailed'] == true, link: '${r['link']}');
  }

  Future<void> revokeInvite(String groupId, String inviteId) async {
    await _api('DELETE', '/groups/$groupId/invites/$inviteId');
    await refresh();
  }

  /// Joins the group and downloads its songs and sets.
  Future<void> acceptInvite(Invite invite) async {
    await _api('POST', '/invites/${invite.id}/accept');
    await sync();
  }

  Future<void> declineInvite(Invite invite) async {
    await _api('POST', '/invites/${invite.id}/decline');
    await refresh();
  }

  Future<void> setAdmin(String groupId, String memberUid, bool admin) async {
    await _api('PUT', '/groups/$groupId/members/$memberUid', {'role': admin ? 'admin' : 'member'});
    await refresh();
  }

  /// Removes a member; with one's own uid, leaves the group.
  Future<void> removeMember(String groupId, String memberUid) async {
    await _api('DELETE', '/groups/$groupId/members/$memberUid');
    await (memberUid == uid ? sync() : refresh());
  }
}
