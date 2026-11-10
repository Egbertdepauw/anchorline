import 'dart:async';

import 'package:ccrlogger/analyzer/bridge/bridge_ok_handler.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/bridge/record_to_analysis.dart';
import 'package:ccrlogger/analyzer/ok_logger.dart';
import 'package:ccrlogger/analyzer/ok_record_processor.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

const _bridgeId = 'a0b1c2d3e4f5';
final _now = DateTime.utc(2026, 11, 9, 15);

/// A SOLO line as the trimix model prints it.
String _soloLine(double o2, double he) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   2026/11/09 15:00:00';

String _hello({int boot = 7, int up = 10000}) =>
    'HELLO proto=1 fw=1.0.0 bridge=$_bridgeId epoch=1a2b3c4d boot=$boot '
    'up=$up solo=1 rec=on vbus=off batt=3987 pending=1';

/// The lines of one record: 30 s of [o2]/[he] at 1 s spacing, then the
/// held line.
List<String> _recordLines(
  String rid, {
  double o2 = 32,
  double he = 0,
  int boot = 7,
  int up = 9000,
  bool live = true,
}) => [
  'REC $rid boot=$boot up=$up wall=0 live=${live ? 1 : 0}',
  for (var s = -30; s <= 0; s++) 'W ${s * 1000} ${_soloLine(o2, he)}',
  'H ${_soloLine(o2, he)}',
  'END $rid',
];

const _named = (
  setup: LogOnOkSetup(
    analysedBy: 'EdP',
    printOnOk: true,
    printerConfigured: true,
  ),
  copies: 1,
);

class _Rig {
  _Rig({this.saveResult = true, this.saveError, this.saveGate}) {
    handler = BridgeOkHandler(
      processor: OkRecordProcessor(
        save: (id, a) async {
          events.add('save');
          if (saveGate != null) await saveGate!.future;
          if (saveError != null) throw saveError!;
          saved.add((id: id, analysis: a));
          return saveResult;
        },
        markComplete: (id) async => events.add('markComplete'),
        printLabel: (a, copies) async {
          events.add('print');
          printed.add(a);
        },
      ),
      send: (m) async {
        events.add(m);
        sent.add(m);
      },
      active: () => true,
      elapsed: () => clock,
      now: () => _now,
    );
    handler.results.listen(results.add);
  }

  final bool saveResult;
  final Object? saveError;
  final Completer<void>? saveGate;

  late final BridgeOkHandler handler;
  Duration clock = Duration.zero;
  final events = <String>[];
  final sent = <String>[];
  final saved = <({String id, NewGasAnalysis analysis})>[];
  final printed = <GasAnalysis>[];
  final results = <OkLogResult>[];

  void push(String line) => handler.onMessage(parseBridgeMessage(line));
  void pushAll(Iterable<String> lines) => lines.forEach(push);

  /// Lets the queued handling run to its end.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  test('a live record with name set saves, ACKs after the save, prints, '
      'then sends FB printed', () async {
    final r = _Rig();
    r.handler.setupProvider = () => _named;
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();

    expect(r.events, [
      'save',
      'ACK r1',
      'print',
      'markComplete',
      'FB r1 printed EAN32',
    ]);
    final a = r.saved.single.analysis;
    expect(a.captureSource, CaptureSource.bridgeOk);
    expect(a.bridgeRecordId, '$_bridgeId/r1');
    expect(r.saved.single.id, bridgeRowId(_bridgeId, 'r1'));
    expect(r.results.single.code, FeedbackCode.printed);
    expect(r.results.single.complete, isTrue);
  });

  test('room air is ACKed and answered AIR - NOT LOGGED without saving',
      () async {
    final r = _Rig();
    r.handler.setupProvider = () => _named;
    r.push(_hello());
    r.pushAll(_recordLines('r1', o2: 20.9));
    await r.settle();

    expect(r.saved, isEmpty);
    expect(r.sent, ['ACK r1', 'FB r1 skipped AIR - NOT LOGGED']);
    expect(r.results.single.code, FeedbackCode.skipped);
  });

  test('a record saved before is ACKed again and not saved twice', () async {
    final r = _Rig(saveResult: false);
    r.handler.setupProvider = () => _named;
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();

    expect(r.sent, ['ACK r1', 'FB r1 saved ALREADY SAVED']);
    expect(r.printed, isEmpty);
    expect(r.events, isNot(contains('print')));
    expect(r.events, isNot(contains('markComplete')));
    expect(r.results.single.alreadySaved, isTrue);
    expect(r.results.single.code, FeedbackCode.saved);
  });

  test('a failed save is not ACKed', () async {
    final r = _Rig(saveError: StateError('disk full'));
    r.handler.setupProvider = () => _named;
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();

    expect(r.sent, ['FB r1 error SAVE FAILED']);
    expect(r.printed, isEmpty);
    expect(r.results.single.code, FeedbackCode.error);
  });

  test('a record before HELLO is not ACKed', () async {
    final r = _Rig();
    r.pushAll(_recordLines('r1'));
    await r.settle();
    expect(r.events, isEmpty);
    expect(r.results, isEmpty);

    // After the HELLO the bridge sends it again, and it is handled.
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();
    expect(r.sent.first, 'ACK r1');
  });

  test('a record cut off by a new connection is dropped, and the resend '
      'from REC is handled', () async {
    final r = _Rig();
    r.push(_hello());
    final lines = _recordLines('r1');
    r.pushAll(lines.take(10));
    r.push(_hello());
    r.pushAll(lines);
    await r.settle();
    expect(r.saved, hasLength(1));
    expect(r.sent.where((m) => m == 'ACK r1'), hasLength(1));
  });

  test('two records are handled one after the other', () async {
    final gate = Completer<void>();
    final r = _Rig(saveGate: gate);
    r.handler.setupProvider = () => _named;
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    r.pushAll(_recordLines('r2', o2: 36));
    await r.settle();
    expect(r.events, ['save'], reason: 'the second waits for the first');

    gate.complete();
    await r.settle();
    final firstFb = r.events.indexOf('FB r1 printed EAN32');
    final secondSave = r.events.lastIndexOf('save');
    expect(firstFb, greaterThanOrEqualTo(0));
    expect(secondSave, greaterThan(firstFb));
    expect(r.events.last, 'FB r2 printed EAN36');
  });

  test('the clock is rebased at receipt', () async {
    final r = _Rig();
    r.push(_hello(up: 8000));
    r.push('ST solo=1 data=1 pending=1 batt=3987 up=10000');
    final lines = _recordLines('r1', up: 9000);
    r.pushAll(lines.take(lines.length - 1));
    r.clock = const Duration(milliseconds: 3000);
    r.push(lines.last);
    await r.settle();

    expect(
      r.saved.single.analysis.analysedAt,
      _now.subtract(const Duration(milliseconds: 4000)),
    );
  });

  test('without a setup a record is still saved, flagged', () async {
    final r = _Rig();
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();
    expect(r.saved.single.analysis.needsSignoff, isTrue);
    expect(r.sent, ['ACK r1', 'FB r1 saved NO NAME SET']);
  });

  test('dispose waits for a record in flight, then closes results', () async {
    final gate = Completer<void>();
    final r = _Rig(saveGate: gate);
    r.push(_hello());
    r.pushAll(_recordLines('r1'));
    await r.settle();
    final disposed = r.handler.dispose();
    r.pushAll(_recordLines('r2'));
    gate.complete();
    await disposed;
    expect(r.results, hasLength(1));
    expect(r.saved, hasLength(1), reason: 'nothing after dispose');
  });
}
