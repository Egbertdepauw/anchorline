import 'dart:async';

import 'package:ccrlogger/analysis/standard_mix_pick.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/protocol/analyzer_reading.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';

const _dil =
    CylinderChoice(id: 'c-dil', label: 'Dil 3L', role: CylinderRole.diluent);
const _s80 = CylinderChoice(id: 'c-s80', label: 'S80 left');

const _ean32 =
    AnalyzerReading(o2: 32.0, he: 0, tempC: 21.4, baroHpa: 1013, raw: 'test');

/// A logger whose results the test sends, as the press handling would.
class _Logger extends UsbOkLogger {
  _Logger(FakeGasAnalysesDao dao)
      : super(
          save: dao.addFromBridge,
          markComplete: (id) => dao.setNeedsSignoff(id, false),
          tickInterval: null,
        );

  final _sent = StreamController<OkLogResult>.broadcast(sync: true);

  @override
  Stream<OkLogResult> get results => _sent.stream;

  void send(OkLogResult r) => _sent.add(r);
}

/// The result of a press that took [setup], saved complete or for sign-off.
OkLogResult _result(OkSetup setup, {required bool complete}) => OkLogResult(
      code: complete ? FeedbackCode.saved : FeedbackCode.check,
      text: complete ? 'EAN32' : 'MISMATCH',
      analysisId: 'a1',
      complete: complete,
      setupUsed: setup,
    );

