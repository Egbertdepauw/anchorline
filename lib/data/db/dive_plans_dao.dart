/// Data Access Object for dive_plans.
///
/// PowerSync-backed table. One draft row per user (name IS NULL),
/// auto-saved on every edit. Saved plans are named rows. Soft-delete
/// via deleted_at. owner_id stamped from the Supabase session at
/// insert time, same pattern as DiveAttachmentsDao.
///
/// UUIDs are generated in Dart (math.Random.secure) — PowerSync's
/// SQLite build does not expose a uuid() SQL function.
library;

import 'dart:math' as math;

import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/dive_plan.dart';
import 'dive_plans_dao_api.dart';

// Re-export so callers of the DAO don't have to import dive_plan.dart
// just for the types that appear in the public DAO surface.
export '../models/dive_plan.dart'
    show
        DivePlanMode,
        DivePlanGas,
        DivePlanSegment,
        DivePlanBailoutBottle,
        DivePlanSettings,
        encodeGases,
        decodeGases,
        encodeSegments,
        decodeSegments,
        encodeBailout,
        decodeBailout,
        encodeSettings,
        decodeSettings;

/// In-memory representation of an editable plan. The draft and saved
/// rows share this shape; the DAO maps it to/from the row data.
class DivePlanDraft {
  final DivePlanMode mode;
  final List<DivePlanGas> gases;
  final List<DivePlanSegment> segments;
  final List<DivePlanBailoutBottle> bailout;
  final DivePlanSettings? settings;
  final String? notes;
  const DivePlanDraft({
    required this.mode,
    required this.gases,
    required this.segments,
    required this.bailout,
    required this.settings,
    this.notes,
  });
}

/// A saved plan as it appears in the saved-plans browser.
class SavedDivePlan {
  final String id;
  final String name;
  final DateTime updatedAt;
  final DivePlanMode mode;
  const SavedDivePlan({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.mode,
  });
}

