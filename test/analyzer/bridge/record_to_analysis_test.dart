import 'package:ccrlogger/analysis/gas_naming.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/bridge/record_to_analysis.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/solo_capture_log.dart';

const _bridgeId = 'a1b2c3d4e5f6';
const _rid = '1a2b3c4d-7';
const _clock = BridgeClock(boot: 3, upMs: 100000);
final _now = DateTime(2026, 11, 3, 16);

/// A SOLO line as the trimix model prints it.
String soloLine(double o2, double he, {String time = '2026/11/03 15:21:00'}) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   $time';

/// A record whose window is 150 lines, 200 ms apart, at offsets -30000 to
/// -200. The held line is the last window line unless [heldLine] says
/// otherwise.
BridgeRecord _record(
  String Function(int i) lineAt, {
  int boot = 3,
  int upMs = 99000,
  int wallMs = 0,
  bool live = true,
  String? heldLine,
  int lines = 150,
}) {
  final window = [
    for (var i = 0; i < lines; i++)
      BridgeWindowLine(-200 * (lines - i), lineAt(i)),
  ];
  return BridgeRecord(
    rid: _rid,
    boot: boot,
    upMs: upMs,
    wallMs: wallMs,
    live: live,
    window: window,
    heldLine: heldLine ?? window.last.line,
  );
}

/// Thirty seconds of the same reading.
BridgeRecord steady(
  double o2,
  double he, {
  int boot = 3,
  int upMs = 99000,
  int wallMs = 0,
  bool live = true,
  String? heldLine,
  int lines = 150,
}) => _record(
  (_) => soloLine(o2, he),
  boot: boot,
  upMs: upMs,
  wallMs: wallMs,
  live: live,
  heldLine: heldLine,
  lines: lines,
);

/// Thirty seconds with O2 rising linearly from [from] to [to].
BridgeRecord drifting(double from, double to, {bool live = true}) =>
    _record((i) => soloLine(from + (to - from) * i / 149, 0.0), live: live);

LogOnOkSetup _setup({
  String? analysedBy = 'EdP',
  DesiredMix? desiredMix = const DesiredMix(21, 35),
  GasRole gasRole = GasRole.diluent,
  String? analysedFor = 'Wendy',
  bool printOnOk = true,
  bool printerConfigured = true,
  String? cylinderId = 'cyl-1',
  double? fillPressureBar = 210,
  String? notes = 'top-up',
}) => LogOnOkSetup(
  analysedBy: analysedBy,
  desiredMix: desiredMix,
  gasRole: gasRole,
  analysedFor: analysedFor,
  printOnOk: printOnOk,
  printerConfigured: printerConfigured,
  cylinderId: cylinderId,
  fillPressureBar: fillPressureBar,
  notes: notes,
  modPpo2s: const [1.1, 1.4, 1.6],
);

final _full = _setup();

RecordOutcome _run(
  BridgeRecord record, {
  LogOnOkSetup? setup,
  BridgeClock clock = _clock,
  DateTime? now,
  bool active = true,
}) => recordToAnalysis(
  record: record,
  bridgeId: _bridgeId,
  setup: setup ?? _full,
  clock: clock,
  now: now ?? _now,
  active: active,
);

SaveRecord _save(
  BridgeRecord record, {
  LogOnOkSetup? setup,
  BridgeClock clock = _clock,
  DateTime? now,
  bool active = true,
}) =>
    _run(record, setup: setup, clock: clock, now: now, active: active)
        as SaveRecord;

