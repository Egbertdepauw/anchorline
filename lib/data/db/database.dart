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
    DivePlans,
    DiveBailoutCarry,
    ImportStates,
    DiveMergeLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 17;

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
          if (from < 14) {
            // User per-dive override of which deco algorithm to display.
            // Nullable TEXT ('zhl16c' or 'vpmb'); NULL = use default
            // (ZHL-16C). Existing rows get NULL.
            await m.addColumn(
                diveAnnotations, diveAnnotations.displayDecoAlgorithm);
          }
          if (from < 15) {
            // Cylinders become physical-only (volume + pressure). Per-dive
            // gas now lives in dive_bailout_carry. SQLite < 3.35 had no
            // ALTER DROP COLUMN; alterTable rebuilds the table.
            // Guard with a sqlite_master probe so partial test fixtures
            // that never created `cylinders` don't crash here — production
            // databases always have it by v8.
            final hasCylinders = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'cylinders'",
            ).get();
            if (hasCylinders.isNotEmpty) {
              await m.alterTable(TableMigration(cylinders));
            }
            await m.createTable(diveBailoutCarry);
          }
          if (from < 16) {
            await m.createTable(divePlans);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_dive_plans_owner_draft '
              'ON dive_plans (owner_id) '
              'WHERE name IS NULL AND deleted_at IS NULL',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_dive_plans_owner_updated '
              'ON dive_plans (owner_id, deleted_at, updated_at DESC)',
            );
          }
          if (from < 17) {
            await m.createTable(diveMergeLinks);
          }
        },
      );
}
