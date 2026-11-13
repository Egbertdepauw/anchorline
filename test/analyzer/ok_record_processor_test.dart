import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/bridge/record_to_analysis.dart';
import 'package:ccrlogger/analyzer/ok_logger.dart';
import 'package:ccrlogger/analyzer/ok_record_processor.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/data/models/open_blend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/fake_open_blends_dao.dart';

const _tx1845 = DesiredMix(18, 45);

String _line(double o2, double he) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';

/// A live record of a steady reading, [rid] apart from the others.
BridgeRecord _record(String rid, {double o2 = 18.2, double he = 44.8}) =>
    BridgeRecord(
      rid: rid,
      boot: 3,
      upMs: 99000,
      wallMs: 0,
      live: true,
      window: [
        for (var i = 0; i < 150; i++)
          BridgeWindowLine(-200 * (150 - i), _line(o2, he)),
      ],
      heldLine: _line(o2, he),
    );

OpenBlend _openBlend(String id) => OpenBlend(
      id: id,
      target: _tx1845,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 20,
      topoff: const DesiredMix(0, 70),
      waterCapacityL: 3,
      role: GasRole.diluent,
      blendedBy: null,
      blendedAt: DateTime(2026, 11, 3, 9),
    );

OkSetup _setup(
  List<OpenBlend> blends, {
  String? name = 'EdP',
  bool print = true,
}) => (
  setup: LogOnOkSetup(
    analysedBy: name,
    autoPickMix: true,
    openBlends: blends,
    printOnOk: print,
    printerConfigured: print,
  ),
  copies: 1,
);

/// A processor on recording fakes; the blend closes on [openDao].
class _Rig {
  _Rig({
    this.printError,
    this.closeError,
    this.useClose = true,
    FakeOpenBlendsDao? dao,
  }) : openDao = dao ?? FakeOpenBlendsDao() {
    processor = OkRecordProcessor(
      save: (id, a) async {
        events.add('save');
        saved[id] = a;
        return true;
      },
      markComplete: (id) async => events.add('markComplete'),
      printLabel: (a, copies) async {
        events.add('print');
        if (printError != null) throw printError!;
      },
      closeBlend: !useClose
          ? null
          : (b, id) async {
              events.add('close');
              if (closeError != null) throw closeError!;
              return openDao.closeBlend(b, id);
            },
      onError: (e, s) => errors.add(e),
    );
  }

  final Object? printError;
  final Object? closeError;
  final bool useClose;
  final FakeOpenBlendsDao openDao;
  late final OkRecordProcessor processor;
  final events = <String>[];
  final saved = <String, NewGasAnalysis>{};
  final errors = <Object>[];

  Future<OkLogResult> press(String rid, OkSetup setup) => processor.process(
        record: _record(rid),
        bridgeId: 'usb',
        source: CaptureSource.usbOk,
        clock: const BridgeClock(boot: 3, upMs: 100000),
        now: DateTime(2026, 11, 3, 16),
        active: true,
        setup: setup,
      );
}

void main() {
  test('a complete press closes its blend, after the print', () async {
    final blend = _openBlend('b1');
    final r = _Rig(dao: FakeOpenBlendsDao(blends: [blend]));
    final res = await r.press('r1', _setup([blend]));
    expect(res.complete, isTrue);
    expect(r.events, ['save', 'print', 'markComplete', 'close']);
    expect(r.openDao.closedBy['b1'], res.analysisId);
    expect(r.saved[res.analysisId]!.desiredMix, _tx1845);
  });

  test('a complete press with no print closes its blend', () async {
    final blend = _openBlend('b1');
    final r = _Rig(dao: FakeOpenBlendsDao(blends: [blend]));
    final res = await r.press('r1', _setup([blend], print: false));
    expect(res.complete, isTrue);
    expect(r.events, ['save', 'close']);
    expect(r.openDao.closedBy['b1'], res.analysisId);
  });

  test('a press that needs sign-off does not close', () async {
    final blend = _openBlend('b1');
    final r = _Rig(dao: FakeOpenBlendsDao(blends: [blend]));
    // No name: saved for sign-off.
    final res = await r.press('r1', _setup([blend], name: null, print: false));
    expect(res.complete, isFalse);
    expect(r.events, ['save']);
    expect(r.openDao.closeBlendCalls, isEmpty);
  });

  test('a print that fails does not close', () async {
    final blend = _openBlend('b1');
    final r = _Rig(
      dao: FakeOpenBlendsDao(blends: [blend]),
      printError: StateError('printer off'),
    );
    final res = await r.press('r1', _setup([blend]));
    expect(res.complete, isFalse);
    expect(r.events, ['save', 'print']);
    expect(r.openDao.closeBlendCalls, isEmpty);
  });

  test('a press with no blend to close asks for none', () async {
    final r = _Rig();
    final res = await r.press('r1', _setup(const []));
    expect(res.complete, isTrue);
    expect(r.events, ['save', 'print', 'markComplete']);
  });

  test('a residual press closes nothing, prints nothing', () async {
    final blend = _openBlend('b1');
    final r = _Rig(dao: FakeOpenBlendsDao(blends: [blend]));
    final res = await r.press(
      'r1',
      (
        setup: LogOnOkSetup(
          analysedBy: 'EdP',
          autoPickMix: true,
          openBlends: [blend],
          residual: true,
          printOnOk: true,
          printerConfigured: true,
        ),
        copies: 1,
      ),
    );
    expect(res.complete, isTrue);
    expect(r.events, ['save']);
    expect(r.saved.values.single.isResidual, isTrue);
    expect(r.openDao.closeBlendCalls, isEmpty);
  });

  test('a closeBlend that throws is reported and the result stays complete',
      () async {
    final blend = _openBlend('b1');
    final r = _Rig(
      dao: FakeOpenBlendsDao(blends: [blend]),
      closeError: StateError('db locked'),
    );
    final res = await r.press('r1', _setup([blend]));
    expect(res.complete, isTrue);
    expect(res.code, FeedbackCode.printed);
    expect(r.errors.single, isA<StateError>());
    expect(r.saved, hasLength(1));
  });

  test('without a closeBlend the press is saved as before', () async {
    final blend = _openBlend('b1');
    final r = _Rig(useClose: false);
    final res = await r.press('r1', _setup([blend]));
    expect(res.complete, isTrue);
    expect(r.events, ['save', 'print', 'markComplete']);
  });

  test('two quick presses, one open blend: one close', () async {
    final blend = _openBlend('b1');
    final dao = FakeOpenBlendsDao(blends: [blend]);
    final r = _Rig(dao: dao);
    // Both presses are set up while the blend is still open, as the card's
    // provider would give them.
    final setup = _setup([blend]);
    final first = await r.press('r1', setup);
    final second = await r.press('r2', setup);

    expect(first.complete, isTrue);
    expect(second.complete, isTrue);
    expect(r.saved, hasLength(2), reason: 'both analyses are saved');
    expect(r.saved[second.analysisId]!.desiredMix, _tx1845,
        reason: 'the second still takes the blend\'s target');
    expect(r.errors, isEmpty);
    // Both asked; only the first closed it.
    expect(dao.closeBlendCalls, hasLength(2));
    expect(dao.closedBy, {'b1': first.analysisId});
    expect(await dao.listOpen(), isEmpty);
  });
}
