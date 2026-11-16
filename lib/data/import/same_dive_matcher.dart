import 'package:subsurface_core/sync/subsurface_git/subsurface_model.dart'
    show subsurfaceSerialForms;

/// Two start times this many seconds apart or less are the same dive.
const int kSameDiveWindowSeconds = 60;

/// The columns of a stored `dives` row that identify it for matching.
class StoredDiveKey {
  final String id;
  final String? dcVendor;
  final int dcSerial;

  /// Start time in epoch seconds.
  final int startTime;
  final int parserVersion;
  final int? dcFamily;

  const StoredDiveKey({
    required this.id,
    required this.dcVendor,
    required this.dcSerial,
    required this.startTime,
    required this.parserVersion,
    required this.dcFamily,
  });

  /// Builds a key from a `dives` row (PowerSync column names).
  factory StoredDiveKey.fromRow(Map<String, Object?> row) => StoredDiveKey(
        id: row['id']! as String,
        dcVendor: row['dc_vendor'] as String?,
        dcSerial: (row['dc_serial']! as num).toInt(),
        startTime: (row['start_time']! as num).toInt(),
        parserVersion: (row['parser_version']! as num).toInt(),
        dcFamily: (row['dc_family'] as num?)?.toInt(),
      );
}

/// The brand a stored row stands for. A NULL vendor reads as Shearwater on a
/// download and as null ("any brand") on a Subsurface copy from before phase
/// 1, so the stored value is returned as is and a null matches any brand.
String? effectiveVendor(String? dcVendor, int parserVersion) => dcVendor;

/// Stored dives that are the same dive as an incoming download.
///
/// Matches when the stored brand equals [vendor] (or is unknown), the stored
/// serial is one of the forms [subsurfaceSerialForms] gives for the incoming
/// serial, the start times are within [kSameDiveWindowSeconds] and the id is
/// not [excludeId]. Soft-deleted rows count: a deleted copy keeps a download
/// hidden, as a deleted download does.
List<StoredDiveKey> findSameDive({
  required String vendor,
  required int serial,
  required int startTimeSeconds,
  required String excludeId,
  required Iterable<StoredDiveKey> stored,
}) {
  final serials = subsurfaceSerialForms(vendor, serial);
  return [
    for (final k in stored)
      if (k.id != excludeId &&
          (effectiveVendor(k.dcVendor, k.parserVersion) ?? vendor) == vendor &&
          serials.contains(k.dcSerial) &&
          (k.startTime - startTimeSeconds).abs() <= kSameDiveWindowSeconds)
        k,
  ];
}
