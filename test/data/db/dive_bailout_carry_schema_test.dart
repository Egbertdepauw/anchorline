import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dive_bailout_carry table is registered and queryable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.cylinders).insert(CylindersCompanion.insert(
          id: 'cyl-a',
          label: 'AL40',
          role: 'bailout',
          bailoutOrder: const Value(1),
          volumeLiters: 5.7,
          workingPressureBar: 207,
          createdAt: 0,
          updatedAt: 0,
        ));
    expect(await db.select(db.diveBailoutCarry).get(), isEmpty);

    await db.into(db.diveBailoutCarry).insert(
          DiveBailoutCarryCompanion.insert(
            id: 'd1:cyl-a',
            diveId: 'd1',
            cylinderId: 'cyl-a',
            gasMix: '21/35',
            bailoutOrder: 1,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    final rows = await db.select(db.diveBailoutCarry).get();
    expect(rows, hasLength(1));
    expect(rows.single.gasMix, '21/35');
    expect(rows.single.fillPressureBar, isNull);
    await db.close();
  });
}
