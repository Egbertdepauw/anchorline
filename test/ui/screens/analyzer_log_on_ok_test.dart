import 'dart:async';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_label_printer.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// A SOLO line as the trimix model prints it.
String _line(double o2, double he) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';

/// A transport the test drives line by line. Delivery is synchronous, so a
/// line reaches the controller and the logger at the time it is emitted.
class _FakeSolo implements AnalyzerTransport {
  final _lines = StreamController<String>.broadcast(sync: true);
  final _statuses =
      StreamController<AnalyzerConnectionStatus>.broadcast(sync: true);
  AnalyzerConnectionStatus _status = AnalyzerConnectionStatus.disconnected;

  void emitLine(String line) => _lines.add(line);

  void _set(AnalyzerConnectionStatus s) {
    _status = s;
    _statuses.add(s);
  }

  @override
  String get name => 'Fake SOLO';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  AnalyzerConnectionStatus get status => _status;
  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _statuses.stream;
  @override
  String? get errorMessage => null;
  @override
  Future<void> connect() async => _set(AnalyzerConnectionStatus.connected);
  @override
  Future<void> disconnect() async =>
      _set(AnalyzerConnectionStatus.disconnected);
  @override
  Future<void> dispose() async {}
}

/// A log whose saves wait for [gate], like a slow database.
class _SlowDao extends FakeGasAnalysesDao {
  _SlowDao({super.cylinders});

  Completer<void>? gate;

  @override
  Future<bool> addFromBridge(String id, NewGasAnalysis a) async {
    await gate?.future;
    return super.addFromBridge(id, a);
  }
}

const _dil =
    CylinderChoice(id: 'c-dil', label: 'Dil 3L', role: CylinderRole.diluent);
const _s80 = CylinderChoice(id: 'c-s80', label: 'S80 left');

/// The screen on a [_FakeSolo], a [FakeGasAnalysesDao] and a logger on the
/// test's clock that the test holds.
class _Harness {
  _Harness({bool printer = false, FakeGasAnalysesDao? dao})
      : dao = dao ?? FakeGasAnalysesDao(cylinders: const [_dil, _s80]) {
    if (printer) {
      fakePrinter = FakeLabelPrinter();
      printing = LabelPrintService(
        render: (label) async => LabelBitmap.blank(384, 240),
        printerFor: (_) => fakePrinter!,
        scanner: FakeLabelPrinterScanner(),
        printerId: () => printerSetUp ? 'dev-1' : null,
        use14ForDeeperMixes: () => false,
      );
    }
  }

  final FakeGasAnalysesDao dao;
  FakeLabelPrinter? fakePrinter;
  LabelPrintService? printing;

  /// A printer is saved on the device; a test can set one up later.
  bool printerSetUp = true;
  late SettingsNotifier settings;
  late AnalyzerController controller;

  /// The transport of the latest session.
  _FakeSolo? solo;

  /// The logger the screen built last, and how many it built.
  UsbOkLogger? logger;
  int loggersBuilt = 0;

  /// The logger's results stream is closed: the screen disposed it.
  bool loggerClosed = false;

  /// Every request to stay awake (true) or let go (false), in order.
  final awake = <bool>[];

