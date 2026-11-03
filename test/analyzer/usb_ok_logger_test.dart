import 'dart:async';

import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/bridge/record_to_analysis.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transport driven by the test. The controllers are synchronous so a line
/// reaches the logger while the manual clock still shows the time it was
/// "received" at.
class FakeTransport implements AnalyzerTransport {
  final _lines = StreamController<String>.broadcast(sync: true);
  final _statuses = StreamController<AnalyzerConnectionStatus>.broadcast(
    sync: true,
  );
  AnalyzerConnectionStatus _status = AnalyzerConnectionStatus.connected;

  void emitLine(String line) => _lines.add(line);

  void emitStatus(AnalyzerConnectionStatus s) {
    _status = s;
    _statuses.add(s);
  }

  bool get hasLineListener => _lines.hasListener;

  @override
  String get name => 'Fake';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  AnalyzerConnectionStatus get status => _status;
  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _statuses.stream;
  @override
  String? get errorMessage => null;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
}

/// A SOLO line as the trimix model prints it.
String steadyLine(double o2, double he) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';

/// The wall clock the tests start at; `now()` is this plus the manual clock.
final _wallStart = DateTime.utc(2026, 11, 3, 15);

const _ean32 = DesiredMix(32, 0);

/// A logger on a [FakeTransport], a manual clock and recording fakes.
class Rig {
  Rig({
    this.printLabel = true,
    this.saveError,
    this.printError,
    this.markCompleteError,
    this.saveGate,
    this.saveResult = true,
    void Function(Object error, StackTrace stack)? onError,
    Duration? tickInterval,
  }) {
    logger = UsbOkLogger(
      save: (id, a) async {
        events.add('save');
        if (saveGate != null) await saveGate!.future;
        if (saveError != null) throw saveError!;
        saved.add((id: id, analysis: a));
        return saveResult;
      },
      markComplete: (id) async {
        events.add('markComplete');
        if (markCompleteError != null) throw markCompleteError!;
        completed.add(id);
      },
      printLabel: printLabel
          ? (a, copies) async {
              events.add('print');
              if (printError != null) throw printError!;
              printed.add((analysis: a, copies: copies));
            }
          : null,
      elapsed: () {
        elapsedReads++;
        return clock;
      },
      now: () => _wallStart.add(clock),
      tickInterval: tickInterval,
      onError: onError,
    );
    sub = logger.results.listen(results.add);
    logger.attach(transport);
  }

  final bool printLabel;
  final Object? saveError;
  final Object? printError;
  final Object? markCompleteError;
  final Completer<void>? saveGate;
  final bool saveResult;

  final transport = FakeTransport();
  late final UsbOkLogger logger;
  late final StreamSubscription<OkLogResult> sub;

  Duration clock = Duration.zero;

  /// How often the logger read the clock; with a timer and no lines going
  /// in, that is how often the timer fired.
  int elapsedReads = 0;
  final events = <String>[];
  final saved = <({String id, NewGasAnalysis analysis})>[];
  final printed = <({GasAnalysis analysis, int copies})>[];
  final completed = <String>[];
  final results = <OkLogResult>[];

  /// A line every 200 ms for [seconds], from the current clock. Leaves the
  /// clock on the last line and returns its time.
  Duration steady(double o2, double he, {required int seconds}) {
    final start = clock;
    for (var ms = 0; ms <= seconds * 1000; ms += 200) {
      clock = start + Duration(milliseconds: ms);
      transport.emitLine(steadyLine(o2, he));
    }
    return clock;
  }

  /// Goes quiet for [silence] and ticks once, as the 200 ms timer would.
  Future<void> silenceThenTick({
    Duration silence = const Duration(milliseconds: 2200),
  }) async {
    clock += silence;
    logger.tick();
    await pumpEventQueue();
  }

