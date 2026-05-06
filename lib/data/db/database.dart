/// CCRLogger Drift database definition.
library;

import 'package:drift/drift.dart';

import 'dive_annotations_dao.dart';
import 'equipment_dao.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Dives,
    DiveSamples,
    DiveAnnotations,
    DiveComputers,
    OxygenCells,
    ScrubberSessions,
    Cylinders,
    PressureMappings,
    DiveCylinders,
    ImportStates,
  ],
  daos: [EquipmentDao, DiveAnnotationsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 7;

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
          if (from < 3) {
            await m.createTable(diveCylinders);
          }
          if (from < 4) {
            await m.addColumn(dives, dives.configuredStackSeconds);
            await m.addColumn(dives, dives.stackRemainingAtStartSeconds);
            await m.addColumn(dives, dives.stackRemainingAtEndSeconds);
          }
          if (from < 5) {
            await m.addColumn(dives, dives.tanksJson);
          }
          if (from < 6) {
            await m.addColumn(diveSamples, diveSamples.tankPressuresBlob);
          }
          if (from < 7) {
            await m.addColumn(dives, dives.subsurfaceUploadedAt);
          }
        },
      );
}
