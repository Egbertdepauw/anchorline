/// Data Access Object for open_blends (issue #112): gases the diver has
/// blended and not yet analysed. An analysis that matches one closes it.
///
/// PowerSync-backed, same pattern as [GasAnalysesDao]: reads and writes go
/// through PowerSync's SQLite, owner_id is stamped from the session at
/// insert time, dismiss is a soft delete with a version bump.
///
/// closed_by_analysis_id is a soft reference to gas_analyses.id (no FK). A
/// blend is open when it isn't deleted and either has no closing analysis
/// or its closing analysis is soft-deleted. A link to an analysis that
/// isn't on this device (yet) counts as closed, so a sync in flight doesn't
/// briefly reopen the blend.
library;

import 'dart:math' as math;

import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/gas_analysis.dart';
import '../models/open_blend.dart';

export '../models/gas_analysis.dart' show DesiredMix, GasRole;
export '../models/open_blend.dart';

/// Thin contract over [OpenBlendsDao] so screens and the processor can be
/// tested with a fake.
abstract class OpenBlendsDaoLike {
  /// Saves a new open blend and returns its id.
  Future<String> add(NewOpenBlend b);

  /// Open blends, oldest first.
  Future<List<OpenBlend>> listOpen();

  /// Open blends, oldest first; emits on open_blends or gas_analyses
  /// changes.
  Stream<List<OpenBlend>> watchOpen();

  /// Closes [b] with [analysisId] if it is still open, otherwise the oldest
  /// open blend with the same target. False when there is none.
  Future<bool> closeBlend(OpenBlend b, String analysisId);

  /// Closes the oldest open blend of [target]; returns its id, or null.
  Future<String?> closeOldestOpen(DesiredMix target, String analysisId);

  /// The blend (not dismissed) that [analysisId] closed, or null.
  Future<OpenBlend?> blendClosedBy(String analysisId);

  /// Soft-deletes the blend.
  Future<void> dismiss(String id);
}

class OpenBlendsDao implements OpenBlendsDaoLike {
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  OpenBlendsDao(this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  /// RFC-4122 v4 UUID generated in Dart (same as GasAnalysesDao).
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

  @override
  Future<String> add(NewOpenBlend b) async {
    final id = _newId();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'INSERT INTO open_blends (id, owner_id, target_o2_percent, '
      'target_he_percent, target_pressure_bar, residual_o2_percent, '
      'residual_he_percent, residual_pressure_bar, topoff_o2_percent, '
      'topoff_he_percent, water_capacity_l, gas_role, blended_by, '
      'blended_at, closed_by_analysis_id, created_at, updated_at, '
      'deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, NULL, '
      '1, 0)',
      [
        id,
        _ownerId,
        b.target.o2Percent,
        b.target.hePercent,
        b.targetPressureBar,
        b.residual.o2Percent,
        b.residual.hePercent,
        b.residualPressureBar,
        b.topoff.o2Percent,
        b.topoff.hePercent,
        b.waterCapacityL,
        b.role.dbValue,
        _blankToNull(b.blendedBy),
        b.blendedAt.millisecondsSinceEpoch,
        now,
        now,
      ],
    );
    return id;
  }

  /// WHERE clause (and its arguments) shared by every "is it open" check.
  (String, List<Object?>) _openWhere() {
    final where = StringBuffer(
      'b.deleted_at IS NULL AND (b.closed_by_analysis_id IS NULL OR EXISTS '
      '(SELECT 1 FROM gas_analyses a WHERE a.id = b.closed_by_analysis_id '
      'AND a.deleted_at IS NOT NULL))',
    );
    final args = <Object?>[];
    final owner = _ownerId;
    if (owner != null) {
      where.write(' AND b.owner_id = ?');
      args.add(owner);
    }
    return (where.toString(), args);
  }

  static const _order = 'ORDER BY b.blended_at ASC, b.created_at ASC, b.id ASC';