  /// Waits, in real time, until the logger's timer has fired at least
  /// [callbacks] more times. Call it with no lines going in.
  Future<void> waitForTimer({int callbacks = 3}) async {
    final target = elapsedReads + callbacks;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (elapsedReads < target) {
      if (DateTime.now().isAfter(deadline)) fail('the timer did not fire');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> close() async {
    await logger.dispose();
    await sub.cancel();
  }
}

void expectResult(
  OkLogResult r,
  FeedbackCode code,
  String text, {
  String? id,
  bool? idPresent,
  required bool complete,
}) {
  expect(r.code, code);
  expect(r.text, text);
  expect(r.complete, complete);
  if (id != null) expect(r.analysisId, id);
  if (idPresent != null) expect(r.analysisId != null, idPresent);
}

void main() {
  group('a hold becomes an analysis', () {
    test('an OK on a stable EAN32 with name and mix saves complete', () async {
      final rig = Rig();
      rig.logger.setupProvider = () => (
        setup: const LogOnOkSetup(analysedBy: 'EdP', desiredMix: _ean32),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      expect(rig.saved, hasLength(1));
      final a = rig.saved.single.analysis;
      expect(a.captureSource, CaptureSource.usbOk);
      expect(a.needsSignoff, isFalse);
      expect(a.stable, isTrue);
      expect(a.analysedBy, 'EdP');
      expect(a.o2Percent, closeTo(32.0, 0.001));
      expect(a.bridgeRecordId, startsWith('usb/'));
      expect(rig.printed, isEmpty);
      expect(rig.completed, isEmpty);
      expect(rig.results, hasLength(1));
      expectResult(
        rig.results.single,
        FeedbackCode.saved,
        'EAN32',
        id: rig.saved.single.id,
        complete: true,
      );
      await rig.close();
    });

    test(
      'print on OK prints a copy marked complete, then clears the flag',
      () async {
        final rig = Rig();
        rig.logger.setupProvider = () => (
          setup: const LogOnOkSetup(
            analysedBy: 'EdP',
            desiredMix: _ean32,
            printOnOk: true,
            printerConfigured: true,
          ),
          copies: 2,
        );
        rig.steady(32.0, 0.0, seconds: 25);
        await rig.silenceThenTick();

        final id = rig.saved.single.id;
        // Saved flagged, so a crash mid-print leaves an entry to sign off.
        expect(rig.saved.single.analysis.needsSignoff, isTrue);
        // The label is printed from a copy that is already "complete".
        expect(rig.printed, hasLength(1));
        expect(rig.printed.single.analysis.id, id);
        expect(rig.printed.single.analysis.needsSignoff, isFalse);
        expect(rig.printed.single.analysis.o2Percent, closeTo(32.0, 0.001));
        expect(rig.printed.single.copies, 2);
        // And only after the print does the stored flag clear.
        expect(rig.events, ['save', 'print', 'markComplete']);
        expect(rig.completed, [id]);
        expectResult(
          rig.results.single,
          FeedbackCode.printed,
          'EAN32',
          id: id,
          complete: true,
        );
        await rig.close();
      },
    );

    test('a failed print leaves the entry flagged', () async {
      final rig = Rig(printError: StateError('printer offline'));
      rig.logger.setupProvider = () => (
        setup: const LogOnOkSetup(
          analysedBy: 'EdP',
          desiredMix: _ean32,
          printOnOk: true,
          printerConfigured: true,
        ),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      expect(rig.events, ['save', 'print']);
      expect(rig.completed, isEmpty);
      expect(rig.results, hasLength(1));
      expectResult(
        rig.results.single,
        FeedbackCode.check,
        'PRINT FAILED',
        id: rig.saved.single.id,
        complete: false,
      );
      await rig.close();
    });

    test(
      'a failed markComplete after a print still reports the print',
      () async {
        final rig = Rig(markCompleteError: StateError('db busy'));
        rig.logger.setupProvider = () => (
          setup: const LogOnOkSetup(
            analysedBy: 'EdP',
            desiredMix: _ean32,
            printOnOk: true,
            printerConfigured: true,
          ),
          copies: 1,
        );
        rig.steady(32.0, 0.0, seconds: 25);
        await rig.silenceThenTick();

        // The label is out, but the row is still flagged: not complete.
        expectResult(
          rig.results.single,
          FeedbackCode.printed,
          'EAN32',
          id: rig.saved.single.id,
          complete: false,
        );
        await rig.close();
      },
    );

    test(
      'a print that is wanted but has no printer function is a check',
      () async {
        final rig = Rig(printLabel: false);
        rig.logger.setupProvider = () => (
          setup: const LogOnOkSetup(
            analysedBy: 'EdP',
            desiredMix: _ean32,
            printOnOk: true,
            printerConfigured: true,
          ),
          copies: 1,
        );
        rig.steady(32.0, 0.0, seconds: 25);
        await rig.silenceThenTick();

        expect(rig.completed, isEmpty);
        expectResult(
          rig.results.single,
          FeedbackCode.check,
          'NO PRINTER',
          id: rig.saved.single.id,
          complete: false,
        );
        await rig.close();
      },
    );

    test('room air is not saved', () async {
      final rig = Rig();
      rig.steady(20.9, 0.3, seconds: 25);
      await rig.silenceThenTick();

      expect(rig.events, isEmpty);
      expectResult(
        rig.results.single,
        FeedbackCode.skipped,
        'AIR - NOT LOGGED',
        idPresent: false,
        complete: false,
      );
      await rig.close();
    });

    test('an OK before stable saves flagged', () async {
      final rig = Rig();
      rig.logger.setupProvider = () => (
        setup: const LogOnOkSetup(analysedBy: 'EdP', desiredMix: _ean32),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 8);
      await rig.silenceThenTick();

      expect(rig.saved, hasLength(1));
      expect(rig.saved.single.analysis.stable, isFalse);
      expect(rig.saved.single.analysis.needsSignoff, isTrue);
      expectResult(
        rig.results.single,
        FeedbackCode.check,
        'NOT STABLE',
        id: rig.saved.single.id,
        complete: false,
      );
      await rig.close();
    });

    test('no setup provider: saved, needs sign-off', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      expect(rig.saved.single.analysis.needsSignoff, isTrue);
      expect(rig.saved.single.analysis.analysedBy, isNull);
      expect(rig.saved.single.analysis.desiredMix, isNull);
      expect(rig.printed, isEmpty);
      expectResult(
        rig.results.single,
        FeedbackCode.saved,
        'NO MIX SET',
        id: rig.saved.single.id,
        complete: false,
      );
      await rig.close();
    });

    test('a setup provider that throws is the same as none', () async {
      final rig = Rig();
      rig.logger.setupProvider = () => throw StateError('card disposed');
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      expectResult(
        rig.results.single,
        FeedbackCode.saved,
        'NO MIX SET',
        id: rig.saved.single.id,
        complete: false,
      );
      await rig.close();
    });

    test('a failed save is reported', () async {
      final rig = Rig(saveError: StateError('disk full'));
      rig.logger.setupProvider = () => (
        setup: const LogOnOkSetup(
          analysedBy: 'EdP',
          desiredMix: _ean32,
          printOnOk: true,
          printerConfigured: true,
        ),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      // Nothing is printed for a row that was not saved.
      expect(rig.events, ['save']);
      expect(rig.results, hasLength(1));
      expectResult(
        rig.results.single,
        FeedbackCode.error,
        'SAVE FAILED',
        idPresent: false,
        complete: false,
      );
      await rig.close();
    });

    test('save returning false is a failed save', () async {
      final rig = Rig(saveResult: false);
      rig.logger.setupProvider = () => (
        setup: const LogOnOkSetup(
          analysedBy: 'EdP',
          desiredMix: _ean32,
          printOnOk: true,
          printerConfigured: true,
        ),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      // The row was already there: nothing printed, nothing cleared.
      expect(rig.events, ['save']);
      expect(rig.printed, isEmpty);
      expect(rig.completed, isEmpty);
      expectResult(
        rig.results.single,
        FeedbackCode.error,
        'SAVE FAILED',
        idPresent: false,
        complete: false,
      );
      await rig.close();
    });

    test('errors reach onError', () async {
      final errors = <(Object, StackTrace)>[];
      final failure = StateError('disk full');
      final rig = Rig(
        saveError: failure,
        onError: (e, st) => errors.add((e, st)),
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      expect(errors, hasLength(1));
      expect(errors.single.$1, same(failure));
      expect(rig.results.single.text, 'SAVE FAILED');
      await rig.close();
    });

    test('print, mark-complete and setup errors reach onError too', () async {
      const printOk = LogOnOkSetup(
        analysedBy: 'EdP',
        desiredMix: _ean32,
        printOnOk: true,
        printerConfigured: true,
      );
      final printFailure = StateError('printer offline');
      final markFailure = StateError('db busy');
      final setupFailure = StateError('card disposed');
      final errors = <Object>[];

      final a = Rig(printError: printFailure, onError: (e, _) => errors.add(e));
      a.logger.setupProvider = () => (setup: printOk, copies: 1);
      a.steady(32.0, 0.0, seconds: 25);
      await a.silenceThenTick();
      await a.close();

      final b = Rig(
        markCompleteError: markFailure,
        onError: (e, _) => errors.add(e),
      );
      b.logger.setupProvider = () => (setup: printOk, copies: 1);
      b.steady(32.0, 0.0, seconds: 25);
      await b.silenceThenTick();
      await b.close();

      final c = Rig(onError: (e, _) => errors.add(e));
      c.logger.setupProvider = () => throw setupFailure;
      c.steady(32.0, 0.0, seconds: 25);
      await c.silenceThenTick();
      await c.close();

      expect(errors, [printFailure, markFailure, setupFailure]);
    });

    test('an onError that throws does not stop the logger', () async {
      final rig = Rig(
        saveError: StateError('disk full'),
        onError: (e, st) => throw StateError('the reporter is broken'),
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      expect(rig.results.single.text, 'SAVE FAILED');
      await rig.close();
    });

    test('analysed_at is the time of the held line', () async {
      final rig = Rig();
      final heldAt = rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      final tick = _wallStart.add(rig.clock);
      expect(rig.clock - heldAt, const Duration(milliseconds: 2200));
      final analysedAt = rig.saved.single.analysis.analysedAt;
      expect(tick.difference(analysedAt).inMilliseconds, closeTo(2200, 1));
      expect(analysedAt, _wallStart.add(heldAt));
      await rig.close();
    });

    test('the window handed on has only the lines since the resume', () async {
      final rig = Rig();
      // A first cylinder, a long OK pause, then the second.
      rig.steady(32.0, 0.0, seconds: 10);
      rig.clock += const Duration(seconds: 6);
      rig.steady(50.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      // Stable on the second gas alone: 50 % is not mixed with the 32 %.
      expect(rig.saved.single.analysis.o2Percent, closeTo(50.0, 0.001));
      expect(rig.saved.single.analysis.stable, isTrue);
      await rig.close();
    });
  });

  group('the stream', () {
    test('unplugging during the silence saves nothing', () async {
      for (final status in [
        AnalyzerConnectionStatus.disconnected,
        AnalyzerConnectionStatus.connecting,
        AnalyzerConnectionStatus.error,
      ]) {
        final rig = Rig();
        rig.steady(32.0, 0.0, seconds: 25);
        rig.clock += const Duration(seconds: 1);
        rig.transport.emitStatus(status);
        rig.clock += const Duration(seconds: 2);
        rig.logger.tick();
        await pumpEventQueue();

        expect(rig.events, isEmpty, reason: '$status');
        expect(rig.results, isEmpty, reason: '$status');
        await rig.close();
      }
    });

    test('a status of connected does not cancel a hold', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      rig.clock += const Duration(seconds: 1);
      rig.transport.emitStatus(AnalyzerConnectionStatus.connected);
      await rig.silenceThenTick(
        silence: const Duration(seconds: 1, milliseconds: 500),
      );
      expect(rig.saved, hasLength(1));
      await rig.close();
    });

    test('no lines, no hold', () async {
      final rig = Rig();
      rig.clock += const Duration(minutes: 1);
      rig.logger.tick();
      await pumpEventQueue();
      expect(rig.results, isEmpty);
      await rig.close();
    });

    test('one hold per silence: more ticks add nothing', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      await rig.silenceThenTick(silence: const Duration(seconds: 1));
      await rig.silenceThenTick(silence: const Duration(seconds: 10));
      expect(rig.saved, hasLength(1));
      expect(rig.results, hasLength(1));
      await rig.close();
    });

    test('after detach, lines no longer reach the detector', () async {
      final rig = Rig();
      rig.logger.detach();
      expect(rig.transport.hasLineListener, isFalse);
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      expect(rig.results, isEmpty);
      await rig.close();
    });

    test('attaching again starts a fresh flow', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      final other = FakeTransport();
      rig.logger.attach(other);
      expect(rig.transport.hasLineListener, isFalse);
      // The old flow is forgotten: one silence now makes no hold.
      await rig.silenceThenTick();
      expect(rig.results, isEmpty);
      // The new transport works.
      final start = rig.clock;
      for (var ms = 0; ms <= 25000; ms += 200) {
        rig.clock = start + Duration(milliseconds: ms);
        other.emitLine(steadyLine(32.0, 0.0));
      }
      await rig.silenceThenTick();
      expect(rig.results, hasLength(1));
      await rig.close();
    });
  });

  group('one hold at a time', () {
    test('a second hold waits for the first and none is dropped', () async {
      final gate = Completer<void>();
      final rig = Rig(saveGate: gate);
      // Each cylinder has its own mix in the setup, read when its hold is
      // handled.
      var setups = 0;
      rig.logger.setupProvider = () => (
        setup: LogOnOkSetup(
          analysedBy: 'EdP',
          desiredMix: setups++ == 0
              ? const DesiredMix(32, 0)
              : const DesiredMix(50, 0),
        ),
        copies: 1,
      );
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      // The first save is stuck.
      expect(rig.events, ['save']);
      expect(rig.results, isEmpty);

      // The diver presses OK again on another cylinder meanwhile.
      rig.steady(50.0, 0.0, seconds: 25);
      await rig.silenceThenTick();
      expect(rig.events, ['save'], reason: 'the second hold waits');

      gate.complete();
      await pumpEventQueue();
      expect(rig.events, ['save', 'save']);
      expect(rig.results, hasLength(2));
      expect(rig.saved.map((s) => s.analysis.o2Percent.round()), [32, 50]);
      expect(rig.saved[0].id, isNot(rig.saved[1].id));
      expectResult(
        rig.results[0],
        FeedbackCode.saved,
        'EAN32',
        id: rig.saved[0].id,
        complete: true,
      );
      expectResult(
        rig.results[1],
        FeedbackCode.saved,
        'EAN50',
        id: rig.saved[1].id,
        complete: true,
      );
      await rig.close();
    });

    test('a failure in one hold does not stop the next', () async {
      var calls = 0;
      final events = <OkLogResult>[];
      var clock = Duration.zero;
      final transport = FakeTransport();
      final logger = UsbOkLogger(
        save: (id, a) async {
          calls++;
          if (calls == 1) throw StateError('first one fails');
          return true;
        },
        markComplete: (_) async {},
        elapsed: () => clock,
        now: () => _wallStart.add(clock),
        tickInterval: null,
      );
      final sub = logger.results.listen(events.add);
      logger.attach(transport);
      for (var round = 0; round < 2; round++) {
        final start = clock;
        for (var ms = 0; ms <= 25000; ms += 200) {
          clock = start + Duration(milliseconds: ms);
          transport.emitLine(steadyLine(32.0, 0.0));
        }
        clock += const Duration(milliseconds: 2200);
        logger.tick();
        await pumpEventQueue();
      }
      expect(events.map((e) => e.text), ['SAVE FAILED', 'NO MIX SET']);
      await logger.dispose();
      await sub.cancel();
    });
  });

  group('lifecycle', () {
    test('the timer ticks the detector', () async {
      final rig = Rig(tickInterval: const Duration(milliseconds: 10));
      rig.steady(32.0, 0.0, seconds: 25);
      // Nobody calls tick(): the timer finds the silence itself.
      rig.clock += const Duration(milliseconds: 2200);
      final r = await rig.logger.results.first.timeout(
        const Duration(seconds: 5),
      );
      expect(r.text, 'NO MIX SET');
      await rig.close();
    });

    test('a stall while the SOLO streams is not an OK press', () async {
      final rig = Rig(tickInterval: const Duration(milliseconds: 10));
      rig.steady(32.0, 0.0, seconds: 7);
      await rig.waitForTimer(); // the timer has seen the clock at 7 s

      // The process stalls for 3 s. The timer is due before the lines that
      // queued up are delivered, and the last line is now 3 s old.
      rig.clock += const Duration(seconds: 3);
      await rig.waitForTimer();

      // Now the queued lines arrive, with fresh delivery times.
      final resumed = rig.clock;
      for (var ms = 0; ms <= 800; ms += 200) {
        rig.clock = resumed + Duration(milliseconds: ms);
        rig.transport.emitLine(steadyLine(32.0, 0.0));
      }
      await rig.waitForTimer(); // still inside the grace
      rig.clock += const Duration(milliseconds: 400); // the grace is over
      await rig.waitForTimer();

      expect(rig.events, isEmpty);
      expect(rig.results, isEmpty);
      await rig.close();
    });

    test('an OK during a stall still counts after the grace', () async {
      final rig = Rig(tickInterval: const Duration(milliseconds: 10));
      final heldAt = rig.steady(32.0, 0.0, seconds: 7);
      await rig.waitForTimer();

      // The process stalls for 3 s and no line ever comes again: that was
      // an OK press. Inside the 1 s grace nothing is decided.
      rig.clock += const Duration(seconds: 3);
      await rig.waitForTimer();
      rig.clock += const Duration(milliseconds: 500);
      await rig.waitForTimer();
      expect(rig.events, isEmpty);
      expect(rig.results, isEmpty);

      // The grace is over: the first tick finds the hold.
      final first = rig.logger.results.first;
      rig.clock += const Duration(milliseconds: 500);
      await first.timeout(const Duration(seconds: 5));

      expect(rig.saved, hasLength(1));
      expect(rig.saved.single.analysis.analysedAt, _wallStart.add(heldAt));
      await rig.close();
    });

    test('with no tick interval there is no timer', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      rig.clock += const Duration(seconds: 5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.results, isEmpty);
      await rig.close();
    });

    test('dispose waits for a hold in flight, then closes results', () async {
      final gate = Completer<void>();
      final rig = Rig(saveGate: gate);
      final all = rig.logger.results.toList();
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.silenceThenTick();

      var disposed = false;
      final done = rig.logger.dispose().then((_) => disposed = true);
      await pumpEventQueue();
      expect(disposed, isFalse, reason: 'the save is still running');
      gate.complete();
      await done;
      final list = await all;
      expect(list, hasLength(1));
      expect(list.single.text, 'NO MIX SET');
      await rig.sub.cancel();
    });

    test('tick after dispose does nothing', () async {
      final rig = Rig();
      rig.steady(32.0, 0.0, seconds: 25);
      await rig.close();
      rig.clock += const Duration(seconds: 3);
      rig.logger.tick();
      await pumpEventQueue();
      expect(rig.events, isEmpty);
    });
  });
}
