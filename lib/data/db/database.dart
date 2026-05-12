/// CCRLogger Drift database definition.
library;

import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Dives,
    DiveSamples,
    DiveRawBlobs,
    DiveAnnotations,
    DiveComputers,
    OxygenCells,
    ScrubberSessions,
    Cylinders,
    PressureMappings,
    DiveCylinders,
    ImportStates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 13;

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
          if (from < 9) {
            await m.addColumn(dives, dives.deletedAt);
          }
          if (from < 10) {
            // New local-only raw-blob storage; live data is migrated by
            // DivesPowerSyncBackfiller on app startup.
            await m.createTable(diveRawBlobs);
          }
          if (from < 11) {
            // Per-cell sensor calibration factors persisted at import
            // time. JSON-encoded list of doubles; null for legacy rows
            // (callers fall back to the Petrel default 0.021).
            await m.addColumn(dives, dives.sensorCalibrationJson);
          }
          if (from < 12) {
            // Subsurface "Information" tab fields — env ratings, air/water
            // temps, weight-system entries. All nullable; existing rows
            // get NULL until the user (or a Subsurface re-import) fills
            // them in.
            await m.addColumn(diveAnnotations, diveAnnotations.visibility);
            await m.addColumn(diveAnnotations, diveAnnotations.wavesize);
            await m.addColumn(diveAnnotations, diveAnnotations.current);
            await m.addColumn(diveAnnotations, diveAnnotations.surge);
            await m.addColumn(diveAnnotations, diveAnnotations.chill);
            await m.addColumn(diveAnnotations, diveAnnotations.airTempC);
            await m.addColumn(diveAnnotations, diveAnnotations.waterTempC);
            await m.addColumn(diveAnnotations, diveAnnotations.weightsJson);
          }
          if (from < 13) {
            // Divemaster string — new per-annotation field exposing the
            // Subsurface "divemaster" line that we previously emitted as
            // empty. Nullable; existing rows get NULL.
            await m.addColumn(diveAnnotations, diveAnnotations.divemaster);
          }
        },
      );
}