  @override
  Future<List<OpenBlend>> listOpen() async {
    final (where, args) = _openWhere();
    final rows = await _ps.getAll(
      'SELECT b.* FROM open_blends b WHERE $where $_order',
      args,
    );
    return rows.map(_rowToBlend).toList();
  }

  @override
  Stream<List<OpenBlend>> watchOpen() {
    final (where, args) = _openWhere();
    return _ps
        .watch(
          'SELECT b.* FROM open_blends b WHERE $where $_order',
          parameters: args,
        )
        .map((rows) => rows.map(_rowToBlend).toList());
  }

  @override
  Future<bool> closeBlend(OpenBlend b, String analysisId) =>
      _ps.writeTransaction((tx) async {
        // Same predicate as listOpen, inside the transaction: two quick
        // closes can't both claim one blend.
        final (where, args) = _openWhere();
        final still = await tx.getOptional(
          'SELECT b.id FROM open_blends b WHERE $where AND b.id = ?',
          [...args, b.id],
        );
        var id = still?['id'] as String?;
        if (id == null) {
          final (sql, targetArgs) = _oldestOfTargetQuery(b.target);
          id = (await tx.getOptional(sql, targetArgs))?['id'] as String?;
        }
        if (id == null) return false;
        await tx.execute(_closeSql, _closeArgs(id, analysisId));
        return true;
      });

  @override
  Future<String?> closeOldestOpen(DesiredMix target, String analysisId) =>
      _ps.writeTransaction((tx) async {
        final (sql, args) = _oldestOfTargetQuery(target);
        final id = (await tx.getOptional(sql, args))?['id'] as String?;
        if (id == null) return null;
        await tx.execute(_closeSql, _closeArgs(id, analysisId));
        return id;
      });

  @override
  Future<OpenBlend?> blendClosedBy(String analysisId) async {
    final owner = _ownerId;
    final row = await _ps.getOptional(
      'SELECT b.* FROM open_blends b WHERE b.deleted_at IS NULL '
      'AND b.closed_by_analysis_id = ?${owner != null ? ' AND b.owner_id = ?' : ''} '
      '$_order LIMIT 1',
      [analysisId, ?owner],
    );
    return row == null ? null : _rowToBlend(row);
  }

  (String, List<Object?>) _oldestOfTargetQuery(DesiredMix target) {
    final (where, args) = _openWhere();
    return (
      'SELECT b.id FROM open_blends b WHERE $where '
          'AND b.target_o2_percent = ? AND b.target_he_percent = ? '
          '$_order LIMIT 1',
      [...args, target.o2Percent, target.hePercent],
    );
  }

  static const _closeSql =
      'UPDATE open_blends SET closed_by_analysis_id = ?, updated_at = ?, '
      'version = COALESCE(version, 0) + 1 WHERE id = ?';

  static List<Object?> _closeArgs(String id, String analysisId) =>
      [analysisId, DateTime.now().millisecondsSinceEpoch, id];

  @override
  Future<void> dismiss(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM open_blends WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE open_blends SET deleted_at = ?, updated_at = ?, '
        'version = ? WHERE id = ?',
        [now, now, newVersion, id],
      );
    });
  }

  static double _real(Object? v) => (v as num?)?.toDouble() ?? 0;

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static OpenBlend _rowToBlend(Map<String, dynamic> r) => OpenBlend(
        id: r['id'] as String,
        target: DesiredMix(
            _int(r['target_o2_percent']), _int(r['target_he_percent'])),
        targetPressureBar: _real(r['target_pressure_bar']),
        residual: DesiredMix(
            _int(r['residual_o2_percent']), _int(r['residual_he_percent'])),
        residualPressureBar: _real(r['residual_pressure_bar']),
        topoff: DesiredMix(
            _int(r['topoff_o2_percent']), _int(r['topoff_he_percent'])),
        waterCapacityL: _real(r['water_capacity_l']),
        role: GasRole.fromDb(r['gas_role'] as String?),
        blendedBy: r['blended_by'] as String?,
        blendedAt:
            DateTime.fromMillisecondsSinceEpoch(_int(r['blended_at'])),
      );
}