/// Lets the DAO's reads finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeGasAnalysesDao dao;
  late SettingsNotifier settings;

  setUp(() async {
    dao = FakeGasAnalysesDao(cylinders: const [_dil, _s80]);
    settings = SettingsNotifier();
    await settings.load();
  });

  /// A controller on [dao] with a stable [reading] (EAN32), its cylinders
  /// and mixes loaded.
  Future<AnalysisSaveController> make({
    DesiredMix? blendTarget,
    DesiredMix? unusedBlendTarget,
    AnalyzerReading reading = _ean32,
  }) async {
    final c = AnalysisSaveController(dao: dao, settings: settings);
    addTearDown(c.dispose);
    c.update(
      reading: reading,
      stability: ReadingStability.stable,
      blendTarget: blendTarget,
      unusedBlendTarget: unusedBlendTarget,
      connected: true,
    );
    await _settle();
    return c;
  }

  test('the OK setup carries the form\'s values', () async {
    final c = await make();
    var told = 0;
    c.addListener(() => told++);

    c.selectCylinder('c-s80');
    c.pickMix(const DesiredMix(32, 0));
    c.tapRole(GasRole.diluent);
    c.analysedBy.text = 'EdP';
    c.analysedFor.text = 'Anna';
    c.fillPressure.text = '200';
    c.notes.text = 'Topped up';
    c.setCopies(3);
    expect(told, greaterThanOrEqualTo(4), reason: 'listeners hear each pick');
    expect(c.desiredMix, const DesiredMix(32, 0));
    expect(c.mixIsAutomatic, isFalse);

    final s = c.okSetup();
    expect(s.copies, 3);
    expect(s.setup.cylinderId, 'c-s80');
    // The diver's pick and tapped role go to every press as they are.
    expect(s.setup.desiredMix, const DesiredMix(32, 0));
    expect(s.setup.autoPickMix, isFalse);
    expect(s.setup.gasRole, GasRole.diluent);
    expect(s.setup.analysedBy, 'EdP');
    expect(s.setup.analysedFor, 'Anna');
    expect(s.setup.fillPressureBar, 200);
    expect(s.setup.notes, 'Topped up');
    expect(s.setup.modPpo2s, settings.analyzerModPpo2s);
    // No printer is set up, so nothing prints on OK.
    expect(s.setup.printerConfigured, isFalse);
    expect(s.setup.printOnOk, isFalse);
    // "Analysed by" is never written to the settings.
    expect(settings.yourInitials, isNull);
  });

  test('an automatic pick is left to each press, with the unused target',
      () async {
    final c = await make(
      blendTarget: const DesiredMix(21, 35),
      unusedBlendTarget: const DesiredMix(21, 35),
    );
    expect(c.mixIsAutomatic, isTrue);
    expect(c.desiredMix, const DesiredMix(32, 0));
    expect(c.mixSource, MixPickSource.standard);

    var s = c.okSetup().setup;
    expect(s.autoPickMix, isTrue);
    expect(s.desiredMix, isNull, reason: 'the press picks for its own line');
    expect(s.blendTarget, const DesiredMix(21, 35));
    expect(s.gasRole, isNull, reason: 'the press works it out from its mix');

    // A cylinder with a known role decides it; one without leaves it open.
    c.selectCylinder('c-dil');
    expect(c.okSetup().setup.gasRole, GasRole.diluent);
    c.selectCylinder('c-s80');
    expect(c.okSetup().setup.gasRole, isNull);

    // The diver's "no mix" is passed as no mix, not as automatic.
    c.clearMix();
    s = c.okSetup().setup;
    expect(s.autoPickMix, isFalse);
    expect(s.desiredMix, isNull);
    expect(c.mixSource, isNull);
  });

  test('the automatic pick follows the reading; the Blend target first',
      () async {
    final c = await make(
      reading: const AnalyzerReading(
          o2: 20.6, he: 33.8, tempC: 21, baroHpa: 1013, raw: 'test'),
      blendTarget: const DesiredMix(21, 35),
      unusedBlendTarget: const DesiredMix(21, 35),
    );
    expect(c.desiredMix, const DesiredMix(21, 35));
    expect(c.mixSource, MixPickSource.blendTarget);
    expect(c.role, GasRole.diluent);

    c.update(
      reading: const AnalyzerReading(
          o2: 49.2, he: 0, tempC: 21, baroHpa: 1013, raw: 'test'),
      stability: ReadingStability.stable,
      blendTarget: const DesiredMix(21, 35),
      unusedBlendTarget: const DesiredMix(21, 35),
      connected: true,
    );
    expect(c.desiredMix, const DesiredMix(50, 0));
    expect(c.mixSource, MixPickSource.standard);
    expect(c.role, GasRole.bailout);

    // Nothing within orange: no pick.
    c.update(
      reading: const AnalyzerReading(
          o2: 23.0, he: 30.0, tempC: 21, baroHpa: 1013, raw: 'test'),
      stability: ReadingStability.stable,
      connected: true,
    );
    expect(c.desiredMix, isNull);
    expect(c.mixSource, isNull);
    expect(c.mixIsAutomatic, isTrue);
  });

  test('a complete OK result uses up only the fields still as taken',
      () async {
    final c = await make();
    final logger = _Logger(dao);
    c.bindLogger(logger);
    expect(logger.setupProvider, isNotNull);

    c.selectCylinder('c-s80');
    c.fillPressure.text = '200';
    c.notes.text = 'first';
    final taken = logger.setupProvider!();

    // While the press is saved, the diver types the next cylinder's
    // pressure.
    c.fillPressure.text = '180';
    logger.send(_result(taken, complete: true));

    expect(c.okResult?.text, 'EAN32');
    expect(c.fillPressure.text, '180');
    expect(c.notes.text, isEmpty, reason: 'as the press took it');
    expect(c.cylinderId, isNull, reason: 'as the press took it');

    // A press that needs sign-off leaves its fields for the next OK.
    c.notes.text = 'second';
    logger.send(_result(logger.setupProvider!(), complete: false));
    expect(c.okResult?.text, 'MISMATCH');
    expect(c.fillPressure.text, '180');
    expect(c.notes.text, 'second');
  });

  test('a complete OK result puts the fill pressure back to its start and '
      'folds the notes', () async {
    await settings.setAnalyzerFillPressureStartBar(230);
    final c = await make();
    final logger = _Logger(dao);
    c.bindLogger(logger);

    c.fillPressure.text = '200';
    c.openNotes();
    c.notes.text = 'Topped up';
    expect(c.notesShown, isTrue);
    logger.send(_result(c.okSetup(), complete: true));

    expect(c.fillPressure.text, '230', reason: 'back to its start, not empty');
    expect(c.notes.text, isEmpty);
    expect(c.notesShown, isFalse, reason: 'folded again');

    // The field opened but left empty folds as well.
    c.openNotes();
    logger.send(_result(c.okSetup(), complete: true));
    expect(c.notesShown, isFalse);

    // A press that needs sign-off leaves the notes open.
    c.openNotes();
    c.notes.text = 'again';
    logger.send(_result(c.okSetup(), complete: false));
    expect(c.notes.text, 'again');
    expect(c.notesShown, isTrue);
  });

  group('the Blend target on OK', () {
    const target = DesiredMix(19, 40);

    /// The log has entry [id] saved with [desired].
    Future<void> stored(String id, DesiredMix? desired) => dao.addFromBridge(
          id,
          NewGasAnalysis(
            analysedAt: DateTime(2026, 11, 7),
            o2Percent: 19.6,
            hePercent: 40.2,
            stable: true,
            desiredMix: desired,
          ),
        );

    OkLogResult complete(OkSetup setup, String id) => OkLogResult(
          code: FeedbackCode.saved,
          text: 'Tx20/40',
          analysisId: id,
          complete: true,
          setupUsed: setup,
        );

    test('a complete result whose entry has the target stops offering it; '
        'the session marks it used', () async {
      final c = await make(blendTarget: target, unusedBlendTarget: target);
      var used = 0;
      c.onBlendTargetUsed = () => used++;
      final logger = _Logger(dao);
      c.bindLogger(logger);

      final first = c.okSetup();
      expect(first.setup.blendTarget, target);
      await stored('a1', target);
      logger.send(complete(first, 'a1'));
      // Held until the entry is read back.
      expect(c.okSetup().setup.blendTarget, isNull);
      await _settle();

      expect(used, 0, reason: 'the OK path is marked by AnalyzerSession');
      expect(c.unusedBlendTarget, isNull);
      expect(c.okSetup().setup.blendTarget, isNull);
    });

    test('a complete result with another mix leaves the target', () async {
      final c = await make(blendTarget: target, unusedBlendTarget: target);
      var used = 0;
      c.onBlendTargetUsed = () => used++;
      final logger = _Logger(dao);
      c.bindLogger(logger);

      final first = c.okSetup();
      await stored('a1', const DesiredMix(18, 45));
      logger.send(complete(first, 'a1'));
      await _settle();

      expect(used, 0);
      expect(c.okSetup().setup.blendTarget, target);
    });

    test('is offered to one press at a time, until that press is known',
        () async {
      final c = await make(blendTarget: target, unusedBlendTarget: target);
      var used = 0;
      c.onBlendTargetUsed = () => used++;
      final logger = _Logger(dao);
      c.bindLogger(logger);

      final first = c.okSetup();
      expect(first.setup.blendTarget, target);
      // A press queued behind it asks before the first one's result is in.
      final queued = c.okSetup();
      expect(queued.setup.blendTarget, isNull);

      // The first one needs sign-off: the target is free again.
      logger.send(_result(first, complete: false));
      expect(used, 0);
      expect(c.okSetup().setup.blendTarget, target);
    });

    test('a new Blend target is offered although an old one is out',
        () async {
      final c = await make(blendTarget: target, unusedBlendTarget: target);
      c.bindLogger(_Logger(dao));
      expect(c.okSetup().setup.blendTarget, target);

      const next = DesiredMix(21, 35);
      c.update(
        reading: _ean32,
        stability: ReadingStability.stable,
        blendTarget: next,
        unusedBlendTarget: next,
        connected: true,
      );
      expect(c.okSetup().setup.blendTarget, next);
    });

    test('a new logger frees the target', () async {
      final c = await make(blendTarget: target, unusedBlendTarget: target);
      c.bindLogger(_Logger(dao));
      expect(c.okSetup().setup.blendTarget, target);
      c.bindLogger(_Logger(dao));
      expect(c.okSetup().setup.blendTarget, target);
    });
  });

  test('tapping the role that is shown makes it the diver\'s', () async {
    final c = await make();
    expect(c.role, GasRole.bailout, reason: 'EAN32 by the rule');
    expect(c.roleTapped, isFalse);
    expect(c.okSetup().setup.gasRole, isNull);

    c.tapRole(GasRole.bailout);
    expect(c.roleTapped, isTrue);
    expect(c.okSetup().setup.gasRole, GasRole.bailout);
  });

  test('a non-number fill pressure is passed as no pressure', () async {
    final c = await make();
    final logger = _Logger(dao);
    c.bindLogger(logger);

    c.fillPressure.text = '21o';
    final taken = c.okSetup();
    expect(taken.setup.fillPressureBar, isNull);

    logger.send(_result(taken, complete: true));
    // Not used up: the diver still sees what to fix.
    expect(c.fillPressure.text, '21o');

    c.fillPressure.text = '199,5';
    expect(c.okSetup().setup.fillPressureBar, 199.5);
  });

  test('a new logger starts a new run and a null one ends it', () async {
    final c = await make();
    final first = _Logger(dao);
    c.bindLogger(first);
    first.send(_result(c.okSetup(), complete: true));
    expect(c.okResult, isNotNull);

    final second = _Logger(dao);
    c.bindLogger(second);
    expect(c.okResult, isNull);
    expect(first.setupProvider, isNull);
    expect(second.setupProvider, isNotNull);

    c.bindLogger(null);
    expect(second.setupProvider, isNull);
  });

  test('a disposed controller leaves the setup of its successor alone',
      () async {
    final logger = _Logger(dao);
    final first = AnalysisSaveController(dao: dao, settings: settings)
      ..bindLogger(logger);
    final firstSetup = logger.setupProvider;
    expect(firstSetup, isNotNull);

    // A new controller binds first; the old one is disposed after it and
    // must not take the new one's setup away.
    final second = AnalysisSaveController(dao: dao, settings: settings)
      ..bindLogger(logger);
    first.dispose();
    expect(logger.setupProvider, isNotNull);
    expect(logger.setupProvider, isNot(equals(firstSetup)));

    // The last one going does clear it.
    second.dispose();
    expect(logger.setupProvider, isNull);
    await _settle();
  });

  test('the chips: the selected mix, the Blend target, then the log',
      () async {
    GasAnalysis logged(String id, int day, int o2, int he) => GasAnalysis(
          id: id,
          analysedAt: DateTime(2026, 10, day),
          o2Percent: o2.toDouble(),
          hePercent: he.toDouble(),
          stable: true,
          targetO2Percent: o2,
          targetHePercent: he,
        );
    dao.analyses.addAll([
      logged('l1', 30, 32, 0),
      logged('l2', 29, 18, 45),
      logged('l3', 28, 15, 55),
    ]);
    final c = await make();
    expect(c.mixOptions, [
      const DesiredMix(32, 0),
      const DesiredMix(18, 45),
      const DesiredMix(15, 55),
    ]);

    // A new Blend target comes second, and the list stays at three.
    c.update(
      reading: _ean32,
      stability: ReadingStability.stable,
      blendTarget: const DesiredMix(21, 35),
      connected: true,
    );
    expect(c.mixOptions, [
      const DesiredMix(32, 0),
      const DesiredMix(21, 35),
      const DesiredMix(18, 45),
    ]);
  });

  test('"Analysed by", the fill pressure and "Print label on OK" start '
      'from the settings', () async {
    await settings.setYourInitials('EdP');
    await settings.setAnalyzerFillPressureStartBar(200);
    await settings.setAnalyzerPrintOnOk(false);
    final c = await make();
    expect(c.analysedBy.text, 'EdP');
    expect(c.fillPressure.text, '200');
    expect(c.printOnOk, isFalse);

    c.setPrintOnOk(true);
    expect(c.printOnOk, isTrue);
    expect(settings.analyzerPrintOnOk, isTrue);
  });
}
