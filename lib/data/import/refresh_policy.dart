import 'package:subsurface_core/subsurface_core.dart'
    show ConvertedDive, kFitDcFamily, kSubsurfaceImportedParserVersion;

/// The reader that produced a dive, told from its `dc_family`.
enum DiveEngine { shearwater, libdc, fit }

/// The engine of a row or incoming dive with the given `dc_family`: null is
/// Shearwater, [kFitDcFamily] (-1) is FIT, any other value is
/// libdivecomputer. (Not to be confused with `parser_version == -1`, the
/// Subsurface copy marker.)
DiveEngine diveEngineOf(int? dcFamily) => switch (dcFamily) {
      null => DiveEngine.shearwater,
      kFitDcFamily => DiveEngine.fit,
      _ => DiveEngine.libdc,
    };

/// Whether a download may overwrite the imported data of a stored dive.
///
/// A Subsurface Cloud copy (`parser_version == -1`) is always replaced by a
/// real download. Otherwise only a newer version of the same engine may
/// refresh: another engine never rewrites a download, and an equal or older
/// version never does either. Engines are compared through [diveEngineOf].
bool refreshMayWrite({
  required int storedVersion,
  required int? storedFamily,
  required int incomingVersion,
  required int? incomingFamily,
}) {
  if (storedVersion == kSubsurfaceImportedParserVersion) return true;
  return diveEngineOf(storedFamily) == diveEngineOf(incomingFamily) &&
      incomingVersion > storedVersion;
}

/// Whether an incoming dive of family [incomingFamily] may write to a stored
/// row at all, raw blob included. A Subsurface copy without a family may take
/// any family. Otherwise the engines must match ([diveEngineOf]), and a set
/// `dc_family` never changes, so it must equal the incoming one.
bool refreshEnginesAgree({
  required int storedVersion,
  required int? storedFamily,
  required int? incomingFamily,
}) {
  if (storedVersion == kSubsurfaceImportedParserVersion &&
      storedFamily == null) {
    return true;
  }
  if (diveEngineOf(storedFamily) != diveEngineOf(incomingFamily)) return false;
  return storedFamily == null || storedFamily == incomingFamily;
}

/// A parse worth writing over stored data: it has samples and a duration.
bool isUsableParse(ConvertedDive c) =>
    c.samples.sampleCount > 0 && c.dive.duration > Duration.zero;