void main() {
  group('the decision', () {
    test('complete live Tx21/35 with printing on: save flagged until printed, '
        'print', () {
      final r = _save(steady(21.0, 35.0));
      expect(r.printLabel, isTrue);
      expect(r.live, isTrue);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'Tx21/35'));
      expect(r.rid, _rid);
      expect(r.analysis.o2Percent, 21.0);
      expect(r.analysis.hePercent, 35.0);
      expect(r.analysis.stable, isTrue);
      expect(r.analysis.analysedBy, 'EdP');
      expect(r.analysis.analysedFor, 'Wendy');
      expect(r.analysis.cylinderId, 'cyl-1');
      expect(r.analysis.fillPressureBar, 210);
      expect(r.analysis.desiredMix, const DesiredMix(21, 35));
      expect(r.analysis.gasRole, GasRole.diluent);
      expect(r.analysis.notes, 'top-up');
      expect(r.analysis.modPpo2s, [1.1, 1.4, 1.6]);
      expect(r.analysis.captureSource, CaptureSource.bridgeOk);
      expect(r.analysis.bridgeRecordId, 'a1b2c3d4e5f6/$_rid');
      expect(r.rowId, bridgeRowId(_bridgeId, _rid));
    });

    test('the source is carried into the analysis', () {
      final r =
          recordToAnalysis(
                record: steady(21.0, 35.0),
                bridgeId: 'usb',
                setup: _full,
                clock: _clock,
                now: _now,
                active: true,
                source: CaptureSource.usbOk,
              )
              as SaveRecord;
      expect(r.analysis.captureSource, CaptureSource.usbOk);
      expect(r.analysis.bridgeRecordId, 'usb/$_rid');
    });

    test('printing off: complete without a label', () {
      final r = _save(steady(21.0, 35.0), setup: _setup(printOnOk: false));
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isFalse);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'Tx21/35'));
    });

    test('no printer configured: complete without a label', () {
      final r = _save(
        steady(21.0, 35.0),
        setup: _setup(printerConfigured: false),
      );
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isFalse);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'Tx21/35'));
    });

    test('orange still prints', () {
      final r = _save(
        steady(30.5, 0.0),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.printLabel, isTrue);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN31'));
    });

    test('a match on the O2 bound (1.0 off) prints', () {
      final r = _save(
        steady(31.0, 0.0),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.printLabel, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN31'));
    });

    test('red does not print and asks to check', () {
      final r = _save(
        steady(28.5, 0.0),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.check, 'MISMATCH'));
    });

    test('hard does not print and asks to check', () {
      final r = _save(
        steady(26.0, 0.0),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.check, 'MISMATCH'));
    });

    test('a red helium mismatch asks to check as well', () {
      // O2 is right, He is 8 points off: red.
      final r = _save(steady(21.0, 27.0));
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.check, 'MISMATCH'));
    });

    test('not stable, printing on: prints', () {
      // The OK press is the confirmation (decision 18). The held value, 32.0,
      // is a match against 31/0.
      final r = _save(
        drifting(30, 32),
        setup: _setup(desiredMix: const DesiredMix(31, 0)),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN32'));
    });

    test('not stable, printing off: complete', () {
      final r = _save(
        drifting(30, 32),
        setup: _setup(
          desiredMix: const DesiredMix(31, 0),
          printOnOk: false,
        ),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isFalse);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'EAN32'));
    });

    test('not stable and a mismatch: the mismatch is reported', () {
      final r = _save(
        drifting(25, 27),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.check, 'MISMATCH'));
    });

    test('no desired mix, printing on: prints the analysed mix', () {
      final r = _save(steady(32.0, 0.0), setup: _setup(desiredMix: null));
      expect(r.analysis.desiredMix, isNull);
      expect(r.printLabel, isTrue);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN32'));
    });

    test('no desired mix, printing off: complete', () {
      final r = _save(
        steady(32.0, 0.0),
        setup: _setup(desiredMix: null, printOnOk: false),
      );
      expect(r.analysis.desiredMix, isNull);
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isFalse);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'EAN32'));
    });

    test('no desired mix and not stable, printing on: prints', () {
      final r = _save(drifting(30, 32), setup: _setup(desiredMix: null));
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN32'));
    });

    test('no name: saved flagged', () {
      final r = _save(steady(21.0, 35.0), setup: _setup(analysedBy: '  '));
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'NO NAME SET'));
    });

    test('a blank name is stored as no name', () {
      final r = _save(steady(21.0, 35.0), setup: _setup(analysedBy: '  '));
      expect(r.analysis.analysedBy, isNull);
    });

    test('no name and no desired mix: saved flagged, no label', () {
      final r = _save(
        steady(21.0, 35.0),
        setup: _setup(analysedBy: null, desiredMix: null),
      );
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'NO NAME SET'));
    });

    test('no name and not stable: saved flagged, no label', () {
      final r = _save(
        drifting(30, 32),
        setup: _setup(analysedBy: null, desiredMix: const DesiredMix(31, 0)),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.saved, 'NO NAME SET'));
    });

    test('a mismatch is reported before a missing name', () {
      final r = _save(
        steady(26.0, 0.0),
        setup: _setup(analysedBy: null, desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.check, 'MISMATCH'));
    });

    test('room air is skipped', () {
      final r = _run(steady(20.9, 0.3));
      expect(r, isA<SkipRecord>());
      expect(r.rid, _rid);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.skipped, 'AIR - NOT LOGGED'),
      );
    });

    test('room air with a negative helium reading is skipped', () {
      final r = _run(steady(20.9, -0.2));
      expect(r, isA<SkipRecord>());
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.skipped, 'AIR - NOT LOGGED'),
      );
    });

    test('room air band edges', () {
      expect(isRoomAir(20.5, 0.9), isTrue);
      expect(isRoomAir(21.5, 0.0), isTrue);
      expect(isRoomAir(20.9, -0.2), isTrue);
      expect(isRoomAir(21.6, 0.0), isFalse);
      expect(isRoomAir(20.4, 0.0), isFalse);
      expect(isRoomAir(20.9, 1.0), isFalse);
    });

    test('an air-like O2 with real helium is a trimix and is saved', () {
      final r = _run(steady(21.0, 35.0));
      expect(r, isA<SaveRecord>());
    });

    test('sensor error at the hold is skipped', () {
      final r = _run(
        steady(
          32.0,
          0.0,
          heldLine:
              'He  ***.* %  O2  32.0 %  Ti  22.0 ~C  1029.5 hPa   '
              '2026/11/03 15:21:00',
        ),
      );
      expect(r, isA<SkipRecord>());
      expect((r.feedback, r.feedbackText), (FeedbackCode.error, 'NO READING'));
    });

    test('an O2 sensor error at the hold is skipped', () {
      final r = _run(
        steady(
          32.0,
          0.0,
          heldLine:
              'He    0.0 %  O2  ***.* %  Ti  22.0 ~C  1029.5 hPa   '
              '2026/11/03 15:21:00',
        ),
      );
      expect(r, isA<SkipRecord>());
      expect((r.feedback, r.feedbackText), (FeedbackCode.error, 'NO READING'));
    });

    test('an O2 of zero at the hold is skipped', () {
      final r = _run(
        steady(
          32.0,
          0.0,
          heldLine:
              'He    0.0 %  O2    0.0 %  Ti  22.0 ~C  1029.5 hPa   '
              '2026/11/03 15:21:00',
        ),
      );
      expect(r, isA<SkipRecord>());
      expect((r.feedback, r.feedbackText), (FeedbackCode.error, 'NO READING'));
    });

    test('a held line that is not a SOLO line is skipped', () {
      final r = _run(steady(32.0, 0.0, heldLine: 'garbage'));
      expect(r, isA<SkipRecord>());
      expect((r.feedback, r.feedbackText), (FeedbackCode.error, 'NO READING'));
    });

    test('a record without a held line is skipped as no reading', () {
      final r = _run(steady(32.0, 0.0, heldLine: ''));
      expect(r, isA<SkipRecord>());
      expect(r.rid, _rid);
      expect((r.feedback, r.feedbackText), (FeedbackCode.error, 'NO READING'));
    });

    test('negative He is stored as 0', () {
      final r = _save(
        steady(32.0, -0.2),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(r.analysis.hePercent, 0.0);
      expect(r.analysis.o2Percent, 32.0);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'EAN32'));
    });

    test('a helium offset on a gas that is not air is stored unchanged', () {
      final r = _save(
        steady(18.0, 0.4),
        setup: _setup(desiredMix: const DesiredMix(18, 0)),
      );
      expect(r.analysis.hePercent, 0.4);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.printed, 'Hypoxic 18'),
      );
    });

    test('temperature and pressure come from the held line', () {
      final r = _save(steady(21.0, 35.0));
      expect(r.analysis.tempC, 22.0);
      expect(r.analysis.baroHpa, 1029.5);
    });

    test('temperature and pressure that are not finite are left out', () {
      final r = _save(
        steady(
          21.0,
          35.0,
          heldLine:
              'He   35.0 %  O2  21.0 %  Ti  ***.* ~C  ***.* hPa   '
              '2026/11/03 15:21:00',
        ),
      );
      expect(r.analysis.tempC, isNull);
      expect(r.analysis.baroHpa, isNull);
    });

    test('temperature and pressure the line does not have are left out', () {
      final r = _save(
        steady(
          21.0,
          35.0,
          heldLine: 'He   35.0 %  O2  21.0 %  2026/11/03 15:21:00',
        ),
      );
      expect(r.analysis.tempC, isNull);
      expect(r.analysis.baroHpa, isNull);
    });
  });

  group('stability', () {
    test('a window shorter than 20 s is not stable, and still prints', () {
      final r = _save(steady(21.0, 35.0, lines: 50));
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
      expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'Tx21/35'));
    });

    test('an empty window is not stable, and still prints', () {
      final r = _save(steady(21.0, 35.0, lines: 0, heldLine: soloLine(21, 35)));
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
    });

    test('a sensor error inside the window restarts the 20 s clock', () {
      final r = _save(
        _record(
          (i) => i == 100
              ? 'He  ***.* %  O2  21.0 %  Ti  22.0 ~C  1029.5 hPa   '
                    '2026/11/03 15:21:00'
              : soloLine(21.0, 35.0),
        ),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
    });

    test('a window line that is not a SOLO line is ignored', () {
      final r = _save(
        _record((i) => i == 70 ? 'garbage' : soloLine(21.0, 35.0)),
      );
      expect(r.analysis.stable, isTrue);
    });
  });

  group('auto pick and the role', () {
    // A setup with no mix and no role, named, printing on.
    LogOnOkSetup autoSetup({
      bool autoPickMix = true,
      DesiredMix? desiredMix,
      DesiredMix? blendTarget,
      GasRole? gasRole,
    }) => LogOnOkSetup(
      analysedBy: 'EdP',
      desiredMix: desiredMix,
      blendTarget: blendTarget,
      autoPickMix: autoPickMix,
      gasRole: gasRole,
      printOnOk: true,
      printerConfigured: true,
    );

    // The held line is the reading being saved; the window is something else.
    SaveRecord decide(
      double o2,
      double he, {
      required LogOnOkSetup setup,
      bool live = true,
    }) => _save(
      steady(21.0, 0.0, live: live, heldLine: soloLine(o2, he)),
      setup: setup,
    );

    test('auto pick comes from the held line', () {
      final out = decide(19.1, 43.0, setup: autoSetup());
      expect(out.analysis.desiredMix, const DesiredMix(18, 45));
      expect(out.printLabel, isTrue);
    });

    test('auto pick never takes a red mix; the label then names the '
        'analysed gas', () {
      final out = decide(23.0, 30.0, setup: autoSetup());
      expect(out.analysis.desiredMix, isNull);
      expect(out.printLabel, isTrue);
    });

    test('a diver pick wins over auto pick (and a red one still blocks the '
        'print)', () {
      final out = decide(
        19.1,
        43.0,
        setup: autoSetup(desiredMix: const DesiredMix(21, 35)),
      );
      expect(out.analysis.desiredMix, const DesiredMix(21, 35));
      expect(out.printLabel, isFalse);
      expect(out.analysis.needsSignoff, isTrue);
    });

    test('the Blend target is used when it grades within orange', () {
      final out = decide(
        19.6,
        40.2,
        setup: autoSetup(blendTarget: const DesiredMix(19, 40)),
      );
      expect(out.analysis.desiredMix, const DesiredMix(19, 40));
    });

    test('the role follows the picked mix', () {
      expect(
        decide(49.2, 0.3, setup: autoSetup()).analysis.gasRole,
        GasRole.bailout,
      );
      expect(
        decide(20.6, 33.8, setup: autoSetup()).analysis.gasRole,
        GasRole.diluent,
      );
    });

    test('with no desired mix the role follows the reading', () {
      expect(
        decide(40.0, 0.0, setup: autoSetup()).analysis.gasRole,
        GasRole.bailout,
      );
    });

    test('an explicit role wins', () {
      expect(
        decide(
          49.2,
          0.3,
          setup: autoSetup(gasRole: GasRole.diluent),
        ).analysis.gasRole,
        GasRole.diluent,
      );
    });

    test('without auto pick no mix is chosen', () {
      final out = decide(19.1, 43.0, setup: autoSetup(autoPickMix: false));
      expect(out.analysis.desiredMix, isNull);
    });

    test('a late record still gets no desired mix and bailout', () {
      final out = decide(20.6, 33.8, setup: autoSetup(), live: false);
      expect(out.analysis.desiredMix, isNull);
      expect(out.analysis.gasRole, GasRole.bailout);
    });
  });

  group('late records', () {
    test('a late record gets no setup', () {
      final r = _save(steady(21.0, 35.0, live: false));
      expect(r.live, isFalse);
      expect(r.analysis.analysedBy, isNull);
      expect(r.analysis.desiredMix, isNull);
      expect(r.analysis.analysedFor, isNull);
      expect(r.analysis.cylinderId, isNull);
      expect(r.analysis.fillPressureBar, isNull);
      expect(r.analysis.notes, isNull);
      expect(r.analysis.gasRole, GasRole.bailout);
      expect(r.analysis.needsSignoff, isTrue);
      expect(r.printLabel, isFalse);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
      expect(r.analysis.modPpo2s, [1.1, 1.4, 1.6]);
    });

    test('late when older than 30 s', () {
      final r = _save(steady(21.0, 35.0, upMs: 69000));
      expect(r.live, isFalse);
      expect(r.analysis.analysedBy, isNull);
      expect(r.printLabel, isFalse);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
    });

    test('30 s old is still live, 30.001 s is late', () {
      expect(_save(steady(21.0, 35.0, upMs: 70000)).live, isTrue);
      expect(_save(steady(21.0, 35.0, upMs: 69999)).live, isFalse);
    });

    test('late when not on the analyzer screen and not in a session', () {
      final r = _save(steady(21.0, 35.0), active: false);
      expect(r.live, isFalse);
      expect(r.analysis.analysedBy, isNull);
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
    });

    test('late after a bridge reboot', () {
      final r = _save(steady(21.0, 35.0, boot: 2));
      expect(r.live, isFalse);
      expect(r.analysis.analysedBy, isNull);
      expect(r.printLabel, isFalse);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
    });

    test('a late record is not graded against a desired mix', () {
      // 26.0/0 would be a hard mismatch against 32/0, but a late record
      // carries no desired mix, so there is nothing to mismatch.
      final r = _save(
        steady(26.0, 0.0, live: false),
        setup: _setup(desiredMix: const DesiredMix(32, 0)),
      );
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
    });

    test('a late record that is not stable still says sign off later', () {
      final r = _save(drifting(30, 32, live: false));
      expect(r.analysis.stable, isFalse);
      expect(r.analysis.needsSignoff, isTrue);
      expect(r.printLabel, isFalse);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'SIGN OFF LATER'),
      );
    });
  });

  group('analysed_at', () {
    test('same boot: now minus the uptime difference', () {
      final r = _save(steady(21.0, 35.0, upMs: 95000));
      expect(r.analysis.analysedAt, DateTime(2026, 11, 3, 15, 59, 55));
      expect(r.analysis.notes, 'top-up');
    });

    test('same boot but late: still the uptime difference', () {
      final r = _save(steady(21.0, 35.0, upMs: 40000));
      expect(r.live, isFalse);
      expect(r.analysis.analysedAt, DateTime(2026, 11, 3, 15, 59));
      expect(r.analysis.notes, isNull);
    });

    test('same boot, clock behind the record: never in the future', () {
      final r = _save(steady(21.0, 35.0, upMs: 103000));
      expect(r.analysis.analysedAt, _now);
    });

    test('other boot: the wall time', () {
      final wall = DateTime(2026, 11, 3, 15, 30);
      final r = _save(
        steady(21.0, 35.0, boot: 2, wallMs: wall.millisecondsSinceEpoch),
      );
      expect(r.analysis.analysedAt, wall);
      expect(r.analysis.notes, isNull);
    });

    test('other boot, no wall time: the SOLO clock', () {
      final r = _save(steady(21.0, 35.0, boot: 2));
      expect(r.analysis.analysedAt, DateTime(2026, 11, 3, 15, 21));
      expect(r.analysis.notes, isNull);
    });

    test('nothing known: now, with a note', () {
      final r = _save(
        steady(
          21.0,
          35.0,
          boot: 2,
          heldLine: 'He   35.0 %  O2  21.0 %  Ti  22.0 ~C  1029.5 hPa',
        ),
      );
      expect(r.analysis.analysedAt, _now);
      expect(
        r.analysis.notes,
        'Time of OK unknown; delivered 2026-11-03 16:00',
      );
    });
  });

  group('bridgeRowId', () {
    test('is a stable UUID v5', () {
      final a = bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-7');
      expect(a, bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-7'));
      expect(a, isNot(bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-8')));
      expect(a, isNot(bridgeRowId('a1b2c3d4e5f7', '1a2b3c4d-7')));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ).hasMatch(a),
        isTrue,
      );
      // uuid.uuid5(uuid.NAMESPACE_URL,
      //     'anchorline-bridge:a1b2c3d4e5f6/1a2b3c4d-7') in Python.
      expect(a, '141b9635-6dd7-5df7-b454-b11799913348');
    });
  });

  group('real captures', () {
    test('the first OK on the bench SOLO', () {
      final log = readSoloCaptureLog(
        'test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt',
      );
      // The 28.7 s hold.
      final gap = log.gaps.firstWhere(
        (g) => g.length > const Duration(seconds: 20),
      );
      final record = recordBeforeGap(log, gap);
      // The held line is the one at 58.357 s and the window reaches back 30 s.
      expect(record.upMs, 58357);
      expect(record.window.first.offsetMs, greaterThanOrEqualTo(-30000));
      expect(record.window.first.offsetMs, lessThan(-29800));
      expect(record.window.last.offsetMs, lessThan(0));
      final r = _save(
        record,
        clock: const BridgeClock(boot: 1, upMs: 60000),
        setup: _setup(desiredMix: null, printOnOk: false),
      );
      expect(r.analysis.o2Percent, 19.8);
      expect(r.analysis.hePercent, 0.5);
      // If this fails, check the helper's offsets before anything else.
      expect(r.analysis.stable, isTrue);
      // Uncalibrated air, spec section 5 caveat.
      expect(
        gasMixName(r.analysis.o2Percent, r.analysis.hePercent),
        'Hypoxic 20',
      );
    });

    test('the second OK was pressed too early to be stable, and it saves', () {
      final log = readSoloCaptureLog(
        'test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt',
      );
      final gap = log.gaps.firstWhere(
        (g) => g.length > const Duration(seconds: 20),
      );
      final record = recordBeforeGap(log, gap);
      // Nine `***.*` helium lines open this capture, so after them the SOLO
      // had been reading for about 14 s, short of the 20 s window.
      expect(record.window.any((w) => w.line.contains('***.*')), isTrue);
      final r = _save(
        record,
        clock: BridgeClock(boot: 1, upMs: record.upMs + 2000),
        setup: _setup(desiredMix: null, printOnOk: false),
      );
      expect(r.analysis.o2Percent, 19.8);
      expect(r.analysis.stable, isFalse);
      // The OK press is the confirmation: no desired mix, named, live.
      expect(r.printLabel, isFalse);
      expect(r.analysis.needsSignoff, isFalse);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.saved, 'Hypoxic 20'),
      );
    });

    test('the second OK, with printing on, prints', () {
      final log = readSoloCaptureLog(
        'test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt',
      );
      final gap = log.gaps.firstWhere(
        (g) => g.length > const Duration(seconds: 20),
      );
      final record = recordBeforeGap(log, gap);
      final r = _save(
        record,
        clock: BridgeClock(boot: 1, upMs: record.upMs + 2000),
        setup: _setup(desiredMix: null),
      );
      expect(r.analysis.stable, isFalse);
      expect(r.printLabel, isTrue);
      expect(
        (r.feedback, r.feedbackText),
        (FeedbackCode.printed, 'Hypoxic 20'),
      );
    });
  });
}
