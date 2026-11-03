import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LocalFileComparator] whose mismatches always fail the test.
///
/// The stock comparator reports a mismatch by throwing a [FlutterError].
/// When `matchesGoldenFile` gets a `ui.Image`, it compares inside
/// `binding.runAsync` and only catches [TestFailure]. `runAsync` catches the
/// [FlutterError], passes it to [FlutterError.reportError] and returns null,
/// which the matcher reads as a match. `testWidgets` turns that report into
/// a failure, but a plain `test()` does not, so the golden passes on any
/// difference (#147). The cylinder label goldens are plain tests.
///
/// This comparator throws a [TestFailure] instead, which the matcher returns
/// as the mismatch in both kinds of test.
///
/// The comparison itself is the stock one: it only passes when no pixel
/// differs. Failure images still go to `failures/` next to the test.
/// `test/flutter_test_config.dart` installs it for every test.
class StrictLocalFileComparator extends LocalFileComparator {
  StrictLocalFileComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    try {
      if (result.passed) return true;
      throw TestFailure(await generateFailureOutput(result, golden, basedir));
    } finally {
      result.dispose();
    }
  }
}
