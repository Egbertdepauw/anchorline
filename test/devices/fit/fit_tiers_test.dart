import 'dart:io';

import 'package:ccrlogger/devices/fit/fit_tiers.dart';
import 'package:ccrlogger/devices/libdc/libdc_tiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every checked model has its fixture file', () {
    for (final entry in kCheckedFitModels.entries) {
      final file = File('packages/fit_reader/test/fixtures/${entry.value}');
      expect(file.existsSync(), isTrue,
          reason: '${entry.key} is listed as checked but ${file.path} '
              'does not exist');
    }
  });

  test('a model that is not listed is not checked', () {
    expect(isCheckedFitModel('Descent Mk3'), isFalse);
    for (final m in kCheckedFitModels.keys) {
      expect(isCheckedFitModel(m), isTrue);
    }
  });

  test('the badge text is the libdivecomputer one', () {
    expect(kNotYetTestedLabel, 'Not yet tested by us');
  });
}
