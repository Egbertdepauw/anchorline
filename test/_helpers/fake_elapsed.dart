import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Elapsed time on the widget test's fake clock, so an
/// [AnalyzerController]'s time base advances with `tester.pump(duration)`
/// instead of real time (its default is a real [Stopwatch]).
Duration Function() fakeElapsed(WidgetTester tester) {
  final start = tester.binding.clock.now();
  return () => tester.binding.clock.now().difference(start);
}

/// An [AnalyzerController] on the fake clock, disposed after the test.
AnalyzerController fakeClockAnalyzerController(WidgetTester tester) {
  final c = AnalyzerController(elapsed: fakeElapsed(tester));
  addTearDown(c.dispose);
  return c;
}
