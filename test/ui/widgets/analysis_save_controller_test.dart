import 'dart:async';

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

  /// A controller on [dao] with a stable EAN32 reading, its cylinders and
  /// mixes loaded.
  Future<AnalysisSaveController> make({DesiredMix? blendTarget}) async {
    final c = AnalysisSaveController(dao: dao, settings: settings);
    addTearDown(c.dispose);
    c.update(
      reading: _ean32,
      stability: ReadingStability.stable,
      blendTarget: blendTarget,
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
    expect(settings.analyzerAnalysedBy, isNull, reason: 'not per keystroke');

    final s = c.okSetup();
    expect(s.copies, 3);
    expect(s.setup.cylinderId, 'c-s80');
    expect(s.setup.desiredMix, const DesiredMix(32, 0));
    expect(s.setup.gasRole, GasRole.diluent);
    expect(s.setup.analysedBy, 'EdP');
    expect(s.setup.analysedFor, 'Anna');
    expect(s.setup.fillPressureBar, 200);
    expect(s.setup.notes, 'Topped up');
    expect(s.setup.modPpo2s, settings.analyzerModPpo2s);
    // No printer is set up, so nothing prints on OK.
    expect(s.setup.printerConfigured, isFalse);
    expect(s.setup.printOnOk, isFalse);
    // An OK press taking the setup writes the name.
    expect(settings.analyzerAnalysedBy, 'EdP');
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

  test('a new Blend target reloads the mix options', () async {
    dao.analyses.add(GasAnalysis(
      id: 'l1',
      analysedAt: DateTime(2026, 10, 30),
      o2Percent: 32,
      hePercent: 0,
      stable: true,
      targetO2Percent: 32,
      targetHePercent: 0,
    ));
    final c = await make();
    expect(c.mixOptions, [const DesiredMix(32, 0)]);

    c.update(
      reading: _ean32,
      stability: ReadingStability.stable,
      blendTarget: const DesiredMix(21, 35),
      connected: true,
    );
    await _settle();
    expect(c.mixOptions, [const DesiredMix(21, 35), const DesiredMix(32, 0)]);
  });

  test('"Analysed by" and "Print label on OK" start from the settings',
      () async {
    await settings.setAnalyzerAnalysedBy('EdP');
    await settings.setAnalyzerPrintOnOk(false);
    final c = await make();
    expect(c.analysedBy.text, 'EdP');
    expect(c.printOnOk, isFalse);

    c.setPrintOnOk(true);
    expect(c.printOnOk, isTrue);
    expect(settings.analyzerPrintOnOk, isTrue);
  });
}
