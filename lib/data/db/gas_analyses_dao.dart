/// Data Access Object for gas_analyses (cylinder analysis log, issue #111).
///
/// PowerSync-backed table, same pattern as [DivePlansDao]: reads and
/// writes go through PowerSync's SQLite (never Drift), owner_id is stamped
/// from the Supabase session at insert time, delete is a soft delete via
/// deleted_at with a version bump. UUIDs are generated in Dart because
/// PowerSync's SQLite has no uuid() function.
///
/// cylinder_id is a soft reference to cylinders.id (no FK): the cylinder's
/// label is joined at read time, soft-deleted cylinders still resolve, and
/// a dangling id is shown as an unknown cylinder instead of losing the
/// analysis.
library;

import 'dart:math' as math;

import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/gas_analysis.dart';

export '../models/gas_analysis.dart';

/// Thin contract over [GasAnalysesDao] so screens can be tested with a
/// fake (mirrors DivePlansDaoLike).
abstract class GasAnalysesDaoLike {
  /// Saves a new analysis and returns its id.
  Future<String> add(NewGasAnalysis analysis);

  /// Live analyses, newest first. With [cylinderId], only that cylinder's.
  Future<List<GasAnalysis>> list({String? cylinderId});

  Future<void> softDelete(String id);

  /// The user's live cylinders, for the "which cylinder" picker.
  Future<List<CylinderChoice>> listCylinderChoices();

  /// Fires whenever gas_analyses changes (local write or sync).
  Stream<void> watchChanges();
}

class GasAnalysesDao implements GasAnalysesDaoLike {
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  GasAnalysesDao(this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  @override
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM gas_analyses LIMIT 1').map((_) {});

  /// RFC-4122 v4 UUID generated in Dart (same as DivePlansDao).
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
  Future<String> add(NewGasAnalysis a) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId();
    String? blankToNull(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    await _ps.execute(
      'INSERT INTO gas_analyses (id, owner_id, cylinder_id, analysed_by, '
      'analysed_at, o2_percent, he_percent, fill_pressure_bar, temp_c, '
      'baro_hpa, mod_ppo2s, stable, notes, created_at, updated_at, '
      'deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)',
      [
        id,
        _ownerId,
        a.cylinderId,
        blankToNull(a.analysedBy),
        a.analysedAt.millisecondsSinceEpoch,
        a.o2Percent,
        a.hePercent,
        a.fillPressureBar,
        a.tempC,
        a.baroHpa,
        encodeModPpo2s(a.modPpo2s),
        a.stable ? 1 : 0,
        blankToNull(a.notes),
        now,
        now,
      ],
    );
    return id;
  }

  @override
  Future<List<GasAnalysis>> list({String? cylinderId}) async {
    final where = <String>['a.deleted_at IS NULL'];
    final args = <Object?>[];
    if (_ownerId != null) {
      where.add('a.owner_id = ?');
      args.add(_ownerId);
    }
    if (cylinderId != null) {
      where.add('a.cylinder_id = ?');
      args.add(cylinderId);
    }
    final rows = await _ps.getAll(
      'SELECT a.*, c.label AS cylinder_label, '
      'c.deleted_at AS cylinder_deleted_at '
      'FROM gas_analyses a '
      'LEFT JOIN cylinders c ON c.id = a.cylinder_id '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY a.analysed_at DESC',
      args,
    );
    return rows.map(_rowToAnalysis).toList();
  }

  @override
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM gas_analyses WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE gas_analyses SET deleted_at = ?, updated_at = ?, '
        'version = ? WHERE id = ?',
        [now, now, newVersion, id],
      );
    });
  }

  @override
  Future<List<CylinderChoice>> listCylinderChoices() async {
    final rows = await _ps.getAll(
      'SELECT id, label FROM cylinders WHERE deleted_at IS NULL '
      'ORDER BY label COLLATE NOCASE',
    );
    return [
      for (final r in rows)
        CylinderChoice(
          id: r['id'] as String,
          label: (r['label'] as String?) ?? 'Cylinder',
        ),
    ];
  }

  static double? _real(Object? v) => (v as num?)?.toDouble();

  static GasAnalysis _rowToAnalysis(Map<String, dynamic> r) => GasAnalysis(
        id: r['id'] as String,
        cylinderId: r['cylinder_id'] as String?,
        cylinderLabel: r['cylinder_label'] as String?,
        cylinderDeleted: r['cylinder_deleted_at'] != null,
        analysedBy: r['analysed_by'] as String?,
        analysedAt: DateTime.fromMillisecondsSinceEpoch(
            r['analysed_at'] as int? ?? 0),
        o2Percent: _real(r['o2_percent']) ?? 0,
        hePercent: _real(r['he_percent']) ?? 0,
        fillPressureBar: _real(r['fill_pressure_bar']),
        tempC: _real(r['temp_c']),
        baroHpa: _real(r['baro_hpa']),
        modPpo2s: decodeModPpo2s(r['mod_ppo2s'] as String?),
        stable: (r['stable'] as int? ?? 0) != 0,
        notes: r['notes'] as String?,
      );
}
