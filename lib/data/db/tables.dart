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

  /// Original decompressed binary blob (for re-parsing).
  BlobColumn get rawBlob => blob()();

  /// Parser version that produced the cached parse.
  IntColumn get parserVersion => integer()();

  /// When this dive was imported.
  IntColumn get importedAt => integer()();

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

  @override
  Set<Column> get primaryKey => {id};
}

/// O2 cell tracking.
class OxygenCells extends Table {
  TextColumn get id => text()();
  IntColumn get slot => integer()(); // 1, 2, or 3
  IntColumn get installedDate => integer().nullable()();
  IntColumn get retiredDate => integer().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

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
