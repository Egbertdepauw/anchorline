import 'package:subsurface_core/subsurface_core.dart'
    show ConvertedDive, kSubsurfaceImportedParserVersion;

/// Whether a download may overwrite the imported data of a stored dive.
///
/// A Subsurface Cloud copy (`parser_version == -1`) is always replaced by a
/// real download. Otherwise only a newer version of the same engine may
/// refresh: another engine never rewrites a download, and an equal or older
/// version never does either. A row's engine is libdivecomputer exactly when
/// its `dc_family` is set.
bool refreshMayWrite({
  required int storedVersion,
  required bool storedIsLibdc,
  required int incomingVersion,
  required bool incomingIsLibdc,
}) {
  if (storedVersion == kSubsurfaceImportedParserVersion) return true;
  return storedIsLibdc == incomingIsLibdc && incomingVersion > storedVersion;
}

/// Whether an incoming dive of family [incomingFamily] may write to a stored
/// row at all, raw blob included. A set `dc_family` never changes, so it must
/// equal the incoming one. A row without a family is either a Subsurface copy
/// (which a download may give a family) or a Shearwater download (which only a
/// Shearwater dive may touch).
bool refreshEnginesAgree({
  required int storedVersion,
  required int? storedFamily,
  required int? incomingFamily,
}) {
  if (storedFamily != null) return incomingFamily == storedFamily;
  if (storedVersion == kSubsurfaceImportedParserVersion) return true;
  return incomingFamily == null;
}

/// A parse worth writing over stored data: it has samples and a duration.
bool isUsableParse(ConvertedDive c) =>
    c.samples.sampleCount > 0 && c.dive.duration > Duration.zero;
