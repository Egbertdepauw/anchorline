import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bundled LGPL-2.1 text that ships with the vendored libdivecomputer
/// source. Declared as an asset in `pubspec.yaml`.
const kLibdcLicenceAsset =
    'packages/libdivecomputer/third_party/libdivecomputer/COPYING';

/// Adds libdivecomputer to the licence page (`showLicensePage`). Flutter
/// collects the entries lazily, so the asset is only read when the page opens.
void registerLicences() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kLibdcLicenceAsset);
    yield LicenseEntryWithLineBreaks(['libdivecomputer'], text);
  });
}
