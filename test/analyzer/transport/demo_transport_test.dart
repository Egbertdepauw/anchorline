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

  test('emits at 5 Hz by default, like the real trimix SOLO', () {
    expect(demo().sampleInterval, const Duration(milliseconds: 200));
  });

  test('reads air until the gas arrives, then settles on 18.2/45.1', () {
    final t = demo();
    // 3 s of air at 5 Hz.
    final first = [
      for (var i = 0; i < 15; i++) parseSoloLine(t.emitSample())!
    ];
    for (final r in first) {
      expect(r.o2, closeTo(20.9, 0.05));
      expect(r.he, closeTo(0, 0.05));
    }
    // One more second of gas.
    var after1s = first.last;
    for (var i = 0; i < 5; i++) {
      after1s = parseSoloLine(t.emitSample())!;
    }
    expect(after1s.o2, lessThan(20.6), reason: 'gas arrives after 3 s');
    expect(after1s.he, greaterThan(5));

    for (var i = 0; i < 300; i++) {
      t.emitSample();
    }
    final settled = parseSoloLine(t.emitSample())!;
    expect(settled.o2, 18.2);
    expect(settled.he, 45.1);
  });

  test('the settling curve is the same in time at 1 Hz and 5 Hz', () {
    final fast = DemoAnalyzerTransport(
        random: Random(1), noiseAmplitude: 0, clock: () => fixedTime);
    final slow = DemoAnalyzerTransport(
        random: Random(1),
        noiseAmplitude: 0,
        sampleInterval: const Duration(seconds: 1),
        clock: () => fixedTime);
    for (var second = 1; second <= 20; second++) {
      String? fastLine;
      for (var i = 0; i < 5; i++) {
        fastLine = fast.emitSample();
      }
      final f = parseSoloLine(fastLine!)!;
      final s = parseSoloLine(slow.emitSample())!;
      expect(f.o2, closeTo(s.o2!, 0.1001), reason: 't = $second s');
      expect(f.he, closeTo(s.he!, 0.1001), reason: 't = $second s');
    }
  });

  test('target mix is configurable', () {
    final t = DemoAnalyzerTransport(
        targetO2: 10, targetHe: 70, random: Random(1), clock: () => fixedTime);
    for (var i = 0; i < 400; i++) {
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
    expect(lines, hasLength(25));

    await t.disconnect();
    await tester.pump(const Duration(seconds: 5));
    expect(lines, hasLength(25), reason: 'no lines after disconnect');
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
