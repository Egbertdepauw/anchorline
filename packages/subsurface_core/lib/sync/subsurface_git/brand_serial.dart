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
  String? product,
  required int parserVersion,
  required int? dcFamily,
}) {
  final legacyHexCopy = !isShearwaterByNames(vendor, product, dcFamily) &&
      vendor != null &&
      dcFamily == null &&
      parserVersion == kSubsurfaceImportedParserVersion;
  if (!legacyHexCopy) return storedSerial;
  return int.tryParse(storedSerial.toRadixString(16)) ?? storedSerial;
}

/// Whether a dive is a Shearwater dive by its stored names. No
/// libdivecomputer family, and either no vendor or Shearwater, or a vendor
/// and product that together name a Shearwater model: a vendor-less
/// Subsurface copy such as "Perdix 2" is read as vendor "Perdix", product
/// "2". Shares its rule with the Subsurface writer's `isOtherBrand`.
bool isShearwaterByNames(String? vendor, String? product, int? dcFamily) {
  if (dcFamily != null) return false;
  if (vendor == null || vendor == kShearwaterVendor) return true;
  return shearwaterModelFromProduct('$vendor ${product ?? ''}'.trim()) !=
      ShearwaterModel.unknown;
}
