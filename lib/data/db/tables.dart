/// Drift table definitions for the CCRLogger database.
///
/// Follows CLAUDE.md architectural principles:
/// - Imported data is immutable (dives, dive_samples) — no sync metadata.
/// - User-editable entities have sync metadata (annotations, equipment).
/// - Samples are columnar packed blobs, not row-per-sample.
/// - Metric in the database, always.
library;

import 'package:drift/drift.dart';

/// Immutable dive records imported from the dive computer.
class Dives extends Table {
  /// Stable ID: hash(serial, diveNumber, startTimestamp).
  TextColumn get id => text()();
  IntColumn get dcSerial => integer()();
  IntColumn get dcDiveNumber => integer()();

  /// Unix timestamp (seconds UTC).
  IntColumn get startTime => integer()();
  IntColumn get endTime => integer()();
  IntColumn get utcOffsetMinutes => integer().nullable()();

  /// Duration in seconds.
  IntColumn get durationSeconds => integer()();

  /// Max depth in millimeters (integer precision, always metric).
  IntColumn get maxDepthMm => integer()();

  /// Dive mode code (DiveMode.value).
  IntColumn get diveMode => integer()();

  /// Deco model code (DecoModel.value).
  IntColumn get decoModel => integer()();
  IntColumn get gfLow => integer().nullable()();
  IntColumn get gfHigh => integer().nullable()();

  IntColumn get atmosphericPressureMbar => integer()();
  IntColumn get waterDensity => integer()();
  IntColumn get logVersion => integer()();

  /// ShearwaterModel index.
  IntColumn get dcModel => integer()();
  IntColumn get dcFirmware => integer().nullable()();

  IntColumn get sampleIntervalMs => integer()();

  /// Gas mixes as JSON array.
  TextColumn get gasMixesJson => text()();

  /// Tanks as JSON array. Null when the parser produced no tank metadata
  /// (no AI configured, OC dives without tank pressure, etc).
  TextColumn get tanksJson => text().nullable()();

  /// Per-cell calibration factors as a JSON array of doubles. Length 3
  /// on CCR; null on OC (or older imports made before the column existed).
  /// Used to derive per-cell PPO2 from raw mV at display/export time:
  /// `ppo2_bar = mV * cal / 1000`. The Petrel factory default is 0.021.
  TextColumn get sensorCalibrationJson => text().nullable()();

  /// Scrubber stack time (seconds). All null when the diver hasn't
  /// enabled stack tracking on the unit.
  IntColumn get configuredStackSeconds => integer().nullable()();
  IntColumn get stackRemainingAtStartSeconds => integer().nullable()();
  IntColumn get stackRemainingAtEndSeconds => integer().nullable()();

  /// Original decompressed binary blob (for re-parsing).
  BlobColumn get rawBlob => blob()();

  /// Parser version that produced the cached parse.
  IntColumn get parserVersion => integer()();

  /// When this dive was imported.
  IntColumn get importedAt => integer()();

  /// When this dive was last exported to a Subsurface .ssrf file
  /// (unix seconds). Null = pending.
  IntColumn get subsurfaceUploadedAt => integer().nullable()();

  /// Soft-delete timestamp (millis since epoch). Null = visible.
  /// User-driven via the dive list; restore via the SnackBar undo.
  /// Imported data is otherwise immutable, so we keep the row + raw blob
  /// — re-importing the same dive id finds the soft-deleted row and
  /// resurrects it instead of inserting a duplicate.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Columnar sample data — one row per dive, packed binary blobs.
class DiveSamples extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  IntColumn get sampleCount => integer()();

  // Each column is independently gzipped for partial reads.
  BlobColumn get depthBlob => blob()();
  BlobColumn get temperatureBlob => blob()();
  BlobColumn get ppo2Blob => blob()();
  BlobColumn get cellMv0Blob => blob()();
  BlobColumn get cellMv1Blob => blob()();
  BlobColumn get cellMv2Blob => blob()();
  BlobColumn get setpointBlob => blob()();
  BlobColumn get cnsBlob => blob()();
  BlobColumn get decoDepthBlob => blob()();
  BlobColumn get decoTimeBlob => blob()();
  BlobColumn get ttsBlob => blob()();
  BlobColumn get gasMixIdxBlob => blob()();
  BlobColumn get statusBlob => blob()();

