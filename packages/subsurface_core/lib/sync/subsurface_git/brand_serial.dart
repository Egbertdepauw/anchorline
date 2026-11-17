/// Undoing the legacy hex reading of a decimal serial. Pure Dart.
library;

import '../../shearwater/parser/hardware.dart';
import 'subsurface_model.dart';

/// The serial to show for a dive, as the brand writes it.
///
/// A Subsurface copy of a non-Shearwater dive that was stored before brands
/// were read carries the hex reading of Subsurface's decimal `Serial` text.
/// Such a copy has a vendor that is not Shearwater, no `dc_family` and the
/// sentinel parser version. For it this returns the decimal digits read back
/// out of the stored value ([subsurfaceSerialForms] is the matching side of
/// the same rule). Anything else returns [storedSerial] unchanged.
int brandSerialOf({
  required int storedSerial,
  required String? vendor,
  required int parserVersion,
  required int? dcFamily,
}) {
  final legacyHexCopy = vendor != null &&
      vendor != kShearwaterVendor &&
      dcFamily == null &&
      parserVersion == kSubsurfaceImportedParserVersion;
  if (!legacyHexCopy) return storedSerial;
  return int.tryParse(storedSerial.toRadixString(16)) ?? storedSerial;
}
