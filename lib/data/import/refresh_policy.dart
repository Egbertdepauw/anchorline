import 'package:subsurface_core/shearwater/parser/dive_converter.dart'
    show ConvertedDive;

// Only the constant is used; this file stays free of database and Flutter code.
import '../../sync/subsurface_git/bootstrap_importer.dart'
    show kSubsurfaceImportedParserVersion;

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

/// A parse worth writing over stored data: it has samples and a duration.
bool isUsableParse(ConvertedDive c) =>
    c.samples.sampleCount > 0 && c.dive.duration > Duration.zero;
