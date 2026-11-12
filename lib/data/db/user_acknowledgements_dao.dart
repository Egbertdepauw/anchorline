/// Data Access Object for user_acknowledgements: texts the diver has read
/// and accepted, such as the planner safety warning (issue #184).
///
/// PowerSync-backed and synced per account, same pattern as
/// [GasAnalysesDao]: reads and writes go through PowerSync's SQLite (never
/// Drift), owner_id is stamped from the Supabase session at insert time
/// (NULL when signed out; the OwnerIdBackfiller claims it at sign-in).
/// Rows are only ever added.
library;

import 'dart:math' as math;

import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;

/// Thin contract over [UserAcknowledgementsDao] so screens can be tested
/// with a fake.
abstract class UserAcknowledgementsDaoLike {
  /// Whether [subject] was accepted at [textVersion] or a later version.
  Future<bool> isAccepted(String subject, int textVersion);

  /// Records that the diver accepted [subject] at [textVersion].
  Future<void> accept(String subject, int textVersion);

  /// Fires whenever user_acknowledgements changes (local write or sync).
  Stream<void> watchChanges();
}

class UserAcknowledgementsDao implements UserAcknowledgementsDaoLike {
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  UserAcknowledgementsDao(this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  @override
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM user_acknowledgements LIMIT 1').map((_) {});

  @override
  Future<bool> isAccepted(String subject, int textVersion) async {
    final where = <String>[
      'deleted_at IS NULL',
      'subject = ?',
      'text_version >= ?',
    ];
    final args = <Object?>[subject, textVersion];
    // Signed in: this account's rows, plus rows this device wrote while
    // signed out (owner_id NULL), which the backfiller is about to claim.
    if (_ownerId != null) {
      where.add('(owner_id = ? OR owner_id IS NULL)');
      args.add(_ownerId);
    }
    final row = await _ps.getOptional(
      'SELECT 1 FROM user_acknowledgements '
      'WHERE ${where.join(' AND ')} LIMIT 1',
      args,
    );
    return row != null;
  }

  @override
  Future<void> accept(String subject, int textVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'INSERT INTO user_acknowledgements (id, owner_id, subject, '
      'text_version, accepted_at, created_at, updated_at, deleted_at, '
      'version, sync_status) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)',
      [_newId(), _ownerId, subject, textVersion, now, now, now],
    );
  }

  /// RFC-4122 v4 UUID generated in Dart (same as GasAnalysesDao): PowerSync's
  /// SQLite has no uuid() function.
  static String _newId() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) b.write('-');
      b.write(hex(i));
    }
    return b.toString();
  }
}
