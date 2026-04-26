/// CCRLogger Drift database definition.
library;

import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Dives,
  DiveSamples,
  DiveAnnotations,
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  Cylinders,
  PressureMappings,
  ImportStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(oxygenCells, oxygenCells.label);
            await m.createTable(cylinders);
            await m.createTable(pressureMappings);
          }
        },
      );
}
