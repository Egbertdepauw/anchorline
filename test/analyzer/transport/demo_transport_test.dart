import 'dart:async';
import 'dart:math';

import 'package:ccrlogger/analyzer/protocol/solo_line_parser.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedTime = DateTime(2026, 10, 27, 20, 30, 5);

  DemoAnalyzerTransport demo() =>
      DemoAnalyzerTransport(random: Random(7), clock: () => fixedTime);

  test('formatLine produces the SOLO trimix format the parser reads', () {
    final line = DemoAnalyzerTransport.formatLine(
      o2: 18.2,
      he: 45.1,
      tempC: 21.4,
      baroHpa: 1013.2,
      time: fixedTime,
    );
    expect(line,
        'He 45.1 O2 18.2 % Ti 21.4 ~C 1013.2 hPa 2026/10/27 20:30:05');
    final r = parseSoloLine(line)!;
    expect(r.o2, 18.2);
    expect(r.he, 45.1);
    expect(r.tempC, 21.4);
    expect(r.baroHpa, 1013.2);
    expect(r.deviceTime, fixedTime);
  });

  test('reads air until the gas arrives, then settles on 18.2/45.1', () {
    final t = demo();
    final first = [for (var i = 0; i < 3; i++) parseSoloLine(t.emitSample())!];
    for (final r in first) {
      expect(r.o2, closeTo(20.9, 0.05));
      expect(r.he, closeTo(0, 0.05));
    }
    final fourth = parseSoloLine(t.emitSample())!;
    expect(fourth.o2, lessThan(20.6), reason: 'gas arrives after 3 samples');
    expect(fourth.he, greaterThan(5));

    for (var i = 0; i < 60; i++) {
      t.emitSample();
    }
    final settled = parseSoloLine(t.emitSample())!;
    expect(settled.o2, 18.2);
    expect(settled.he, 45.1);
  });

  test('target mix is configurable', () {
    final t = DemoAnalyzerTransport(
        targetO2: 10, targetHe: 70, random: Random(1), clock: () => fixedTime);
    for (var i = 0; i < 80; i++) {
      t.emitSample();
    }
    final r = parseSoloLine(t.emitSample())!;
    expect(r.o2, 10.0);
    expect(r.he, 70.0);
  });

  testWidgets('emits one line per interval while connected', (tester) async {
    final t = demo();
    final lines = <String>[];
    final statuses = <AnalyzerConnectionStatus>[];
    final ls = t.lines.listen(lines.add);
    final ss = t.statusChanges.listen(statuses.add);

    expect(t.status, AnalyzerConnectionStatus.disconnected);
    await t.connect();
    expect(t.status, AnalyzerConnectionStatus.connected);
    await tester.pump(const Duration(seconds: 5));
    expect(lines, hasLength(5));

    await t.disconnect();
    await tester.pump(const Duration(seconds: 5));
    expect(lines, hasLength(5), reason: 'no lines after disconnect');
    expect(t.status, AnalyzerConnectionStatus.disconnected);
    expect(statuses, [
      AnalyzerConnectionStatus.connecting,
      AnalyzerConnectionStatus.connected,
      AnalyzerConnectionStatus.disconnected,
    ]);

    // Not awaited: a broadcast cancel returns a root-zone future that
    // never completes under the widget-test fake clock.
    unawaited(ls.cancel());
    unawaited(ss.cancel());
    await t.dispose();
  });
}
