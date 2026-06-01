import 'dart:typed_data';

import 'package:ccrlogger/ui/widgets/profile_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // x = sample index; y flat so a contour's length equals its x-span.
  double xOf(int i) => i.toDouble();
  double yOf(double v) => 0.0;

  test('contiguous data yields a single subpath', () {
    final data = Float32List.fromList([1, 2, 3, 4]);
    final path = buildBrokenTracePath(data, 4, xOf, yOf);
    expect(path.computeMetrics().length, 1);
  });

  test('a NaN gap splits the trace into two subpaths (not erased)', () {
    // This is the merged-dive case: a NaN surface gap in the middle. The old
    // single-Path builder produced a NaN-poisoned path that Skia dropped
    // entirely (the bug). Now it must yield two drawable segments.
    final data = Float32List.fromList([1, 2, double.nan, double.nan, 5, 6]);
    final path = buildBrokenTracePath(data, 6, xOf, yOf);
    final contours = path.computeMetrics().toList();
    expect(contours.length, 2);
    // Each real segment spans 1 unit in x (samples 0->1 and 4->5).
    expect(contours[0].length, closeTo(1.0, 1e-6));
    expect(contours[1].length, closeTo(1.0, 1e-6));
  });

  test('leading and trailing NaN are skipped', () {
    final data = Float32List.fromList([double.nan, 2, 3, double.nan]);
    final path = buildBrokenTracePath(data, 4, xOf, yOf);
    final contours = path.computeMetrics().toList();
    expect(contours.length, 1); // only the 2->3 segment
    expect(contours.single.length, closeTo(1.0, 1e-6));
  });

  test('all-NaN data yields an empty (non-throwing) path', () {
    final data = Float32List.fromList([double.nan, double.nan]);
    final path = buildBrokenTracePath(data, 2, xOf, yOf);
    expect(path.computeMetrics().isEmpty, isTrue);
  });
}
