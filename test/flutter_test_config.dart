import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '_helpers/strict_golden_comparator.dart';

/// Runs before every test file under `test/`.
///
/// `flutter test` sets [goldenFileComparator] to a [LocalFileComparator]
/// for the test file before calling this. Swap it for the strict one, so a
/// golden mismatch fails the test (#147).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final stock = goldenFileComparator;
  if (stock is LocalFileComparator) {
    // The comparator only keeps the test file's directory, so any file
    // name in it will do.
    goldenFileComparator =
        StrictLocalFileComparator(stock.basedir.resolve('_test.dart'));
  }
  await testMain();
}
