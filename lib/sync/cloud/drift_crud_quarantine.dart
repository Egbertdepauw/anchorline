/// Drift-backed [CrudQuarantine]: persists permanently-rejected CRUD ops to
/// the local `sync_quarantine` table so a single "poison" op can't wedge the
/// upload queue (issue #2), the diagnostic can surface "N changes couldn't
/// sync", and a future re-drive can replay them once the cause is fixed.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show CrudEntry;

import '../../data/db/database.dart';
import 'ccrlogger_backend_connector.dart' show CrudQuarantine;

class DriftCrudQuarantine implements CrudQuarantine {
  final AppDatabase _db;
  DriftCrudQuarantine(this._db);

  @override
  Future<void> record(CrudEntry op, Object cause) async {
    await _db.into(_db.syncQuarantine).insert(
          SyncQuarantineCompanion.insert(
            opClientId: op.clientId,
            opType: op.op.name,
            targetTable: op.table,
            rowId: op.id,
            opData: Value(op.opData == null ? null : jsonEncode(op.opData)),
            error: cause.toString(),
            quarantinedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// How many ops are currently quarantined — the "N changes couldn't sync"
  /// figure for the diagnostic.
  Future<int> count() async {
    final countExp = _db.syncQuarantine.id.count();
    final query = _db.selectOnly(_db.syncQuarantine)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
