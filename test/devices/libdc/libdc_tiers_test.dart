import 'dart:io';

import 'package:ccrlogger/devices/libdc/libdc_tiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every checked family has its fixture file', () {
    for (final entry in kCheckedLibdcFamilies.entries) {
      final file =
          File('packages/libdivecomputer/test/fixtures/${entry.value}');
      expect(file.existsSync(), isTrue,
          reason: 'family ${entry.key} is listed as checked but '
              '${file.path} does not exist');
    }
  });

  test('the checked-families list starts empty, so every family is untested',
      () {
    expect(kCheckedLibdcFamilies, isEmpty);
    expect(isCheckedLibdcFamily(0), isFalse);
    expect(isCheckedLibdcFamily(17), isFalse);
  });
}
