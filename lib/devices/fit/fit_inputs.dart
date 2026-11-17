/// What the user picked for a FIT import.
library;

sealed class FitInput {
  const FitInput(this.path);

  final String path;
}

/// One picked file: a `.fit` file or a `.zip` (a Garmin export).
class FitFileInput extends FitInput {
  const FitFileInput(super.path);
}

/// A picked folder, read recursively.
class FitFolderInput extends FitInput {
  const FitFolderInput(super.path);
}

/// "Garmin Descent Mk1", or the product alone when it already starts with the
/// vendor ("Garmin product 4999"); just the vendor without a product.
String fitModelLabel(String vendor, String? product) {
  if (product == null || product.isEmpty) return vendor;
  return product.toLowerCase().startsWith(vendor.toLowerCase())
      ? product
      : '$vendor $product';
}

/// How far a scan has come. The total grows while zips are opened.
class FitScanCounts {
  FitScanCounts({
    this.filesRead = 0,
    this.filesTotal,
    this.dives = 0,
    this.otherActivities = 0,
    this.apnea = 0,
    this.unreadable = 0,
    this.outOfSpace = false,
  });

  int filesRead;
  int? filesTotal;
  int dives;
  int otherActivities;
  int apnea;
  int unreadable;

  /// The disk filled up while reading, and the scan stopped there.
  bool outOfSpace;

  FitScanCounts copy() => FitScanCounts(
    filesRead: filesRead,
    filesTotal: filesTotal,
    dives: dives,
    otherActivities: otherActivities,
    apnea: apnea,
    unreadable: unreadable,
    outOfSpace: outOfSpace,
  );
}
