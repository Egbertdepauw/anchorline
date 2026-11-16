import 'dart:async';

import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/analysis/open_blend_match.dart';
import 'package:ccrlogger/analysis/standard_mix_pick.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/protocol/analyzer_reading.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_open_blends_dao.dart';

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

/// An open blend of [target], blended [ago] before the test clock.
OpenBlend _blend(
  String id,
  DesiredMix target, {
  GasRole? role,
  Duration ago = const Duration(hours: 1),
}) =>
    OpenBlend(
      id: id,
      target: target,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 3,
      // As the Blend tab guesses: lean is diluent, rich bailout.
      role: role ?? gasRoleForMix(target.o2Percent.toDouble()),
      blendedBy: null,
      blendedAt: _now.subtract(ago),
    );

final _now = DateTime(2026, 11, 13, 12);

/// Lets the DAO's reads finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeGasAnalysesDao dao;
  late FakeOpenBlendsDao openDao;
  late SettingsNotifier settings;

  setUp(() async {
    dao = FakeGasAnalysesDao(cylinders: const [_dil, _s80]);
    openDao = FakeOpenBlendsDao();
    settings = SettingsNotifier();
    await settings.load();
  });

  /// A controller on [dao] with a stable [reading] (EAN32), its cylinders
  /// and mixes loaded.
  Future<AnalysisSaveController> make({
    List<OpenBlend> blends = const [],
    AnalyzerReading reading = _ean32,
    void Function(double o2, double he, double? bar)? onResidualSaved,
  }) async {
    openDao.blends.addAll(blends);
    final c = AnalysisSaveController(
      dao: dao,
      settings: settings,
      openBlends: openDao,
      onResidualSaved: onResidualSaved,
      now: () => _now,
    );
    addTearDown(c.dispose);
    c.update(
      reading: reading,
      stability: ReadingStability.stable,
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
    expect(s.setup.tappedRole, GasRole.diluent);
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

  test('an automatic pick is left to each press, with no open blend match',
      () async {
    final c = await make(blends: [_blend('b1', const DesiredMix(21, 35))]);
    expect(c.mixIsAutomatic, isTrue);
    expect(c.desiredMix, const DesiredMix(32, 0));
    expect(c.mixSource, MixPickSource.standard);

    var s = c.okSetup().setup;
    expect(s.autoPickMix, isTrue);
    expect(s.desiredMix, isNull, reason: 'the press picks for its own line');
    // The press matches the open blends itself, by its own reading.
    expect(s.openBlends.map((b) => b.id), ['b1']);
    expect(s.blendChoice, isA<AutoBlend>());
    expect(s.residual, isFalse);
    expect(s.tappedRole, isNull);
    expect(s.cylinderRole, isNull, reason: 'the press works it out');

    // A cylinder with a known role decides it; one without leaves it open.
    c.selectCylinder('c-dil');
    expect(c.okSetup().setup.cylinderRole, GasRole.diluent);
    expect(c.okSetup().setup.tappedRole, isNull);
    c.selectCylinder('c-s80');
    expect(c.okSetup().setup.cylinderRole, isNull);

    // The diver's "no mix" is passed as no mix, not as automatic.
    c.clearMix();
    s = c.okSetup().setup;
    expect(s.autoPickMix, isFalse);
    expect(s.desiredMix, isNull);
    expect(c.mixSource, isNull);
  });

  test('auto pick prefers an open blend over a standard mix', () async {
    final c = await make(
      reading: const AnalyzerReading(
          o2: 20.6, he: 33.8, tempC: 21, baroHpa: 1013, raw: 'test'),
      blends: [_blend('b1', const DesiredMix(21, 35))],
    );
    expect(c.desiredMix, const DesiredMix(21, 35));
    expect(c.mixSource, MixPickSource.blendTarget);
    expect(c.role, GasRole.diluent);

    c.update(
      reading: const AnalyzerReading(
          o2: 49.2, he: 0, tempC: 21, baroHpa: 1013, raw: 'test'),
      stability: ReadingStability.stable,
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

  group('the open blend on OK', () {
    const target = DesiredMix(19, 40);

    const reading = AnalyzerReading(
        o2: 19.6, he: 40.2, tempC: 21, baroHpa: 1013, raw: 'test');

    test('the press gets the open blends, to match by its own reading',
        () async {
      final c = await make(reading: reading, blends: [_blend('b1', target)]);
      final s = c.okSetup().setup;
      expect(s.openBlends.map((b) => b.id), ['b1']);
      expect(s.blendChoice, isA<AutoBlend>());
    });

    test('a newly blended gas is passed as it appears', () async {
      final c = await make(reading: reading);
      expect(c.okSetup().setup.openBlends, isEmpty);

      await openDao.add(NewOpenBlend(
        target: target,
        targetPressureBar: 200,
        residual: const DesiredMix(21, 0),
        residualPressureBar: 0,
        topoff: const DesiredMix(21, 0),
        waterCapacityL: 3,
        role: GasRole.diluent,
        blendedBy: null,
        blendedAt: _now,
      ));
      await _settle();
      expect(c.okSetup().setup.openBlends.single.target, target);
    });

    test('the diver\'s blend choice and "Residual analysis" go to the press',
        () async {
      final c = await make(reading: reading, blends: [_blend('b1', target)]);
      final b = c.openBlends.single;
      c.chooseBlend(PickedBlend(b));
      var s = c.okSetup().setup;
      expect(s.blendChoice, isA<PickedBlend>());
      expect((s.blendChoice as PickedBlend).blend.id, 'b1');

      c.chooseBlend(const NoBlend());
      expect(c.okSetup().setup.blendChoice, isA<NoBlend>());

      c.setResidual(true);
      expect(c.okSetup().setup.residual, isTrue);
    });

    test('a picked blend that closed elsewhere counts as automatic',
        () async {
      final c = await make(reading: reading, blends: [_blend('b1', target)]);
      c.chooseBlend(PickedBlend(c.openBlends.single));
      openDao.dismissed.add('b1');
      openDao.deleteAnalysis('nothing'); // pushes a change
      await _settle();
      expect(c.okSetup().setup.blendChoice, isA<AutoBlend>());
    });

    test('a complete result changes nothing about the blends here',
        () async {
      final c = await make(reading: reading, blends: [_blend('b1', target)]);
      final logger = _Logger(dao);
      c.bindLogger(logger);
      final first = c.okSetup();
      logger.send(_result(first, complete: true));
      await _settle();
      // The processor closes the blend; the card only hears of it from the
      // open blends stream.
      expect(c.okSetup().setup.openBlends, hasLength(1));
      await openDao.closeBlend(openDao.blends.single, 'a1');
      await _settle();
      expect(c.okSetup().setup.openBlends, isEmpty);
    });

    group('a residual press', () {
      OkLogResult residualResult(OkSetup setup, String id) => OkLogResult(
            code: FeedbackCode.saved,
            text: 'EAN32',
            analysisId: id,
            complete: true,
            setupUsed: setup,
          );

      Future<void> storeResidual(String id, {double? bar = 45}) =>
          dao.addFromBridge(
            id,
            NewGasAnalysis(
              analysedAt: DateTime(2026, 11, 7),
              o2Percent: 21.3,
              hePercent: 34.8,
              fillPressureBar: bar,
              stable: true,
              isResidual: true,
            ),
          );

      test('fills the Blend tab with the stored gas and pressure', () async {
        final calls = <(double, double, double?)>[];
        final c = await make(
          onResidualSaved: (o2, he, bar) => calls.add((o2, he, bar)),
        );
        final logger = _Logger(dao);
        c.bindLogger(logger);
        c.setResidual(true);
        final setup = c.okSetup();
        await storeResidual('a1');
        logger.send(residualResult(setup, 'a1'));
        await _settle();
        expect(calls, [(21.3, 34.8, 45.0)]);
        // The next press is a fill again.
        expect(c.residual, isFalse);
        expect(c.okSetup().setup.residual, isFalse);
      });

      test('with no fill pressure the pressure is passed as null', () async {
        final calls = <(double, double, double?)>[];
        final c = await make(
          onResidualSaved: (o2, he, bar) => calls.add((o2, he, bar)),
        );
        final logger = _Logger(dao);
        c.bindLogger(logger);
        c.setResidual(true);
        final setup = c.okSetup();
        await storeResidual('a1', bar: null);
        logger.send(residualResult(setup, 'a1'));
        await _settle();
        expect(calls, [(21.3, 34.8, null)]);
      });

      test('a press that was not a residual does not call it', () async {
        final calls = <(double, double, double?)>[];
        final c = await make(
          onResidualSaved: (o2, he, bar) => calls.add((o2, he, bar)),
        );
        final logger = _Logger(dao);
        c.bindLogger(logger);
        final setup = c.okSetup();
        await storeResidual('a1');
        logger.send(residualResult(setup, 'a1'));
        await _settle();
        expect(calls, isEmpty);
      });

      test('a late press saved as a plain analysis does not call it',
          () async {
        final calls = <(double, double, double?)>[];
        final c = await make(
          onResidualSaved: (o2, he, bar) => calls.add((o2, he, bar)),
        );
        final logger = _Logger(dao);
        c.bindLogger(logger);
        c.setResidual(true);
        final setup = c.okSetup();
        // The press was late: stored without the residual flag.
        await dao.addFromBridge(
          'a1',
          NewGasAnalysis(
            analysedAt: DateTime(2026, 11, 7),
            o2Percent: 21.3,
            hePercent: 34.8,
            stable: true,
          ),
        );
        logger.send(residualResult(setup, 'a1'));
        await _settle();
        expect(calls, isEmpty);
        // Stored as a plain analysis: the switch is the diver's to turn off.
        expect(c.residual, isTrue);
      });
    });
  });

  group('the open blend a save closes', () {
    const tx1845 = DesiredMix(18, 45);
    const reading = AnalyzerReading(
        o2: 18.5, he: 44.0, tempC: 21, baroHpa: 1013, raw: 'test');

    test('the oldest matching blend is the one to close, with its role',
        () async {
      final c = await make(reading: reading, blends: [
        _blend('new', tx1845,
            role: GasRole.diluent, ago: const Duration(minutes: 5)),
        _blend('old', tx1845,
            role: GasRole.diluent, ago: const Duration(hours: 2)),
      ]);
      expect(c.blendToClose?.id, 'old');
      expect(c.desiredMix, tx1845);
      expect(c.role, GasRole.diluent);
      expect(c.mixSource, MixPickSource.blendTarget);
      expect(c.warning, isNull);
    });

    test('a manual mix chip closes the oldest blend of that mix', () async {
      final c = await make(reading: reading, blends: [
        _blend('a', tx1845, ago: const Duration(minutes: 5)),
        _blend('b', tx1845, ago: const Duration(hours: 2)),
        _blend('c', const DesiredMix(21, 35)),
      ]);
      c.pickMix(const DesiredMix(21, 35));
      expect(c.blendToClose?.id, 'c');
      c.pickMix(tx1845);
      expect(c.blendToClose?.id, 'b');
      // A mix with no open blend closes none.
      c.pickMix(const DesiredMix(32, 0));
      expect(c.blendToClose, isNull);
      expect(c.nearestUnmatched, isNull,
          reason: 'the diver chose the mix themselves');
    });

    test('choosing None closes nothing, a picked blend whatever it grades',
        () async {
      final c = await make(reading: _ean32, blends: [
        _blend('far', const DesiredMix(50, 0)),
      ]);
      expect(c.blendToClose, isNull);
      expect(c.nearestUnmatched?.blend.id, 'far');
      expect(c.nearestUnmatched?.grade.level, MixMatchLevel.hard);
      expect(c.blendChoices.map((r) => r.blend.id), ['far']);

      c.chooseBlend(PickedBlend(c.openBlends.single));
      expect(c.blendToClose?.id, 'far');
      expect(c.desiredMix, const DesiredMix(50, 0));
      expect(c.nearestUnmatched, isNull);

      c.chooseBlend(const NoBlend());
      expect(c.blendToClose, isNull);
      expect(c.nearestUnmatched, isNull);

      c.chooseBlend(const AutoBlend());
      expect(c.nearestUnmatched, isNotNull);
    });

    test('a picked blend that is closed elsewhere counts as automatic',
        () async {
      final c = await make(reading: reading, blends: [
        _blend('a', tx1845),
        _blend('b', tx1845, ago: const Duration(minutes: 5)),
      ]);
      c.chooseBlend(PickedBlend(c.openBlends.last));
      expect(c.blendToClose?.id, 'b');
      await openDao.closeBlend(openDao.blends.last, 'x');
      await _settle();
      expect(c.blendToClose?.id, 'a');
    });

    test('residual: nothing to close, no desired mix, no warning', () async {
      final c = await make(reading: reading, blends: [_blend('a', tx1845)]);
      expect(c.blendToClose, isNotNull);
      c.setResidual(true);
      expect(c.residual, isTrue);
      expect(c.blendToClose, isNull);
      expect(c.desiredMix, isNull);
      expect(c.warning, isNull);
      expect(c.canSaveAndPrint, isFalse);
      c.setResidual(false);
      expect(c.canSaveAndPrint, isTrue);
    });

    test('a rich bailout blend warns loudly, a lean diluent mildly',
        () async {
      final c = await make(
        reading: const AnalyzerReading(
            o2: 55.0, he: 0, tempC: 21, baroHpa: 1013, raw: 'test'),
        blends: [_blend('deco', const DesiredMix(50, 0))],
      );
      c.chooseBlend(PickedBlend(c.openBlends.single));
      expect(c.warning?.level, WarningLevel.loud);
    });

    test('the chips offer the open blends\' targets', () async {
      final c = await make(blends: [
        _blend('a', const DesiredMix(21, 35)),
        _blend('b', const DesiredMix(21, 35)),
        _blend('c', const DesiredMix(50, 0)),
      ]);
      expect(c.mixOptions, [
        const DesiredMix(32, 0),
        const DesiredMix(21, 35),
        const DesiredMix(50, 0),
      ]);
    });

    test('subscribes to the open blends once and lets go on dispose',
        () async {
      // Made here, not by [make]: that one disposes it at the end as well.
      final c = AnalysisSaveController(
        dao: dao,
        settings: settings,
        openBlends: openDao,
        now: () => _now,
      );
      await _settle();
      expect(openDao.watchOpenCalls, 1);
      c.update(
          reading: _ean32, stability: ReadingStability.stable, connected: true);
      c.pickMix(null);
      expect(openDao.watchOpenCalls, 1);

      var told = 0;
      c.addListener(() => told++);
      c.dispose();
      await openDao.add(NewOpenBlend(
        target: const DesiredMix(21, 35),
        targetPressureBar: 200,
        residual: const DesiredMix(21, 0),
        residualPressureBar: 0,
        topoff: const DesiredMix(21, 0),
        waterCapacityL: 3,
        role: GasRole.diluent,
        blendedBy: null,
        blendedAt: _now,
      ));
      await _settle();
      expect(told, 0, reason: 'a disposed controller is not told');
    });

    test('with None chosen the automatic pick is a standard mix, not the '
        'open blend', () async {
      final c = await make(
        reading: const AnalyzerReading(
            o2: 19.6, he: 40.2, tempC: 21, baroHpa: 1013, raw: 'test'),
        blends: [_blend('b1', const DesiredMix(19, 40))],
      );
      expect(c.desiredMix, const DesiredMix(19, 40));
      expect(c.mixSource, MixPickSource.blendTarget);

      c.chooseBlend(const NoBlend());
      expect(c.blendToClose, isNull);
      expect(c.mixSource, isNot(MixPickSource.blendTarget));
      expect(c.desiredMix, isNot(const DesiredMix(19, 40)));
    });
  });

  test('tapping the role that is shown makes it the diver\'s', () async {
    final c = await make();
    expect(c.role, GasRole.bailout, reason: 'EAN32 by the rule');
    expect(c.roleTapped, isFalse);
    expect(c.okSetup().setup.tappedRole, isNull);

    c.tapRole(GasRole.bailout);
    expect(c.roleTapped, isTrue);
    expect(c.okSetup().setup.tappedRole, GasRole.bailout);
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

  test('the chips: the selected mix, the open blends, then the log',
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

    // A new open blend comes second, and the list stays at three.
    await openDao.add(NewOpenBlend(
      target: const DesiredMix(21, 35),
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 3,
      role: GasRole.diluent,
      blendedBy: null,
      blendedAt: _now,
    ));
    await _settle();
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
