import 'package:ccrlogger/ui/licences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerLicences adds a libdivecomputer entry with the LGPL text',
      () async {
    registerLicences();
    final entries = await LicenseRegistry.licenses.toList();
    final entry = entries.firstWhere(
      (e) => e.packages.contains('libdivecomputer'),
    );
    final text = entry.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 2.1'));
    // Keep the bundled asset in step with the file in the package.
    expect(
      (await rootBundle.loadString(kLibdcLicenceAsset)).trim(),
      isNotEmpty,
    );
  });
}
