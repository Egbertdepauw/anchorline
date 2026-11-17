// Product names for Garmin dive computers, ids and names taken as facts from
// Subsurface's garmin-models.h (trademark signs dropped).

/// FIT manufacturer ids we name.
const int kFitManufacturerGarmin = 1;
const int kFitManufacturerSuunto = 23;

const Map<int, String> _garminProducts = {
  2859: 'Descent Mk1',
  2991: 'Descent Mk1',
  3258: 'Descent Mk2/Mk2i',
  3702: 'Descent Mk2/Mk2i',
  3542: 'Descent Mk2 S',
  3930: 'Descent Mk2 S',
  4005: 'Descent G1',
  4588: 'Descent G2',
  4222: 'Descent Mk3 43 mm',
  4223: 'Descent Mk3 51 mm',
  4518: 'Descent X50i',
  4532: 'fēnix 8',
  4533: 'fēnix 8',
  4534: 'fēnix 8',
  4536: 'fēnix 8',
  4631: 'fēnix 8',
  4775: 'fēnix 8',
  4776: 'fēnix 8',
};

/// The brand name for a FIT manufacturer id.
String fitVendorName(int manufacturer) => switch (manufacturer) {
  kFitManufacturerGarmin => 'Garmin',
  kFitManufacturerSuunto => 'Suunto',
  _ => 'FIT manufacturer $manufacturer',
};

/// The product name: the Garmin table first, else the file's own product
/// name with a leading vendor name removed, else a numbered placeholder.
String fitProductName({
  required int manufacturer,
  int? product,
  String? productName,
}) {
  if (manufacturer == kFitManufacturerGarmin && product != null) {
    final known = _garminProducts[product];
    if (known != null) return known;
  }
  final name = productName?.trim();
  if (name != null && name.isNotEmpty) {
    final vendor = fitVendorName(manufacturer);
    if (name.length > vendor.length &&
        name.toLowerCase().startsWith('${vendor.toLowerCase()} ')) {
      return name.substring(vendor.length).trim();
    }
    return name;
  }
  final label = manufacturer == kFitManufacturerGarmin
      ? 'Garmin product'
      : 'product';
  return '$label ${product ?? 0}';
}