class DivePlansDao implements DivePlansDaoLike {
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DivePlansDao(this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  @override
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM dive_plans LIMIT 1').map((_) {});

  // ── UUID helper ────────────────────────────────────────────────────

  /// RFC-4122 v4 UUID generated in Dart. Mirrors UuidV4IdGenerator in
  /// dive_attachments_notifier.dart — kept local so this DAO has no
  /// notifier dependency.
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

  // ── Draft ──────────────────────────────────────────────────────────

  @override
  Future<DivePlanDraft?> loadDraft() async {
    final row = await _ps.getOptional(
      'SELECT mode, gases_json, segments_json, bailout_json, settings_json, '
      'notes FROM dive_plans '
      'WHERE name IS NULL AND deleted_at IS NULL '
      '${_ownerId == null ? '' : 'AND owner_id = ?'}',
      _ownerId == null ? [] : [_ownerId],
    );
    return row == null ? null : _toDraft(row);
  }

  @override
  Future<void> upsertDraft(DivePlanDraft draft) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      // Find the existing draft (if any).
      final existing = await tx.getOptional(
        'SELECT id FROM dive_plans '
        'WHERE name IS NULL AND deleted_at IS NULL '
        '${_ownerId == null ? '' : 'AND owner_id = ?'}',
        _ownerId == null ? [] : [_ownerId],
      );
      if (existing != null) {
        await tx.execute(
          'UPDATE dive_plans SET mode = ?, gases_json = ?, '
          'segments_json = ?, bailout_json = ?, settings_json = ?, '
          'notes = ?, updated_at = ? WHERE id = ?',
          [
            draft.mode.name,
            encodeGases(draft.gases),
            encodeSegments(draft.segments),
            encodeBailout(draft.bailout),
            encodeSettings(draft.settings),
            draft.notes,
            now,
            existing['id'],
          ],
        );
      } else {
        await tx.execute(
          'INSERT INTO dive_plans (id, owner_id, name, mode, gases_json, '
          'segments_json, bailout_json, settings_json, notes, created_at, '
          'updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)',
          [
            _newId(),
            _ownerId,
            draft.mode.name,
            encodeGases(draft.gases),
            encodeSegments(draft.segments),
            encodeBailout(draft.bailout),
            encodeSettings(draft.settings),
            draft.notes,
            now,
            now,
          ],
        );
      }
    });
  }

  /// Promotes the current draft to a saved plan with [name] and clears
  /// the draft. Returns the new saved plan.
  @override
  Future<SavedDivePlan> saveAs({required String name}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final newId = _newId();
    final result = await _ps.writeTransaction<SavedDivePlan>((tx) async {
      final draft = await tx.getOptional(
        'SELECT id, mode, gases_json, segments_json, bailout_json, '
        'settings_json, notes FROM dive_plans '
        'WHERE name IS NULL AND deleted_at IS NULL '
        '${_ownerId == null ? '' : 'AND owner_id = ?'}',
        _ownerId == null ? [] : [_ownerId],
      );
      if (draft == null) {
        throw StateError('No draft to save.');
      }
      // Insert a new named row.
      await tx.execute(
        'INSERT INTO dive_plans (id, owner_id, name, mode, gases_json, '
        'segments_json, bailout_json, settings_json, notes, created_at, '
        'updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)',
        [
          newId,
          _ownerId,
          name,
          draft['mode'],
          draft['gases_json'],
          draft['segments_json'],
          draft['bailout_json'],
          draft['settings_json'],
          draft['notes'],
          now,
          now,
        ],
      );
      // Clear the draft row.
      await tx.execute(
        'DELETE FROM dive_plans WHERE id = ?',
        [draft['id']],
      );
      return SavedDivePlan(
        id: newId,
        name: name,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        mode: DivePlanMode.values
            .firstWhere((m) => m.name == draft['mode']),
      );
    });
    return result;
  }

  // ── Saved plans ────────────────────────────────────────────────────

  @override
  Future<List<SavedDivePlan>> listSaved() async {
    final rows = await _ps.getAll(
      'SELECT id, name, mode, updated_at FROM dive_plans '
      'WHERE name IS NOT NULL AND deleted_at IS NULL '
      '${_ownerId == null ? '' : 'AND owner_id = ?'} '
      'ORDER BY updated_at DESC',
      _ownerId == null ? [] : [_ownerId],
    );
    return rows
        .map((r) => SavedDivePlan(
              id: r['id'] as String,
              name: r['name'] as String,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  r['updated_at'] as int),
              mode: DivePlanMode.values
                  .firstWhere((m) => m.name == r['mode']),
            ))
        .toList();
  }

  /// Loads a saved plan into a draft-shaped object. The caller can then
  /// pass it to [upsertDraft] to replace the active draft.
  @override
  Future<DivePlanDraft?> loadSaved(String id) async {
    final row = await _ps.getOptional(
      'SELECT mode, gases_json, segments_json, bailout_json, settings_json, '
      'notes FROM dive_plans WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return row == null ? null : _toDraft(row);
  }

  @override
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'UPDATE dive_plans SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, id],
    );
  }

  @override
  Future<void> renameSaved(String id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'UPDATE dive_plans SET name = ?, updated_at = ? WHERE id = ?',
      [name, now, id],
    );
  }

  /// Clears the current draft (without saving). Used by "New plan".
  @override
  Future<void> clearDraft() async {
    await _ps.execute(
      'DELETE FROM dive_plans '
      'WHERE name IS NULL AND deleted_at IS NULL '
      '${_ownerId == null ? '' : 'AND owner_id = ?'}',
      _ownerId == null ? [] : [_ownerId],
    );
  }

  // ── Mapping ────────────────────────────────────────────────────────

  DivePlanDraft _toDraft(Map<String, dynamic> row) => DivePlanDraft(
        mode: DivePlanMode.values
            .firstWhere((m) => m.name == row['mode']),
        gases: decodeGases(row['gases_json'] as String),
        segments: decodeSegments(row['segments_json'] as String),
        bailout: decodeBailout(row['bailout_json'] as String),
        settings: decodeSettings(row['settings_json'] as String?),
        notes: row['notes'] as String?,
      );
}
