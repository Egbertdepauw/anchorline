/// CRUD for dive merge groups, stored in the synced `dive_merge_links`
/// table. A dive belongs to at most one group (PK = dive id). Unmerge is a
/// soft delete so it syncs and is undoable.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import 'database.dart';

/// A single active dive->group link.
class MergeLink {
  final String diveId;
  final String groupId;
  const MergeLink({required this.diveId, required this.groupId});
}

/// Deterministic group id from the set of dive ids (order-independent), so
/// the same merge performed on two devices yields the same group id and
/// PowerSync reconciles cleanly.
String generateMergeGroupId(List<String> diveIds) {
  final sorted = [...diveIds]..sort();
  return sha256
      .convert(utf8.encode('merge:${sorted.join(":")}'))
      .toString()
      .substring(0, 32);
}

class DiveMergeDao {
  // ignore: unused_field
  final AppDatabase _drift; // reserved for future Drift-side queries (raw blobs)
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DiveMergeDao(this._drift, this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  /// Links [diveIds] into one group. Reactivates soft-deleted links.
  /// Returns the group id.
  Future<String> mergeDives(List<String> diveIds) async {
    if (diveIds.isEmpty) {
      throw ArgumentError('diveIds must not be empty');
    }
    final groupId = generateMergeGroupId(diveIds);
    final now = DateTime.now().millisecondsSinceEpoch;
    final placeholders = List.filled(diveIds.length, '?').join(',');
    await _ps.writeTransaction((tx) async {
      // Read existing rows INSIDE the transaction so a concurrent sync-down
      // can't slip a row in between the check and the write (which would make
      // the INSERT branch hit a primary-key conflict).
      final existingRows = await tx.getAll(
        'SELECT id FROM dive_merge_links WHERE id IN ($placeholders)',
        diveIds,
      );
      final existing = existingRows.map((r) => r['id'] as String).toSet();
      for (final diveId in diveIds) {
        if (existing.contains(diveId)) {
          await tx.execute(
            'UPDATE dive_merge_links SET group_id = ?, owner_id = ?, '
            'deleted_at = NULL, updated_at = ?, '
            'version = COALESCE(version, 0) + 1, '
            'sync_status = 0 WHERE id = ?',
            [groupId, _ownerId, now, diveId],
          );
        } else {
          await tx.execute(
            'INSERT INTO dive_merge_links '
            '(id, owner_id, group_id, created_at, updated_at, deleted_at, '
            ' version, sync_status) '
            'VALUES (?, ?, ?, ?, ?, NULL, 1, 0)',
            [diveId, _ownerId, groupId, now, now],
          );
        }
      }
    });
    return groupId;
  }

  /// All non-deleted links.
  Future<List<MergeLink>> getActiveLinks() async {
    final rows = await _ps.getAll(
      'SELECT id, group_id FROM dive_merge_links WHERE deleted_at IS NULL',
    );
    return rows
        .map((r) =>
            MergeLink(diveId: r['id'] as String, groupId: r['group_id'] as String))
        .toList();
  }

  /// Soft-deletes every link in [groupId].
  Future<void> unmerge(String groupId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'UPDATE dive_merge_links SET deleted_at = ?, updated_at = ?, '
      'version = COALESCE(version, 0) + 1 '
      'WHERE group_id = ? AND deleted_at IS NULL',
      [now, now, groupId],
    );
  }

  /// Fires whenever the links table changes (local edit or cloud sync).
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM dive_merge_links LIMIT 1').map((_) {});
}
