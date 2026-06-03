import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/sync/cloud/drift_crud_quarantine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show CrudEntry, UpdateType;

void main() {
  late AppDatabase db;
  late DriftCrudQuarantine quarantine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    quarantine = DriftCrudQuarantine(db);
  });

  tearDown(() => db.close());

  test('records a permanently-rejected op and counts it', () async {
    expect(await quarantine.count(), 0);

    await quarantine.record(
      CrudEntry(7, UpdateType.put, 'dive_samples', 'dive-1', null, {'b': 1}),
      Exception('413 oversized'),
    );

    expect(await quarantine.count(), 1);
    final row = await db.select(db.syncQuarantine).getSingle();
    expect(row.opClientId, 7);
    expect(row.opType, 'put');
    expect(row.targetTable, 'dive_samples');
    expect(row.rowId, 'dive-1');
    expect(row.opData, contains('"b":1'));
    expect(row.error, contains('413'));
  });

  test('count reflects multiple quarantined ops', () async {
    await quarantine.record(
      CrudEntry(1, UpdateType.put, 'dive_samples', 'd1', null, {'b': 1}),
      Exception('e1'),
    );
    await quarantine.record(
      CrudEntry(2, UpdateType.delete, 'dives', 'd2', null, null),
      Exception('e2'),
    );
    expect(await quarantine.count(), 2);

    // A delete op carries no payload.
    final del = await (db.select(db.syncQuarantine)
          ..where((t) => t.rowId.equals('d2')))
        .getSingle();
    expect(del.opData, isNull);
  });
}
