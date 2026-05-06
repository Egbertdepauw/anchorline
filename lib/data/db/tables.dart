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

/// User-managed cylinders (O2, diluent, bailout, offboard).
class Cylinders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()(); // "AL40 stage", "12L steel"
  TextColumn get role => text()(); // 'oxygen' | 'diluent' | 'bailout' | 'offboard'
  IntColumn get bailoutOrder => integer().nullable()(); // only when role == 'bailout'
  RealColumn get volumeLiters => real()();
  IntColumn get workingPressureBar => integer()();
  TextColumn get gasMix => text().nullable()(); // "21/35", "100", null
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
