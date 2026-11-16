import 'package:subsurface_core/subsurface_core.dart'
    show
        kShearwaterVendor,
        kSubsurfaceImportedParserVersion,
        subsurfaceSerialForms;

/// Two start times this many seconds apart or less are the same dive.
const int kSameDiveWindowSeconds = 60;

/// The columns of a stored `dives` row that identify it for matching.
class StoredDiveKey {
  final String id;
  final String? dcVendor;
  final int dcSerial;

  /// The computer's own dive number (a Subsurface copy carries Subsurface's
  /// logbook number instead).
  final int dcDiveNumber;

  /// Start time in epoch seconds.
  final int startTime;
  final int parserVersion;
  final int? dcFamily;

  const StoredDiveKey({
    required this.id,
    required this.dcVendor,
    required this.dcSerial,
    required this.dcDiveNumber,
    required this.startTime,
    required this.parserVersion,
    required this.dcFamily,
  });

  /// Builds a key from a `dives` row (PowerSync column names).
  factory StoredDiveKey.fromRow(Map<String, Object?> row) => StoredDiveKey(
        id: row['id']! as String,
        dcVendor: row['dc_vendor'] as String?,
        dcSerial: (row['dc_serial']! as num).toInt(),
        dcDiveNumber: (row['dc_dive_number']! as num).toInt(),
        startTime: (row['start_time']! as num).toInt(),
        parserVersion: (row['parser_version']! as num).toInt(),
        dcFamily: (row['dc_family'] as num?)?.toInt(),
      );
}

/// The brand a stored row stands for. A NULL vendor reads as Shearwater on a
/// download and as null ("any brand") on a Subsurface copy from before phase
/// 1 (`parser_version == -1`).
String? effectiveVendor(String? dcVendor, int parserVersion) =>
    dcVendor ??
    (parserVersion == kSubsurfaceImportedParserVersion
        ? null
        : kShearwaterVendor);

/// Stored dives that are the same dive as an incoming download.
///
/// Matches when the stored brand equals [vendor] (or is unknown), the stored
/// serial is one of the forms [subsurfaceSerialForms] gives for the incoming
/// serial, the start times are within [kSameDiveWindowSeconds] and the id is
/// not [excludeId]. Soft-deleted rows count: a deleted copy keeps a download
/// hidden, as a deleted download does.
///
/// [diveNumber] is the incoming dive's `dc_dive_number` when it is a download,
/// null when it is a Subsurface copy. When non-null, a stored download
/// (`parser_version >= 0`) matches only with the same dive number: two
/// different dives from one computer differ in dive number, and a refreshed
/// copy carries the download's number, so a re-download still finds it. Stored
/// copies (-1) are not compared on number, since theirs is Subsurface's
/// logbook number. libdivecomputer dives (number 0 on both sides) keep the
/// time-window rule until phase 2.
List<StoredDiveKey> findSameDive({
  required String vendor,
  required int serial,
  required int startTimeSeconds,
  required String excludeId,
  int? diveNumber,
  required Iterable<StoredDiveKey> stored,
}) {
  final serials = subsurfaceSerialForms(vendor, serial);
  return [
    for (final k in stored)
      if (k.id != excludeId &&
          (effectiveVendor(k.dcVendor, k.parserVersion) ?? vendor) == vendor &&
          serials.contains(k.dcSerial) &&
          (diveNumber == null ||
              k.parserVersion == kSubsurfaceImportedParserVersion ||
              k.dcDiveNumber == diveNumber) &&
          (k.startTime - startTimeSeconds).abs() <= kSameDiveWindowSeconds)
        k,
  ];
}
