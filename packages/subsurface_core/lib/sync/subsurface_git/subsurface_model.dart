/// Reading Subsurface's `model` and `Serial` lines for any dive computer
/// brand. Pure Dart.
library;

import '../../shearwater/parser/hardware.dart';

/// Vendor names that contain a space, so a model line cannot be split on
/// its first space alone.
///
/// Taken from upstream libdivecomputer's `src/descriptor.c` (master as of
/// 2026-04-18): the only vendors there with a space in the name.
const List<String> kMultiWordVendors = [
  'Atomic Aquatics',
  'Deep Six',
  'Dive Rite',
  'Heinrichs Weikamp',
];

/// Splits a Subsurface `model` line ("Shearwater Petrel 3") into vendor and
/// product. Returns null for a model without a space and for Subsurface's
/// placeholder `'manually added dive'`.
({String vendor, String product})? splitSubsurfaceModel(String model) {
  final m = model.trim();
  if (m == 'manually added dive') return null;
  for (final v in kMultiWordVendors) {
    if (m.startsWith('$v ') && m.length > v.length + 1) {
      return (vendor: v, product: m.substring(v.length + 1).trim());
    }
  }
  final i = m.indexOf(' ');
  if (i <= 0 || i == m.length - 1) return null;
  return (vendor: m.substring(0, i), product: m.substring(i + 1).trim());
}

/// Parses the text of Subsurface's `Serial` keyvalue. Shearwater (and a
/// missing vendor, the pre-brand reading) writes hex; most other upstream
/// parsers write decimal. Non-Shearwater text falls back to hex, then 0.
int parseSubsurfaceSerial(String? vendor, String text) {
  final t = text.trim();
  if (vendor == null || vendor == kShearwaterVendor) {
    return int.tryParse(t, radix: 16) ?? 0;
  }
  return int.tryParse(t) ?? int.tryParse(t, radix: 16) ?? 0;
}

/// Every reading of [serial] that a Subsurface copy may be stored or keyed
/// under. Every serial-keyed match against Subsurface copies must accept
/// both readings, because copies stored before brands were read carry the
/// hex reading of the Serial text.
///
/// A Shearwater or null vendor gives just [serial]. Any other vendor also
/// gets the old hex reading of the decimal digits (null if not valid hex).
Set<int> subsurfaceSerialForms(String? vendor, int serial) {
  if (vendor == null || vendor == kShearwaterVendor) return {serial};
  final hexReading = int.tryParse('$serial', radix: 16);
  return {serial, ?hexReading};
}

/// Inverse of [shearwaterProductName]. Anything unrecognised, including a
/// null product, is [ShearwaterModel.unknown].
ShearwaterModel shearwaterModelFromProduct(String? product) {
  if (product == null) return ShearwaterModel.unknown;
  for (final m in ShearwaterModel.values) {
    if (shearwaterProductName(m) == product) return m;
  }
  return ShearwaterModel.unknown;
}
