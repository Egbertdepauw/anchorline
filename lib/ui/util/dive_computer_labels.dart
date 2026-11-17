/// What the dive screens call a dive's computer: its model name and serial.
///
/// A Shearwater dive keeps the names and the 8-digit hex serial the screens
/// always showed. Any other brand shows the stored vendor and product, and
/// its serial in decimal. The name never depends on the engine family being
/// known to this build: it reads only `dcVendor` and `dcProduct`, so a dive
/// from a family a later build adds, or a Garmin FIT dive (`dcFamily` -1),
/// shows the same way.
library;

import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/sync/subsurface_git/brand_serial.dart';

import '../../data/db/database.dart';

/// True for a dive from a Shearwater computer: no libdivecomputer family and
/// no vendor, or Shearwater as the vendor.
bool isShearwaterDive(Dive d) =>
    d.dcFamily == null &&
    (d.dcVendor == null || d.dcVendor == kShearwaterVendor);

/// "Divesoft Liberty" for another brand; the existing Shearwater model name
/// ("Shearwater Petrel 3") for a Shearwater dive.
String diveComputerName(Dive d) {
  if (isShearwaterDive(d)) return _shearwaterName(d.dcModel);
  return _brandName(d);
}

/// The short label on the mode badge: the Shearwater model's enum name
/// ("petrel3") as always, or the vendor and product for another brand.
String diveComputerBadgeName(Dive d) {
  if (!isShearwaterDive(d)) return _brandName(d);
  return d.dcModel >= 0 && d.dcModel < ShearwaterModel.values.length
      ? ShearwaterModel.values[d.dcModel].name
      : 'Unknown';
}

/// 8 hex digits for a Shearwater dive, as today; the decimal serial for any
/// other brand.
String diveComputerSerialText(Dive d) {
  if (isShearwaterDive(d)) {
    return d.dcSerial.toRadixString(16).padLeft(8, '0');
  }
  return brandSerialOf(
    storedSerial: d.dcSerial,
    vendor: d.dcVendor,
    parserVersion: d.parserVersion,
    dcFamily: d.dcFamily,
  ).toString();
}

String _brandName(Dive d) {
  final vendor = d.dcVendor?.trim() ?? '';
  final product = d.dcProduct?.trim() ?? '';
  final name = [vendor, product].where((s) => s.isNotEmpty).join(' ');
  return name.isEmpty ? 'Unknown' : name;
}

String _shearwaterName(int modelIdx) {
  final values = ShearwaterModel.values;
  if (modelIdx < 0 || modelIdx >= values.length) return 'Unknown';
  return switch (values[modelIdx]) {
    ShearwaterModel.predator => 'Shearwater Predator',
    ShearwaterModel.petrel => 'Shearwater Petrel',
    ShearwaterModel.petrel2 => 'Shearwater Petrel 2',
    ShearwaterModel.petrel3 => 'Shearwater Petrel 3',
    ShearwaterModel.nerd => 'Shearwater NERD',
    ShearwaterModel.nerd2 => 'Shearwater NERD 2',
    ShearwaterModel.perdix => 'Shearwater Perdix',
    ShearwaterModel.perdixAi => 'Shearwater Perdix AI',
    ShearwaterModel.perdix2 => 'Shearwater Perdix 2',
    ShearwaterModel.teric => 'Shearwater Teric',
    ShearwaterModel.peregrine => 'Shearwater Peregrine',
    ShearwaterModel.peregrineTx => 'Shearwater Peregrine TX',
    ShearwaterModel.tern => 'Shearwater Tern',
    ShearwaterModel.unknown => 'Shearwater (unknown)',
  };
}
