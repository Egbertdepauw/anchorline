import 'dart:async';
import 'dart:math';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/fake_elapsed.dart';

/// Transport driven by hand: the test pushes lines with [send].
class FakeTransport implements AnalyzerTransport {
  final _lines = StreamController<String>.broadcast();
  final _status = StreamController<AnalyzerConnectionStatus>.broadcast();
  AnalyzerConnectionStatus _current = AnalyzerConnectionStatus.disconnected;
  bool disposed = false;

  void send(String line) => _lines.add(line);

  void setStatus(AnalyzerConnectionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  @override
  String get name => 'Fake';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  AnalyzerConnectionStatus get status => _current;
  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _status.stream;
  @override
  String? get errorMessage => null;
  @override
  Future<void> connect() async =>
      setStatus(AnalyzerConnectionStatus.connected);
  @override
  Future<void> disconnect() async {
    if (_current != AnalyzerConnectionStatus.disconnected) {
      setStatus(AnalyzerConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    // Not awaited: a broadcast controller's done future only completes
    // once the done event is delivered, which callers need not wait for.
    unawaited(_lines.close());
    unawaited(_status.close());
  }
}

const _airLine = 'He 0.0 O2 20.9 % Ti 21.4 ~C 1013.2 hPa 2026/10/27 20:30:00';
const _errorLine =
    'He ***.* O2 20.9 % Ti 21.4 ~C 1013.2 hPa 2026/10/27 20:30:01';

void main() {
  testWidgets('demo gas settles from SETTLING to STABLE on 18.2/45.1',
      (tester) async {
    final c = AnalyzerController(elapsed: fakeElapsed(tester));
    expect(c.stability, ReadingStability.noData);
    await c.connect(DemoAnalyzerTransport(random: Random(3)));
    expect(c.isConnected, isTrue);

    final seen = <ReadingStability>{};
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(seconds: 1));
      seen.add(c.stability);
      if (i < 20) {
        expect(c.stability, isNot(ReadingStability.stable),
            reason: 'needs 20 s of data at 5 Hz too (t = ${i + 1} s)');
      }
    }
    expect(seen, contains(ReadingStability.settling));
    expect(c.stability, ReadingStability.stable);
    expect(c.latest!.o2, 18.2);
    expect(c.latest!.he, 45.1);
    expect(c.noDataHint, isFalse);

    await c.disconnect();
    expect(c.isConnected, isFalse);
    c.dispose();
  });

  testWidgets('history keeps two minutes of elapsed time at 5 Hz',
      (tester) async {
    final c = AnalyzerController(elapsed: fakeElapsed(tester));
    await c.connect(DemoAnalyzerTransport(random: Random(3)));
    await tester.pump(const Duration(seconds: 150));
    expect(c.historyNowSeconds, closeTo(150, 1e-6));
    expect(c.history.last.seconds, c.historyNowSeconds);
    expect(c.history.first.seconds, closeTo(30, 1e-6));
    // 30 s … 150 s inclusive at 200 ms spacing.
    expect(c.history, hasLength(601));
    await c.disconnect();
    c.dispose();
  });

  testWidgets('history and stability use real time at 1 Hz too',
      (tester) async {
    final c = AnalyzerController(elapsed: fakeElapsed(tester));
    await c.connect(DemoAnalyzerTransport(
      random: Random(3),
      sampleInterval: const Duration(seconds: 1),
    ));
    await tester.pump(const Duration(seconds: 150));
    expect(c.history.first.seconds, closeTo(30, 1e-6));
    expect(c.history, hasLength(121));
    expect(c.stability, ReadingStability.stable);
    await c.disconnect();
    c.dispose();
  });

  testWidgets('samples are timed by arrival, not by count', (tester) async {
    final c = AnalyzerController(elapsed: fakeElapsed(tester));
    final t = FakeTransport();
    await c.connect(t);
    // A burst of 15 lines at once, then one 2 s later.
    for (var i = 0; i < 15; i++) {
      t.send(_airLine);
    }
    await tester.pump(const Duration(seconds: 2));
    t.send(_airLine);
    await tester.pump();
    expect(c.history, hasLength(16));
    expect(c.history.first.seconds, 0);
    expect(c.history[14].seconds, 0);
    expect(c.historyNowSeconds, closeTo(2, 1e-6));
    expect(c.stability, ReadingStability.settling);
    await c.disconnect();
    c.dispose();
  });

  testWidgets('an asterisk line is a SENSOR ERROR', (tester) async {
    final c = AnalyzerController();
    final t = FakeTransport();
    await c.connect(t);
    t.send(_airLine);
    await tester.pump();
    expect(c.stability, ReadingStability.settling);

    t.send(_errorLine);
    await tester.pump();
    expect(c.stability, ReadingStability.sensorError);
    expect(c.latest!.he!.isNaN, isTrue);
    expect(c.history.last.he.isNaN, isTrue);

    t.send(_airLine);
    await tester.pump();
    expect(c.stability, ReadingStability.settling,
        reason: 'recovers, but must re-earn stability');
    await c.disconnect();
    c.dispose();
  });

  testWidgets('garbage lines are ignored', (tester) async {
    final c = AnalyzerController();
    final t = FakeTransport();
    await c.connect(t);
    t.send('Divesoft SOLO v1.2');
    t.send('');
    await tester.pump();
    expect(c.latest, isNull);
    expect(c.stability, ReadingStability.noData);
    expect(c.history, isEmpty);
    await c.disconnect();
    c.dispose();
  });

  testWidgets('no-data hint after ~4 s of silence while connected',
      (tester) async {
    final c = AnalyzerController();
    final t = FakeTransport();
    await c.connect(t);
    await tester.pump(const Duration(seconds: 3));
    expect(c.noDataHint, isFalse);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(c.noDataHint, isTrue);

    t.send(_airLine);
    await tester.pump();
    expect(c.noDataHint, isFalse, reason: 'cleared by the first line');

    await tester.pump(const Duration(seconds: 5));
    expect(c.noDataHint, isTrue, reason: 'raised again when lines stop');

    await c.disconnect();
    expect(c.noDataHint, isFalse);
    expect(t.disposed, isTrue, reason: 'controller owns the transport');
    c.dispose();
  });

  testWidgets('no hint when the transport is not connected', (tester) async {
    final c = AnalyzerController();
    final t = FakeTransport();
    await c.connect(t);
    t.setStatus(AnalyzerConnectionStatus.error);
    await tester.pump(const Duration(seconds: 10));
    expect(c.noDataHint, isFalse);
    expect(c.status, AnalyzerConnectionStatus.error);
    await c.disconnect();
    c.dispose();
  });
}