  Future<void> pump(
    WidgetTester tester, {
    bool withDao = true,
    SettingsNotifier? useSettings,
    Size size = const Size(400, 3200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (useSettings != null) {
      settings = useSettings;
    } else {
      settings = SettingsNotifier();
      await settings.load();
    }
    await tester.pumpWidget(MaterialApp(
      home: AnalyzerScreen(
        settings: settings,
        analysesDao: withDao ? dao : null,
        controller: controller =
            AnalyzerController(elapsed: fakeElapsed(tester)),
        blendTarget: const DesiredMix(32, 0),
        labelPrinting: printing,
        keepAwake: (on) async => awake.add(on),
        transportOptions: [
          AnalyzerTransportOption(
            label: 'Bench',
            create: () => solo = _FakeSolo(),
          ),
          AnalyzerTransportOption(
            label: 'Demo',
            isDemo: true,
            create: () => DemoAnalyzerTransport(),
          ),
        ],
        okLoggerFactory: () {
          loggersBuilt++;
          loggerClosed = false;
          final l = buildOkLogger(
            dao: dao,
            printing: printing,
            elapsed: fakeElapsed(tester),
            tickInterval: null,
          );
          l.results.listen((_) {}, onDone: () => loggerClosed = true);
          return logger = l;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The Connect / Disconnect button.
  Future<void> connect(WidgetTester tester) async {
    await tester.tap(_key('analyzer-connect'));
    await tester.pump();
  }

  /// Leaves the screen and stops the controller's timers, which the test
  /// binding insists on at the end of a test.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }

  /// [seconds] of readings, two lines a second, on the test clock.
  Future<void> feed(
    WidgetTester tester,
    double o2,
    double he, {
    int seconds = 25,
  }) async {
    for (var i = 0; i < seconds * 2; i++) {
      solo!.emitLine(_line(o2, he));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  /// The SOLO goes quiet for 2.2 s, as it does on OK; the logger's timer
  /// would tick, the test ticks by hand.
  Future<void> pressOk(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2200));
    logger!.tick();
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _pickSource(WidgetTester tester, String label) async {
  await tester.tap(_key('analyzer-transport'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _switchOn(WidgetTester tester) async {
  await tester.tap(_key('analyzer-log-on-ok'));
  await tester.pump();
}

/// The setup of a stable EAN32 for the name "EdP": the chip, the name.
Future<void> _setUp(WidgetTester tester) async {
  await tester.tap(_key('desired-mix-32-0'));
  await tester.pump();
  await tester.enterText(_key('analysis-diver'), 'EdP');
  await tester.pump();
}

/// The keyboard's Done on the field being edited.
Future<void> _done(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

Future<void> _pickCylinder(WidgetTester tester, String label) async {
  await tester.tap(_key('analysis-cylinder'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The message of the result on the card.
String _resultText(WidgetTester tester) =>
    tester.widget<Text>(_key('analysis-ok-result')).data ?? '';

/// A widget test on a [_Harness] that is ended properly afterwards.
void _test(
  String description,
  Future<void> Function(WidgetTester tester, _Harness h) body, {
  bool printer = false,
  FakeGasAnalysesDao? dao,
}) {
  testWidgets(description, (tester) async {
    final h = _Harness(printer: printer, dao: dao);
    try {
      await body(tester, h);
    } finally {
      await h.end(tester);
    }
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the switch', () {
    _test('Log on OK is offered for USB, not for the demo', (tester, h) async {
      await h.pump(tester);
      expect(_key('analyzer-log-on-ok'), findsOneWidget);
      expect(find.text('Log on OK'), findsOneWidget);
      expect(find.text('Press OK on the SOLO to save. Keep this screen open.'),
          findsOneWidget);

      await _pickSource(tester, 'Demo');
      expect(_key('analyzer-log-on-ok'), findsNothing);
    });

    _test('the wide layout has the switch and the OK hint too',
        (tester, h) async {
      await h.pump(tester, size: const Size(1200, 1600));
      await _switchOn(tester);
      await h.connect(tester);
      expect(_key('analyzer-log-on-ok'), findsOneWidget);
      expect(_key('analysis-ok-hint'), findsOneWidget);
      expect(_key('analysis-save'), findsNothing);
    });

    _test('without a log there is no switch', (tester, h) async {
      await h.pump(tester, withDao: false);
      expect(_key('analyzer-log-on-ok'), findsNothing);
    });

    _test('the switch is remembered on the device', (tester, h) async {
      await h.pump(tester);
      expect(h.settings.analyzerLogOnOk, isFalse);
      await _switchOn(tester);
      expect(h.settings.analyzerLogOnOk, isTrue);
      final again = SettingsNotifier();
      await again.load();
      expect(again.analyzerLogOnOk, isTrue);
    });

    _test('no logger without a connection, the card stays manual',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      expect(h.loggersBuilt, 0);
      expect(_key('analysis-save'), findsOneWidget);
      expect(_key('analysis-ok-hint'), findsNothing);
      expect(_key('analysis-print-on-ok'), findsNothing);
    });

    _test('a demo session never gets a logger', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await _pickSource(tester, 'Demo');
      await h.connect(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(h.loggersBuilt, 0);
    });
  });

  group('the card in Log on OK mode', () {
    _test('with Log on OK on, the card shows the OK hint instead of Save',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);

      expect(h.loggersBuilt, 1);
      expect(_key('analysis-ok-hint'), findsOneWidget);
      expect(find.text('Press OK on the SOLO to save'), findsOneWidget);
      expect(_key('analysis-save'), findsNothing);
      expect(_key('analysis-save-print'), findsNothing);
      // The fields of the setup are still there, with "For" in both modes.
      expect(_key('analysis-diver'), findsOneWidget);
      expect(_key('analysis-for'), findsOneWidget);
      expect(_key('analysis-pressure'), findsOneWidget);
      expect(_key('analysis-notes'), findsOneWidget);
      expect(_key('analysis-cylinder'), findsOneWidget);
      // No printer here, so nothing to switch on.
      expect(
        tester
            .widget<SwitchListTile>(_key('analysis-print-on-ok'))
            .onChanged,
        isNull,
      );
    });

    _test('an unstable reading asks to wait before pressing OK',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);

      await h.feed(tester, 32.0, 0, seconds: 3);
      expect(
        find.text(
            'Reading not stable yet. Wait for STABLE before pressing OK.'),
        findsOneWidget,
      );
    });

    _test('room air brings Save back', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);

      await h.feed(tester, 20.9, 0, seconds: 3);
      expect(find.text("Air isn't logged on OK. Tap Save."), findsOneWidget);
      expect(_key('analysis-ok-hint'), findsOneWidget);
      expect(_key('analysis-save'), findsOneWidget);

      await h.feed(tester, 32.0, 0, seconds: 3);
      expect(find.text('Press OK on the SOLO to save'), findsOneWidget);
      expect(_key('analysis-save'), findsNothing);
    });

    _test('an OK on air says it was not logged and saves nothing',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);

      await h.feed(tester, 20.9, 0);
      await h.pressOk(tester);

      expect(h.dao.addedFromBridge, isEmpty);
      expect(_resultText(tester), 'Room air: not logged');
      expect(_key('analysis-ok-edit'), findsNothing);
      expect(_key('analysis-ok-delete'), findsNothing);
    });

    _test('an OK press saves, shows the result and offers Edit and Delete',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      expect(h.dao.addedFromBridge, hasLength(1));
      expect(h.dao.added, isEmpty);
      final (id, a) = h.dao.addedFromBridge.single;
      expect(a.o2Percent, closeTo(32.0, 0.01));
      expect(a.analysedBy, 'EdP');
      expect(a.desiredMix, const DesiredMix(32, 0));
      expect(a.needsSignoff, isFalse);
      expect(h.dao.analyses.single.id, id);

      expect(_resultText(tester), 'Saved EAN32');
      expect(_key('analysis-ok-edit'), findsOneWidget);
      expect(_key('analysis-ok-delete'), findsOneWidget);
    });

    _test('the setup of the card is what the OK press saves',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await _pickCylinder(tester, 'Dil 3L');
      await tester.enterText(_key('analysis-for'), 'Anna');
      await tester.enterText(_key('analysis-pressure'), '210,5');
      await tester.enterText(_key('analysis-notes'), 'Topped up');
      await tester.pump();

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      final a = h.dao.addedFromBridge.single.$2;
      expect(a.cylinderId, 'c-dil');
      expect(a.gasRole, GasRole.diluent);
      expect(a.analysedFor, 'Anna');
      expect(a.fillPressureBar, 210.5);
      expect(a.notes, 'Topped up');
      expect(a.modPpo2s, h.settings.analyzerModPpo2s);
      expect(a.captureSource, CaptureSource.usbOk);
    });

    _test('Edit opens the sheet on the stored entry', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      expect(_key('analysis-edit-sheet'), findsOneWidget);
      expect(find.text('EdP'), findsWidgets);
    });

    _test('Delete on the result asks, then soft-deletes', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      final id = h.dao.addedFromBridge.single.$1;

      await tester.tap(_key('analysis-ok-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this analysis?'), findsOneWidget);
      expect(h.dao.deleted, isEmpty);

      // Cancel leaves it all as it was.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.dao.deleted, isEmpty);
      expect(_key('analysis-ok-result'), findsOneWidget);

      await tester.tap(_key('analysis-ok-delete'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-ok-delete-confirm'));
      await tester.pumpAndSettle();
      expect(h.dao.deleted, [id]);
      expect(_key('analysis-ok-result'), findsNothing);
    });

    _test(
        'a complete save clears cylinder, pressure and notes, '
        'keeps name, mix and role', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await _pickCylinder(tester, 'Dil 3L'); // role: diluent
      await tester.enterText(_key('analysis-for'), 'Anna');
      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.enterText(_key('analysis-notes'), 'Topped up');
      await tester.pump();

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(_resultText(tester), 'Saved EAN32');

      expect(find.text('200'), findsNothing);
      expect(find.text('Topped up'), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String?>>(_key('analysis-cylinder'))
            .initialValue,
        isNull,
      );
      // Kept for the next cylinder.
      expect(find.text('EdP'), findsOneWidget);
      expect(find.text('Anna'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(_key('desired-mix-32-0'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<SegmentedButton<GasRole>>(_key('analysis-gas-role'))
            .selected,
        {GasRole.diluent},
      );
    });

    _test('a save that needs sign-off keeps the per-cylinder fields',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await _pickCylinder(tester, 'S80 left');
      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.enterText(_key('analysis-notes'), 'Topped up');
      await tester.pump();

      // Pressed far too early: 6 s of flow is not stable.
      await h.feed(tester, 32.0, 0, seconds: 6);
      await h.pressOk(tester);

      expect(h.dao.addedFromBridge.single.$2.needsSignoff, isTrue);
      expect(_resultText(tester), 'Needs sign-off: NOT STABLE');
      expect(_key('analysis-ok-edit'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('Topped up'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String?>>(_key('analysis-cylinder'))
            .initialValue,
        'c-s80',
      );
    });

    _test('with no name or mix the entry is saved for sign-off',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      expect(h.dao.addedFromBridge.single.$2.needsSignoff, isTrue);
      expect(_resultText(tester), 'Saved, needs sign-off: NO MIX SET');
    });

    _test('typing for the next cylinder while a press is saved is kept',
        (tester, h) async {
      final slow = h.dao as _SlowDao;
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.enterText(_key('analysis-notes'), 'first');
      await tester.pump();

      await h.feed(tester, 32.0, 0);
      slow.gate = Completer<void>();
      await h.pressOk(tester); // the save is under way
      expect(_key('analysis-ok-result'), findsNothing);

      // The diver already fills in the next cylinder.
      await tester.enterText(_key('analysis-pressure'), '180');
      await tester.pump();
      slow.gate!.complete();
      await tester.pump();
      await tester.pump();

      expect(_resultText(tester), 'Saved EAN32');
      expect(find.text('180'), findsOneWidget);
      // Notes were as the press took them, so they are used up.
      expect(find.text('first'), findsNothing);
    }, dao: _SlowDao(cylinders: const [_dil, _s80]));

    _test('Edit and Sign off turns the result into a plain Saved',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);

      await h.feed(tester, 32.0, 0, seconds: 6);
      await h.pressOk(tester);
      expect(_resultText(tester), 'Needs sign-off: NOT STABLE');

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-edit-signoff'));
      await tester.pumpAndSettle();

      expect(h.dao.analyses.single.needsSignoff, isFalse);
      expect(_resultText(tester), 'Saved EAN32');
    });

    _test('Edit and Sign off uses up the per-cylinder fields',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await _pickCylinder(tester, 'S80 left');
      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.enterText(_key('analysis-notes'), 'Topped up');
      await tester.pump();

      await h.feed(tester, 32.0, 0, seconds: 6);
      await h.pressOk(tester);
      // Needs sign-off: the fields stay.
      expect(find.text('200'), findsOneWidget);

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-edit-signoff'));
      await tester.pumpAndSettle();

      expect(_resultText(tester), 'Saved EAN32');
      expect(find.text('200'), findsNothing);
      expect(find.text('Topped up'), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String?>>(_key('analysis-cylinder'))
            .initialValue,
        isNull,
      );
      // And the rest of the setup stays.
      expect(find.text('EdP'), findsOneWidget);
    });

    _test('Edit and Sign off leaves what was typed since', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.pump();

      await h.feed(tester, 32.0, 0, seconds: 6);
      await h.pressOk(tester);
      // The next cylinder is already being filled in.
      await tester.enterText(_key('analysis-pressure'), '180');
      await tester.pump();

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-edit-signoff'));
      await tester.pumpAndSettle();

      expect(_resultText(tester), 'Saved EAN32');
      expect(find.text('180'), findsOneWidget);
    });

    _test('after an edit the result follows the entry as stored',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await h.feed(tester, 32.0, 0, seconds: 6);
      await h.pressOk(tester);
      expect(_resultText(tester), 'Needs sign-off: NOT STABLE');
      final id = h.dao.addedFromBridge.single.$1;

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      // Meanwhile the entry is signed off from another screen.
      await h.dao.setNeedsSignoff(id, false);
      await tester.tap(_key('analysis-edit-save'));
      await tester.pumpAndSettle();

      expect(_resultText(tester), 'Saved EAN32');
    });

    _test('Delete in the edit sheet clears the result', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      await tester.tap(_key('analysis-ok-edit'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-edit-delete'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-delete-confirm'));
      await tester.pumpAndSettle();

      expect(h.dao.deleted, hasLength(1));
      expect(_key('analysis-ok-result'), findsNothing);
    });
  });

  group('printing on OK', () {
    _test('the label prints and the entry is signed off', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      // On by default with a printer set up.
      expect(
        tester.widget<SwitchListTile>(_key('analysis-print-on-ok')).value,
        isTrue,
      );
      await tester.tap(_key('copies-inc'));
      await tester.pump();

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      await tester.pumpAndSettle();

      expect(h.fakePrinter!.printed, hasLength(1));
      expect(h.fakePrinter!.printed.single.$2, 2);
      final id = h.dao.addedFromBridge.single.$1;
      // Saved flagged, cleared after the print.
      expect(h.dao.addedFromBridge.single.$2.needsSignoff, isTrue);
      expect(h.dao.signoffChanges, [(id, false)]);
      expect(h.dao.analyses.single.needsSignoff, isFalse);
      expect(_resultText(tester), 'Printed EAN32');
    }, printer: true);

    _test('a printer set up after connecting prints from the next press',
        (tester, h) async {
      h.printerSetUp = false;
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      expect(
        tester.widget<SwitchListTile>(_key('analysis-print-on-ok')).value,
        isFalse,
      );

      // Set up through the card's link, which comes back to this screen.
      h.printerSetUp = true;
      await h.settings.setLabelPrinter(id: 'dev-1', name: 'Phomemo');
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(_key('analysis-print-on-ok')).value,
        isTrue,
      );

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      await tester.pumpAndSettle();

      expect(h.fakePrinter!.printed, hasLength(1));
      expect(_resultText(tester), 'Printed EAN32');
    }, printer: true);

    _test('with the print switch off the entry is saved, not printed',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await tester.tap(_key('analysis-print-on-ok'));
      await tester.pump();

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);

      expect(h.fakePrinter!.printed, isEmpty);
      expect(h.dao.addedFromBridge.single.$2.needsSignoff, isFalse);
      expect(_resultText(tester), 'Saved EAN32');
    }, printer: true);
  });

  group('the layout', () {
    _test('crossing the wide breakpoint keeps the card and its setup',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      await _pickCylinder(tester, 'Dil 3L'); // role: diluent
      await tester.enterText(_key('analysis-for'), 'Anna');
      await tester.pump();

      Future<void> resize(Size size) async {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump();
      }

      void expectSetupShown() {
        expect(find.text('EdP'), findsOneWidget);
        expect(find.text('Anna'), findsOneWidget);
        expect(
          tester.widget<ChoiceChip>(_key('desired-mix-32-0')).selected,
          isTrue,
        );
        expect(
          tester
              .widget<SegmentedButton<GasRole>>(_key('analysis-gas-role'))
              .selected,
          {GasRole.diluent},
        );
        expect(_key('analysis-ok-hint'), findsOneWidget);
      }

      // Narrow to wide: the same card, so the setup is still on it and
      // still the logger's.
      await resize(const Size(1200, 3200));
      expectSetupShown();
      expect(h.logger!.setupProvider, isNotNull);
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(h.dao.addedFromBridge, hasLength(1));
      var a = h.dao.addedFromBridge.last.$2;
      expect(a.analysedBy, 'EdP');
      expect(a.desiredMix, const DesiredMix(32, 0));
      expect(a.gasRole, GasRole.diluent);
      expect(a.analysedFor, 'Anna');
      expect(_resultText(tester), 'Saved EAN32');
      expectSetupShown();

      // And back.
      await resize(const Size(400, 3200));
      expectSetupShown();
      expect(_resultText(tester), 'Saved EAN32');
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(h.dao.addedFromBridge, hasLength(2));
      a = h.dao.addedFromBridge.last.$2;
      expect(a.analysedBy, 'EdP');
      expect(a.desiredMix, const DesiredMix(32, 0));
      expect(a.needsSignoff, isFalse);
      expect(h.loggersBuilt, 1);
    });

    testWidgets('a disposed card leaves the setup of its successor alone',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final logger = UsbOkLogger(
        save: dao.addFromBridge,
        markComplete: (id) => dao.setNeedsSignoff(id, false),
        tickInterval: null,
      );
      Widget card(int n) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnalysisSaveCard(
                  key: ValueKey('card-$n'),
                  dao: dao,
                  reading: null,
                  stability: ReadingStability.noData,
                  modPpo2s: const [1.4],
                  okLogger: logger,
                ),
              ),
            ),
          );

      await tester.pumpWidget(card(1));
      final first = logger.setupProvider;
      expect(first, isNotNull);

      // A new State binds first; the old one is disposed at the end of the
      // frame and must not take the new one's setup away.
      await tester.pumpWidget(card(2));
      expect(logger.setupProvider, isNotNull);
      expect(logger.setupProvider, isNot(equals(first)));

      // The last card going does clear it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(logger.setupProvider, isNull);
      // Not awaited: closing the stream needs the real zone's microtasks.
      unawaited(logger.dispose());
      await tester.pump();
    });
  });

  group('stopping the logger', () {
    _test('switching off disposes the logger and brings Save back',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester);
      expect(h.loggerClosed, isFalse);

      await _switchOn(tester); // now off
      await tester.pump();
      expect(h.settings.analyzerLogOnOk, isFalse);
      expect(h.loggerClosed, isTrue);
      expect(_key('analysis-ok-hint'), findsNothing);
      expect(_key('analysis-save'), findsOneWidget);

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(h.dao.addedFromBridge, isEmpty);
    });

    _test('disconnecting disposes the logger, reconnecting builds one',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      expect(h.loggersBuilt, 1);

      await h.connect(tester); // the button now says Disconnect
      await tester.pump();
      expect(h.loggerClosed, isTrue);
      expect(_key('analysis-save'), findsOneWidget);

      await h.connect(tester);
      expect(h.loggersBuilt, 2);
      expect(h.loggerClosed, isFalse);
      expect(_key('analysis-ok-hint'), findsOneWidget);

      // The card follows the new logger: its setup, its results.
      await _setUp(tester);
      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(h.dao.addedFromBridge, hasLength(1));
      expect(h.dao.addedFromBridge.single.$2.analysedBy, 'EdP');
      expect(_resultText(tester), 'Saved EAN32');
    });

    _test('leaving the screen disposes the logger', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      expect(h.loggerClosed, isFalse);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(h.loggerClosed, isTrue);
    });
  });

  group('keeping the Mac awake', () {
    _test('the wakelock is held while the logger runs and released after',
        (tester, h) async {
      await h.pump(tester);
      expect(h.awake, isEmpty);
      await _switchOn(tester);
      expect(h.awake, isEmpty, reason: 'no connection, no logger, no lock');
      await h.connect(tester);
      expect(h.awake, [true]);

      // Readings do not take it again.
      await h.feed(tester, 32.0, 0, seconds: 3);
      expect(h.awake, [true]);

      await _switchOn(tester); // off
      await tester.pump();
      expect(h.awake, [true, false]);
    });

    _test('disconnecting releases it, reconnecting takes it again',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await h.connect(tester); // Disconnect
      await tester.pump();
      expect(h.awake, [true, false]);
      await h.connect(tester);
      expect(h.awake, [true, false, true]);
    });

    _test('leaving the screen releases it', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(h.awake, [true, false]);
    });

    _test('a demo session never takes it', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await _pickSource(tester, 'Demo');
      await h.connect(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(h.awake, isEmpty);
    });
  });

  group('the screen when the SOLO is held', () {
    _test('no data hint if the SOLO never sent a line', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_key('analyzer-no-data-hint'), findsOneWidget);
      expect(find.text('Press OK on the SOLO to save. Keep this screen open.'),
          findsOneWidget);
    });

    _test('after an OK press the setup hint stays away, the switch says held',
        (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await h.feed(tester, 32.0, 0, seconds: 3);
      expect(_key('analyzer-no-data-hint'), findsNothing);

      // OK pressed: the stream stops and stays stopped.
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.noDataHint, isTrue);
      expect(_key('analyzer-no-data-hint'), findsNothing);
      expect(find.text('Held on the SOLO. Press OK there to measure again.'),
          findsOneWidget);

      // OK again: the lines come back and so does the usual text.
      h.solo!.emitLine(_line(32.0, 0));
      await tester.pump();
      expect(_key('analyzer-no-data-hint'), findsNothing);
      expect(find.text('Press OK on the SOLO to save. Keep this screen open.'),
          findsOneWidget);
    });

    _test('with Log on OK off the quiet SOLO gets no held text and no hint',
        (tester, h) async {
      await h.pump(tester);
      await h.connect(tester);
      await h.feed(tester, 32.0, 0, seconds: 3);
      await tester.pump(const Duration(seconds: 5));
      expect(_key('analyzer-no-data-hint'), findsNothing);
      expect(find.textContaining('Held on the SOLO'), findsNothing);
    });
  });

  group('analysed by', () {
    _test('analysed by is remembered', (tester, h) async {
      await h.pump(tester);
      expect(h.settings.analyzerAnalysedBy, isNull);

      await tester.enterText(_key('analysis-diver'), 'EdP');
      await _done(tester);
      expect(h.settings.analyzerAnalysedBy, 'EdP');

      // A new screen on the same settings starts from it.
      final again = _Harness();
      await again.pump(tester, useSettings: h.settings);
      expect(find.text('EdP'), findsOneWidget);
      await again.end(tester);

      // And a new start of the app.
      final reloaded = SettingsNotifier();
      await reloaded.load();
      expect(reloaded.analyzerAnalysedBy, 'EdP');
    });

    _test('clearing the name forgets it', (tester, h) async {
      await h.pump(tester);
      await tester.enterText(_key('analysis-diver'), 'EdP');
      await _done(tester);
      await tester.enterText(_key('analysis-diver'), '');
      await _done(tester);
      expect(h.settings.analyzerAnalysedBy, isNull);
      final reloaded = SettingsNotifier();
      await reloaded.load();
      expect(reloaded.analyzerAnalysedBy, isNull);
    });

    _test('typing a name writes the setting once, not per keystroke',
        (tester, h) async {
      await h.pump(tester);
      var writes = 0;
      h.settings.addListener(() => writes++);

      for (final typed in ['E', 'Ed', 'EdP']) {
        await tester.enterText(_key('analysis-diver'), typed);
        await tester.pump();
      }
      expect(writes, 0);
      expect(h.settings.analyzerAnalysedBy, isNull);

      await _done(tester);
      expect(writes, 1);
      expect(h.settings.analyzerAnalysedBy, 'EdP');

      // Done again with nothing changed writes nothing.
      await _done(tester);
      expect(writes, 1);
    });

    _test('leaving the field writes the name', (tester, h) async {
      await h.pump(tester);
      await tester.enterText(_key('analysis-diver'), 'EdP');
      await tester.pump();
      expect(h.settings.analyzerAnalysedBy, isNull);

      await tester.tap(_key('analysis-for'));
      await tester.pump();
      expect(h.settings.analyzerAnalysedBy, 'EdP');
    });

    _test('an OK press writes the name it saved', (tester, h) async {
      await h.pump(tester);
      await _switchOn(tester);
      await h.connect(tester);
      await _setUp(tester); // types the name, no Done
      expect(h.settings.analyzerAnalysedBy, isNull);

      await h.feed(tester, 32.0, 0);
      await h.pressOk(tester);
      expect(h.dao.addedFromBridge.single.$2.analysedBy, 'EdP');
      expect(h.settings.analyzerAnalysedBy, 'EdP');
    });

    _test('a manual Save writes the name', (tester, h) async {
      await h.pump(tester);
      await h.connect(tester);
      await h.feed(tester, 32.0, 0, seconds: 3);
      await tester.enterText(_key('analysis-diver'), 'EdP');
      await tester.pump();
      expect(h.settings.analyzerAnalysedBy, isNull);

      await tester.tap(_key('analysis-save'));
      await tester.pumpAndSettle();
      expect(h.settings.analyzerAnalysedBy, 'EdP');
      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();
    });

    _test('leaving the screen writes a name still being typed',
        (tester, h) async {
      await h.pump(tester);
      await tester.enterText(_key('analysis-diver'), 'EdP');
      await tester.pump();
      expect(h.settings.analyzerAnalysedBy, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(h.settings.analyzerAnalysedBy, 'EdP');
    });
  });

  group('For, in the manual flow too', () {
    _test('Save stores "For" and keeps it for the next fill',
        (tester, h) async {
      await h.pump(tester);
      await h.connect(tester); // Log on OK is off
      await h.feed(tester, 32.0, 0, seconds: 3);
      await tester.enterText(_key('analysis-for'), 'Anna');
      await tester.pump();

      await tester.tap(_key('analysis-save'));
      await tester.pumpAndSettle();
      // The reading isn't stable after 3 s.
      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();

      expect(h.dao.added.single.analysedFor, 'Anna');
      expect(find.text('Anna'), findsOneWidget);
    });
  });
}
