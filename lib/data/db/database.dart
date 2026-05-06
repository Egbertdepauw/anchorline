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
  int get schemaVersion => 8;

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
          if (from < 8) {
            // Tables that existed at v1 always need the column added.
            await m.addColumn(diveAnnotations, diveAnnotations.ownerId);
            await m.addColumn(oxygenCells, oxygenCells.ownerId);
            await m.addColumn(scrubberSessions, scrubberSessions.ownerId);
            await m.addColumn(diveComputers, diveComputers.ownerId);
            // Tables created by earlier migration steps in this cascade
            // are already fresh-with-owner_id; only ALTER if they were
            // created before this run.
            if (from >= 2) {
              await m.addColumn(cylinders, cylinders.ownerId);
              await m.addColumn(pressureMappings, pressureMappings.ownerId);
            }
            if (from >= 3) {
              await m.addColumn(diveCylinders, diveCylinders.ownerId);
            }
          }
        },
      );
}