  /// Combined per-tank pressure trace blob (gzipped Float32 channels with
  /// a small header). Null for OC dives and pre-v6 imports.
  BlobColumn get tankPressuresBlob => blob().nullable()();

  @override
  Set<Column> get primaryKey => {diveId};
}

/// Local-only storage of the raw Shearwater binary blob, keyed by
/// `dive_id`. Phase 2.5 split: dive metadata + samples sync via
/// PowerSync, but the raw blob stays on the importing device — it's
/// only needed for re-parsing after a parser bug fix, and not worth
/// the bandwidth/storage to mirror across devices.
///
/// One row per dive; absent on devices that didn't import the dive.
class DiveRawBlobs extends Table {
  TextColumn get diveId => text()();
  BlobColumn get rawBlob => blob()();

  @override
  Set<Column> get primaryKey => {diveId};
}

/// User-editable dive annotations.
class DiveAnnotations extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  TextColumn get siteName => text().nullable()();
  IntColumn get siteLatitudeE5 => integer().nullable()();
  IntColumn get siteLongitudeE5 => integer().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get buddiesJson => text().nullable()();
  TextColumn get tagsJson => text().nullable()();
  IntColumn get rating => integer().nullable()();
  TextColumn get conditions => text().nullable()();
  TextColumn get divemaster => text().nullable()();

  // Subsurface "Information" tab — environmental ratings (1..5; null =
  // unrated, mirroring the existing `rating` convention) plus measured
  // air/water temperatures and weight-system entries. Matches the data
  // already living in users' Subsurface git repos so Subsurface →
  // CCRLog import round-trips losslessly.
  IntColumn get visibility => integer().nullable()();
  IntColumn get wavesize => integer().nullable()();
  IntColumn get current => integer().nullable()();
  IntColumn get surge => integer().nullable()();
  IntColumn get chill => integer().nullable()();
  RealColumn get airTempC => real().nullable()();
  RealColumn get waterTempC => real().nullable()();

  /// JSON array of `{"weight_kg": double, "description": string}` objects,
  /// one per `weightsystem` line in Subsurface. Null = no weight entries.
  TextColumn get weightsJson => text().nullable()();

  /// User per-dive override of which deco algorithm to display.
  /// Values: 'zhl16c' or 'vpmb'. NULL = use default (ZHL-16C).
  TextColumn get displayDecoAlgorithm => text().nullable()();

  /// User-assigned dive number (renumbering). NULL = automatic date sequence.
  IntColumn get userDiveNumber => integer().nullable()();

  // Sync metadata.
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {diveId};
}

