import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_state_reporter.dart';
import 'package:ccrlogger/analyzer/protocol/analyzer_reading.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:flutter_test/flutter_test.dart';

AnalyzerReading _r(double? o2, double? he) =>
    AnalyzerReading(o2: o2, he: he, raw: '');

void main() {
  group('liveStateFor', () {
    test('no reading gives nothing', () {
      expect(liveStateFor(null, ReadingStability.noData), isNull);
    });

    test('NaN O2 is a sensor error', () {
      final s = liveStateFor(_r(double.nan, 0), ReadingStability.settling);
      expect(s?.state, BridgeLiveState.sensorError);
      expect(s?.mix, isNull);
    });

    test('O2 of zero or less is a sensor error', () {
      expect(
        liveStateFor(_r(0, 0), ReadingStability.stable)?.state,
        BridgeLiveState.sensorError,
      );
      expect(
        liveStateFor(_r(null, 0), ReadingStability.stable)?.state,
        BridgeLiveState.sensorError,
      );
    });

    test('the detector saying sensor error is a sensor error', () {
      expect(
        liveStateFor(_r(32, double.nan), ReadingStability.sensorError)?.state,
        BridgeLiveState.sensorError,
      );
    });

    test('20.9/0 is air', () {
      final s = liveStateFor(_r(20.9, 0), ReadingStability.stable);
      expect(s?.state, BridgeLiveState.air);
      expect(s?.mix, isNull);
    });

    test('stable EAN32', () {
      final s = liveStateFor(_r(32.1, 0.2), ReadingStability.stable);
      expect(s?.state, BridgeLiveState.stable);
      expect(s?.mix, 'EAN32');
    });

    test('settling trimix, also right after a reset', () {
      expect(
        liveStateFor(_r(21, 35), ReadingStability.settling),
        (state: BridgeLiveState.settling, mix: 'Tx21/35'),
      );
      expect(
        liveStateFor(_r(21, 35), ReadingStability.noData)?.state,
        BridgeLiveState.settling,
      );
    });
  });

  group('BridgeStateReporter', () {
    testWidgets('sends on change, not on repeats, and resends after 3 s',
        (tester) async {
      final sent = <String>[];
      final reporter = BridgeStateReporter(send: (m) async => sent.add(m));
      reporter.start();

      reporter.update(_r(32, 0), ReadingStability.settling);
      reporter.update(_r(32.1, 0), ReadingStability.settling);
      expect(sent, ['STATE settling EAN32']);

      reporter.update(_r(32, 0), ReadingStability.stable);
      expect(sent, ['STATE settling EAN32', 'STATE stable EAN32']);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(sent, hasLength(2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(sent, hasLength(3));
      expect(sent.last, 'STATE stable EAN32');
      await tester.pump(kStateHeartbeat);
      expect(sent, hasLength(4));

      reporter.stop();
      await tester.pump(const Duration(seconds: 10));
      expect(sent, hasLength(4), reason: 'stopped');
    });

    testWidgets('a change resets the heartbeat', (tester) async {
      final sent = <String>[];
      final reporter = BridgeStateReporter(send: (m) async => sent.add(m));
      reporter.start();
      reporter.update(_r(32, 0), ReadingStability.settling);
      await tester.pump(const Duration(seconds: 2));
      reporter.update(_r(32, 0), ReadingStability.stable);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(sent, hasLength(2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(sent, hasLength(3));
      reporter.stop();
    });

    testWidgets('nothing is sent before start or without a reading',
        (tester) async {
      final sent = <String>[];
      final reporter = BridgeStateReporter(send: (m) async => sent.add(m));
      reporter.update(_r(32, 0), ReadingStability.stable);
      expect(sent, isEmpty);

      reporter.start();
      reporter.update(null, ReadingStability.noData);
      await tester.pump(const Duration(seconds: 10));
      expect(sent, isEmpty);

      reporter.update(_r(32, 0), ReadingStability.stable);
      expect(sent, ['STATE stable EAN32']);

      // A restart sends the same state again on its first update.
      reporter.stop();
      reporter.start();
      reporter.update(_r(32, 0), ReadingStability.stable);
      expect(sent, hasLength(2));
      reporter.stop();
    });

    testWidgets('a send that throws does not stop the reporter',
        (tester) async {
      var calls = 0;
      final reporter = BridgeStateReporter(send: (m) async {
        calls++;
        throw StateError('link gone');
      });
      reporter.start();
      reporter.update(_r(32, 0), ReadingStability.stable);
      await tester.pump(kStateHeartbeat);
      expect(calls, 2);
      reporter.stop();
    });
  });
}