/// Known dive computers.
class DiveComputers extends Table {
  TextColumn get id => text()();
  IntColumn get serial => integer().unique()();
  IntColumn get model => integer()();
  IntColumn get firmwareVersion => integer().nullable()();
  TextColumn get nickname => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// O2 cell tracking.
class OxygenCells extends Table {
  TextColumn get id => text()();
  IntColumn get slot => integer()(); // 1, 2, or 3
  TextColumn get label => text().nullable()(); // e.g. "Analytical R-22D #1234"
  IntColumn get installedDate => integer().nullable()();
  IntColumn get retiredDate => integer().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Scrubber session tracking.
class ScrubberSessions extends Table {
  TextColumn get id => text()();
  IntColumn get startedDate => integer().nullable()();
  IntColumn get totalMinutes => integer().nullable()();
  TextColumn get mediaType => text().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-managed cylinders (physical vessels). Volume + working pressure;
/// per-dive gas is recorded in [DiveBailoutCarry] / `dive_cylinders`.
class Cylinders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()(); // "AL40 stage", "12L steel"
  TextColumn get role => text()(); // 'oxygen' | 'diluent' | 'bailout' | 'offboard'
  IntColumn get bailoutOrder => integer().nullable()(); // only when role == 'bailout'
  RealColumn get volumeLiters => real()();
  IntColumn get workingPressureBar => integer()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-DC mapping from pressure-channel index to a Cylinder.
class PressureMappings extends Table {
  TextColumn get diveComputerId => text()();
  IntColumn get channelIndex => integer()(); // 0, 1, 2, ... as logged
  TextColumn get cylinderId => text().nullable()(); // FK to Cylinders.id; null = unmapped

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {diveComputerId, channelIndex};
}

/// Per-dive linkage of gas mixes to physical cylinders.
///
/// One row per (diveId, gasMixIndex). `gasMixIndex` indexes into
/// `Dives.gasMixesJson`. `cylinderId` is nullable — null means the user
/// hasn't yet decided which cylinder held that mix.
class DiveCylinders extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  IntColumn get gasMixIndex => integer()();
  TextColumn get cylinderId => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {diveId, gasMixIndex};
}

/// Per-dive list of OC bailout cylinders the diver carried.
/// One row per (diveId, cylinderId). The composite is encoded into [id]
/// as `<diveId>:<cylinderId>` so PowerSync syncs it under a single PK.
class DiveBailoutCarry extends Table {
  TextColumn get id => text()();
  TextColumn get diveId => text().references(Dives, #id)();
  TextColumn get cylinderId => text().references(Cylinders, #id)();
  TextColumn get gasMix => text()(); // "21/35", "100", "32"
  IntColumn get fillPressureBar =>
      integer().nullable()(); // null → use cylinder.workingPressureBar
  IntColumn get bailoutOrder => integer()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Multilevel dive plans (CC + Bailout v1, OC future). One row per
/// plan: a single per-user "draft" row (name IS NULL) auto-saves on
/// edit; named rows are explicitly saved plans. Body is JSON-encoded
/// because gases/segments/bottles are always loaded as a unit.
class DivePlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get mode => text()(); // 'cc' or 'oc'
  TextColumn get gasesJson => text()();
  TextColumn get segmentsJson => text()();
  TextColumn get bailoutJson => text()();
  TextColumn get settingsJson => text().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Import state for incremental sync per dive computer.
class ImportStates extends Table {
  /// Dive computer serial as string.
  TextColumn get dcSerial => text()();

  /// Last successfully imported dive fingerprint (4 bytes).
  BlobColumn get lastFingerprint => blob().nullable()();

  /// When the last import happened.
  IntColumn get lastImportAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {dcSerial};
}

/// Links a dive into a merge group. A dive belongs to at most one group,
/// so `diveId` is the primary key. A group "exists" while >=2 non-deleted
/// links share a `groupId`. Unmerge = soft-delete the links.
class DiveMergeLinks extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  TextColumn get groupId => text()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {diveId};
}

/// Local, device-only, re-derivable cache of per-dive stats that require
/// decoding the sample blob (water temperature extremes, time-in-deco).
/// Keyed by dive id; `parserVersion` mirrors the dive's parser version so a
/// re-parse invalidates the row. Not synced — recomputed per device.
class DiveDerivedStats extends Table {
  TextColumn get diveId => text()();
  IntColumn get parserVersion => integer()();
  RealColumn get minWaterTempC => real().nullable()();
  RealColumn get maxWaterTempC => real().nullable()();
  IntColumn get timeInDecoSeconds => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveId};
}

/// CRUD upload ops the backend permanently rejected, recorded so a single
/// "poison" op can't wedge the FIFO upload queue forever (issue #2). The
/// connector skips such an op (so the queue drains) and writes it here, where
/// the diagnostic surfaces the count ("N changes couldn't sync") and a future
/// re-drive can replay them after the underlying cause is fixed.
///
/// Local-only — NOT sync-eligible (it records failures of the sync itself, and
/// is meaningful only on the device that hit them).
class SyncQuarantine extends Table {
  /// Surrogate key — the same row id can be quarantined more than once.
  IntColumn get id => integer().autoIncrement()();

  /// The op's PowerSync `CrudEntry.clientId`.
  IntColumn get opClientId => integer()();

  /// `put` / `patch` / `delete`.
  TextColumn get opType => text()();

  /// The Postgres/PowerSync table the op targeted (named `targetTable` to
  /// avoid clashing with drift's built-in `Table.tableName`).
  TextColumn get targetTable => text()();
  TextColumn get rowId => text()();

  /// JSON of the op's payload (for a future re-drive); null for deletes.
  TextColumn get opData => text().nullable()();

  /// String form of the backend rejection that quarantined the op.
  TextColumn get error => text()();

  /// When it was quarantined (epoch milliseconds).
  IntColumn get quarantinedAt => integer()();
}
