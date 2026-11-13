// The Analyse tab's "Save analysis" section and its pinned action bar: the
// defaults of spec §4.2, the nearest standard mix of §4.3, the role rule,
// and the layout of §4.1 items 6–7 on a real phone size.
import 'dart:async';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/screens/gas_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/analysis_action_bar.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A transport the test drives line by line (synchronous delivery).
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
  String get name => 'USB';
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

/// A Blend notifier that counts the marks of its target as used.
class _CountingBlend extends BlendNotifier {
  _CountingBlend({required super.settings});

  int marks = 0;

  @override
  Future<void> markRecentTargetUsed() {
    marks++;
    return super.markRecentTargetUsed();
  }
}

/// A log whose saves fail while [fail] is set.
class _FlakyDao extends FakeGasAnalysesDao {
  _FlakyDao({super.cylinders});

  bool fail = false;

  @override
  Future<String> add(NewGasAnalysis a) async {
    if (fail) throw Exception('disk full');
    return super.add(a);
  }
}

const _dil =
    CylinderChoice(id: 'c-dil', label: 'Dil 3L', role: CylinderRole.diluent);
const _s80 = CylinderChoice(id: 'c-s80', label: 'S80 left');

/// An analysis already in the log, with the desired mix [o2]/[he].
GasAnalysis _logged(String id, DateTime at, int o2, int he) => GasAnalysis(
      id: id,
      analysedAt: at,
      o2Percent: o2.toDouble(),
      hePercent: he.toDouble(),
      stable: true,
      targetO2Percent: o2,
      targetHePercent: he,
    );

/// The real Gas destination on a phone: the app theme, a 59 pt top inset, a
/// 34 pt home area and the shell's 56 pt bottom nav around it.
class _Rig {
  _Rig({FakeGasAnalysesDao? dao, this.printer = true, this.printerSetUp = true})
      : dao = dao ?? FakeGasAnalysesDao(cylinders: const [_dil, _s80]);

  final FakeGasAnalysesDao dao;

  /// Label printing is wired in; [printerSetUp] says a printer is saved.
  final bool printer;
  final bool printerSetUp;

  late SettingsNotifier settings;
  late _CountingBlend blend;
  late AnalyzerSession session;
  late AnalyzerController controller;
  _FakeSolo? solo;
  final fakePrinter = FakeLabelPrinter();

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(393, 852),
    double textScale = 1,
    Map<String, Object> prefs = const {},
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = SettingsNotifier();
    await settings.load();
    blend = _CountingBlend(settings: settings);
    final printing = printer
        ? LabelPrintService(
            render: (label) async => LabelBitmap.blank(384, 240),
            printerFor: (_) => fakePrinter,
            scanner: FakeLabelPrinterScanner(),
            printerId: () => printerSetUp ? 'dev-1' : null,
            use14ForDeeperMixes: () => false,
          )
        : null;
    session = AnalyzerSession(
      settings: settings,
      analysesDao: dao,
      labelPrinting: printing,
      blend: blend,
      controller: controller = AnalyzerController(elapsed: fakeElapsed(tester)),
      keepAwake: (_) async {},
      transportOptions: [
        AnalyzerTransportOption(
            label: 'USB', create: () => solo = _FakeSolo()),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppThemes.byId(null).themeData,
      builder: (context, child) {
        const insets = EdgeInsets.only(top: 59, bottom: 34);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: insets,
            viewPadding: insets,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: GasScreen(
          blend: blend,
          settings: settings,
          session: session,
          analysesDao: dao,
          labelPrinting: printing,
          onHome: () {},
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 2,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Dives'),
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Plan'),
            BottomNavigationBarItem(
                icon: Icon(Icons.science_outlined), label: 'Gas'),
            BottomNavigationBarItem(
                icon: Icon(Icons.bluetooth), label: 'Import'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(_key('gas-tab-analyse'));
    await tester.pumpAndSettle();
  }

  /// Leaves the screen and stops the controller's timers.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    controller.dispose();
  }

  Future<void> connect(WidgetTester tester) async {
    await session.connectSelected(tester.element(find.byType(GasScreen)));
    await tester.pump();
  }

  Future<void> disconnect(WidgetTester tester) async {
    await session.disconnect();
    await tester.pump();
  }

  /// [seconds] of [o2]/[he], two lines a second; 25 s ends STABLE.
  Future<void> feed(WidgetTester tester, double o2, double he,
      {int seconds = 25}) async {
    for (var i = 0; i < seconds * 2; i++) {
      solo!.emitLine(_line(o2, he));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  /// Connects and settles on a stable [o2]/[he].
  Future<void> stable(WidgetTester tester, double o2, double he) async {
    await connect(tester);
    await feed(tester, o2, he);
    expect(find.text('STABLE'), findsOneWidget);
  }
}

/// A widget test on a [_Rig] that is ended properly afterwards.
void _test(
  String description,
  Future<void> Function(WidgetTester tester, _Rig rig) body, {
  FakeGasAnalysesDao? dao,
  bool printer = true,
  bool printerSetUp = true,
}) {
  testWidgets(description, (tester) async {
    final rig = _Rig(dao: dao, printer: printer, printerSetUp: printerSetUp);
    try {
      await body(tester, rig);
    } finally {
      await rig.end(tester);
    }
  });
}

/// Taps [f], first scrolling the tab to it if it is out of view. Not with
/// `ensureVisible`: that also scrolls the TabBarView sideways, and a target
/// far enough right pages it over to the Log tab.
Future<void> _tap(WidgetTester tester, Finder f) async {
  final scroll = _key('analyzer-scroll');
  if (find.descendant(of: scroll, matching: f).evaluate().isNotEmpty) {
    final view = tester.getRect(scroll);
    final at = tester.getRect(f);
    if (at.top < view.top || at.bottom > view.bottom) {
      await tester.dragUntilVisible(f, scroll, const Offset(0, -60));
      await tester.pumpAndSettle();
    }
  }
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Taps the manual Save and lets the save run (no dialog for a stable
/// reading).
Future<void> _save(WidgetTester tester) => _tap(tester, _key('analysis-save'));

Future<void> _pickCylinder(WidgetTester tester, String label) async {
  await _tap(tester, _key('analysis-cylinder'));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _verdict(WidgetTester tester) =>
    tester.widget<Text>(_key('analysis-verdict')).data!;

Set<GasRole> _role(WidgetTester tester) => tester
    .widget<SegmentedButton<GasRole>>(_key('analysis-gas-role'))
    .selected;

/// The mix chips that are selected, by key.
List<String> _picked(WidgetTester tester) => [
      for (final e in find.byType(ChoiceChip).evaluate())
        if ((e.widget as ChoiceChip).selected)
          ((e.widget as ChoiceChip).key! as ValueKey<String>).value,
    ];

/// The labels of the mix chips, "Other…" included, in order.
List<String?> _chipLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(DesiredMixPicker),
      matching: find.byType(Text),
    ))
    .map((t) => t.data)
    .toList();

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The app's own fonts, so text is measured as on a device: the test font
  // is far wider, and its wrapping would make the height check meaningless.
  setUpAll(() async {
    for (final (family, file) in [
      ('Inter', 'fonts/Inter-VariableFont.ttf'),
      ('JetBrainsMono', 'fonts/JetBrainsMono-VariableFont.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(file))).load();
    }
  });

  group('the nearest standard mix', () {
    _test('a 20.4/33.5 reading preselects Tx21/35 with the standard suffix',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);

      expect(find.text('Matches Tx21/35, the nearest standard mix'),
          findsOneWidget);
      expect(_verdict(tester), 'Matches Tx21/35, the nearest standard mix');
      expect(_picked(tester), ['desired-mix-21-35']);
    });

    _test('49.2 picks EAN50; 19.1/43 picks Tx18/45, in orange',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 49.2, 0);
      expect(_verdict(tester), 'Matches EAN50, the nearest standard mix');
      expect(_picked(tester), ['desired-mix-50-0']);

      // The automatic pick follows the live reading.
      await rig.feed(tester, 19.1, 43.0);
      expect(_verdict(tester), 'O2 1.1 off Tx18/45, the nearest standard mix');
      expect(_picked(tester), ['desired-mix-18-45']);
    });

    _test('a reading within orange of no standard mix picks nothing',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 23.0, 30.0);
      expect(_picked(tester), isEmpty);
      expect(_key('analysis-verdict'), findsNothing);
    });

    _test('the Blend target beats the standard mix and says so',
        (tester, rig) async {
      await rig.pump(tester);
      // 22/33 and 21/35 both grade match against 21.6/33.6; the target wins.
      rig.blend
        ..setTargetMix(22, 33)
        ..setTargetPressure(200);
      await rig.stable(tester, 21.6, 33.6);
      expect(_verdict(tester), 'Matches Tx22/33, the Blend target');
      expect(_picked(tester), ['desired-mix-22-33']);
    });

    _test('a diver pick has no suffix and holds over reading changes',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      await _tap(tester, _key('desired-mix-other'));
      await tester.enterText(_key('desired-mix-other-o2'), '21');
      await tester.enterText(_key('desired-mix-other-he'), '33');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();
      expect(_verdict(tester), 'Matches Tx21/33');

      await rig.feed(tester, 49.2, 0, seconds: 3);
      expect(_picked(tester), ['desired-mix-21-33']);
      expect(_verdict(tester), contains('off Tx21/33'));
    });

    _test('tapping the selected chip clears it until the next Save',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      await _tap(tester, _key('desired-mix-21-35'));
      expect(_picked(tester), isEmpty);
      expect(_key('analysis-verdict'), findsNothing);

      // Still the diver's "no mix" on a new reading.
      await rig.feed(tester, 20.6, 33.8);
      expect(_picked(tester), isEmpty);

      await _save(tester);
      expect(rig.dao.added.single.desiredMix, isNull);
      // A manual save makes the pick automatic again.
      expect(_picked(tester), ['desired-mix-21-35']);
    });

    _test('at most three mix chips plus Other…', (tester, rig) async {
      await rig.pump(tester);
      rig.blend
        ..setTargetMix(21, 35)
        ..setTargetPressure(200);
      await rig.stable(tester, 49.2, 0);
      // The pick, the Blend target, then the log; Tx21/35 only once.
      expect(_chipLabels(tester), ['EAN50', 'Tx21/35', 'Tx18/45', 'Other…']);
      expect(_picked(tester), ['desired-mix-50-0']);
    },
        dao: FakeGasAnalysesDao(analyses: [
          _logged('l1', DateTime(2026, 11, 5), 21, 35),
          _logged('l2', DateTime(2026, 11, 4), 18, 45),
          _logged('l3', DateTime(2026, 11, 3), 32, 0),
          _logged('l4', DateTime(2026, 11, 2), 15, 55),
        ]));
  });

  group('the role', () {
    _test('the role is Diluent for Tx21/35 and Bailout for EAN50',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      expect(_role(tester), {GasRole.diluent});

      await rig.feed(tester, 49.2, 0);
      expect(_picked(tester), ['desired-mix-50-0']);
      expect(_role(tester), {GasRole.bailout});

      await _save(tester);
      expect(rig.dao.added.single.gasRole, GasRole.bailout);
      expect(rig.dao.added.single.desiredMix, const DesiredMix(50, 0));
    });

    _test('with no desired mix the role follows the reading: EAN40',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 40.0, 0);
      expect(_picked(tester), isEmpty);
      expect(_role(tester), {GasRole.bailout});
    });

    _test('a cylinder\'s role wins over the mix; a tapped role over both',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(393, 1400));
      await rig.stable(tester, 49.2, 0);
      expect(_role(tester), {GasRole.bailout});

      await _pickCylinder(tester, 'Dil 3L');
      expect(_role(tester), {GasRole.diluent});

      await _tap(tester, find.text('Bailout'));
      expect(_role(tester), {GasRole.bailout});
    });

    _test('a tapped role survives a reading change and resets after Save',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      await _tap(tester, find.text('Bailout'));
      expect(_role(tester), {GasRole.bailout});

      await rig.feed(tester, 18.2, 45.1);
      expect(_picked(tester), ['desired-mix-18-45']);
      expect(_role(tester), {GasRole.bailout});

      await _save(tester);
      expect(rig.dao.added.single.gasRole, GasRole.bailout);
      expect(_role(tester), {GasRole.diluent},
          reason: 'back to the rule for Tx18/45');
    });
  });

  group('the other defaults', () {
    _test('fill pressure starts at the setting and returns to it after Save',
        (tester, rig) async {
      await rig.pump(tester);
      expect(_fieldText(tester, 'analysis-pressure'), '230');
      await rig.stable(tester, 20.4, 33.5);

      await tester.enterText(_key('analysis-pressure'), '200');
      await tester.pump();
      await _save(tester);
      expect(rig.dao.added.single.fillPressureBar, 200);
      expect(_fieldText(tester, 'analysis-pressure'), '230');
    });

    _test('a fill pressure start of 232.5 is shown as typed',
        (tester, rig) async {
      await rig.pump(tester,
          prefs: {'analyzer_fill_pressure_start_bar': 232.5});
      expect(_fieldText(tester, 'analysis-pressure'), '232.5');
    });

    _test('Analysed by starts from Your initials and is not written back',
        (tester, rig) async {
      await rig.pump(tester, prefs: {'your_initials': 'EdP'});
      expect(_fieldText(tester, 'analysis-diver'), 'EdP');
      await rig.stable(tester, 20.4, 33.5);
      expect(_fieldText(tester, 'analysis-diver'), 'EdP');

      await tester.enterText(_key('analysis-diver'), 'JS');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await _save(tester);
      expect(rig.dao.added.single.analysedBy, 'JS');
      expect(rig.settings.yourInitials, 'EdP');
      // Someone else analysing holds for the session.
      expect(_fieldText(tester, 'analysis-diver'), 'JS');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final reloaded = SettingsNotifier();
      await reloaded.load();
      expect(reloaded.yourInitials, 'EdP');
    });

    _test('a typed name holds until Disconnect; the next connect starts over',
        (tester, rig) async {
      await rig.pump(tester, prefs: {'your_initials': 'EdP'});
      await rig.connect(tester);
      await tester.enterText(_key('analysis-diver'), 'JS');
      await rig.feed(tester, 20.4, 33.5, seconds: 2);
      expect(_fieldText(tester, 'analysis-diver'), 'JS');

      await rig.disconnect(tester);
      await rig.connect(tester);
      expect(_fieldText(tester, 'analysis-diver'), 'EdP');
    });

    _test('the cylinder stays after a manual save', (tester, rig) async {
      await rig.pump(tester, size: const Size(393, 1400));
      await rig.stable(tester, 20.4, 33.5);
      await _pickCylinder(tester, 'S80 left');
      await _save(tester);
      expect(rig.dao.added.single.cylinderId, 'c-s80');
      expect(
        tester.widget<DropdownButton<String?>>(_key('analysis-cylinder')).value,
        'c-s80',
      );

      await _save(tester);
      expect(rig.dao.added.last.cylinderId, 'c-s80');
    });

    _test('a note opens with + Add a note and is cleared after Save',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(393, 1400));
      await rig.stable(tester, 20.4, 33.5);
      expect(_key('analysis-notes'), findsNothing);
      expect(find.text('+ Add a note'), findsOneWidget);

      await _tap(tester, _key('analysis-add-note'));
      expect(_key('analysis-add-note'), findsNothing);
      await tester.enterText(_key('analysis-notes'), 'Topped up');
      await tester.pump();
      await _tap(tester, _key('copies-inc'));
      expect(tester.widget<Text>(_key('copies-value')).data, '2');

      await _save(tester);
      expect(rig.dao.added.single.notes, 'Topped up');
      expect(_key('analysis-notes'), findsNothing);
      expect(_key('analysis-add-note'), findsOneWidget);
      expect(tester.widget<Text>(_key('copies-value')).data, '1');
    });
  });

  group('saving', () {
    _test('a reading that changes during the unstable dialog saves the '
        'snapshot pick', (tester, rig) async {
      await rig.pump(tester);
      await rig.connect(tester);
      await rig.feed(tester, 19.1, 43.0, seconds: 3);
      expect(find.text('SETTLING'), findsOneWidget);
      expect(_picked(tester), ['desired-mix-18-45']);

      await tester.tap(_key('analysis-save'));
      await tester.pumpAndSettle();
      expect(find.text('Reading not stable'), findsOneWidget);

      // Another cylinder goes on while the dialog is open: nothing is
      // within orange of 23/30, so the live pick is gone.
      await rig.feed(tester, 23.0, 30.0, seconds: 3);
      expect(_picked(tester), isEmpty);

      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();
      final a = rig.dao.added.single;
      expect(a.o2Percent, 19.1);
      expect(a.desiredMix, const DesiredMix(18, 45));
      expect(a.gasRole, GasRole.diluent);
    });

    _test('a completed save of the Blend target marks it used',
        (tester, rig) async {
      await rig.pump(tester);
      rig.blend
        ..setTargetMix(21, 35)
        ..setTargetPressure(200);
      await rig.stable(tester, 20.6, 33.8);
      expect(_verdict(tester), 'Matches Tx21/35, the Blend target');

      await _save(tester);
      expect(rig.dao.added.single.desiredMix, const DesiredMix(21, 35));
      expect(rig.blend.marks, 1);
      expect(rig.blend.unusedRecentTarget(), isNull);
      // One blend is one cylinder: the next pick is the standard mix.
      expect(_verdict(tester), 'Matches Tx21/35, the nearest standard mix');
    });

    _test('a failed save does not use the Blend target up',
        (tester, rig) async {
      final dao = rig.dao as _FlakyDao;
      dao.fail = true;
      await rig.pump(tester);
      rig.blend
        ..setTargetMix(21, 35)
        ..setTargetPressure(200);
      await rig.stable(tester, 20.6, 33.8);
      await _save(tester);
      expect(find.text('Save failed: Exception: disk full'), findsOneWidget);
      expect(rig.blend.marks, 0);
      expect(_verdict(tester), 'Matches Tx21/35, the Blend target');
    }, dao: _FlakyDao(cylinders: const [_dil, _s80]));

    _test('a save of another mix leaves the Blend target unused',
        (tester, rig) async {
      await rig.pump(tester);
      rig.blend
        ..setTargetMix(21, 35)
        ..setTargetPressure(200);
      await rig.stable(tester, 49.2, 0);
      await _save(tester);
      expect(rig.dao.added.single.desiredMix, const DesiredMix(50, 0));
      expect(rig.blend.marks, 0);
      expect(rig.blend.unusedRecentTarget(), const DesiredMix(21, 35));
    });
  });

  group('the action bar', () {
    _test('Save & print is the primary button when a printer is set up',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      final bar = _key('analysis-action-bar');
      expect(bar, findsOneWidget);
      expect(
          find.descendant(
              of: bar,
              matching: find.byWidgetPredicate((w) =>
                  w is FilledButton &&
                  w.key == const ValueKey('analysis-save-print'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: bar,
              matching: find.byWidgetPredicate((w) =>
                  w is OutlinedButton &&
                  w.key == const ValueKey('analysis-save'))),
          findsOneWidget);
      expect(find.descendant(of: bar, matching: _key('copies-inc')),
          findsOneWidget);
      expect(find.text('Save & print'), findsOneWidget);
      expect(_key('analysis-setup-printer'), findsNothing);
      // Buttons and the stepper are 44 pt targets.
      expect(tester.getSize(_key('analysis-save')).height,
          greaterThanOrEqualTo(44));
      expect(tester.getSize(_key('analysis-save-print')).height,
          greaterThanOrEqualTo(44));
      expect(tester.getSize(_key('copies-inc')).height,
          greaterThanOrEqualTo(44));
      expect(tester.getSize(_key('copies-dec')).width,
          greaterThanOrEqualTo(44));

      await _tap(tester, _key('analysis-save-print'));
      expect(rig.dao.added, hasLength(1));
      expect(rig.fakePrinter.printed, hasLength(1));
    });

    _test('without a printer Save is the only button and the link shows',
        (tester, rig) async {
      await rig.pump(tester);
      await rig.stable(tester, 20.4, 33.5);
      final bar = _key('analysis-action-bar');
      expect(_key('analysis-save-print'), findsNothing);
      expect(_key('copies-inc'), findsNothing);
      expect(
          find.descendant(
              of: bar,
              matching: find.byWidgetPredicate((w) =>
                  w is FilledButton &&
                  w.key == const ValueKey('analysis-save'))),
          findsOneWidget);
      // Full width, less the bar's side padding.
      expect(tester.getSize(_key('analysis-save')).width,
          closeTo(393 - 32, 1));
      // The link is in the section, not the bar.
      expect(
          find.descendant(
              of: _key('analysis-save-card'),
              matching: _key('analysis-setup-printer')),
          findsOneWidget);
      expect(find.text('Set up label printer'), findsOneWidget);
    }, printerSetUp: false);

    _test('no label printing at all: Save only, and no link',
        (tester, rig) async {
      await rig.pump(tester);
      expect(_key('analysis-save'), findsOneWidget);
      expect(_key('analysis-save-print'), findsNothing);
      expect(_key('analysis-setup-printer'), findsNothing);
    }, printer: false);

    _test('the bar is pinned under the scroll view, above the bottom nav',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(393, 600));
      await rig.stable(tester, 20.4, 33.5);
      final bar = tester.getRect(_key('analysis-action-bar'));
      final nav = tester.getRect(find.byType(BottomNavigationBar));
      expect(bar.bottom, nav.top);
      // Scrolling the tab leaves the bar where it is.
      await tester.drag(_key('analyzer-scroll'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(_key('analysis-action-bar')), bar);
    });
  });

  group('the layout', () {
    double maxScroll(WidgetTester tester) => tester
        .state<ScrollableState>(find
            .descendant(
                of: _key('analyzer-scroll'), matching: find.byType(Scrollable))
            .first)
        .position
        .maxScrollExtent;

    _test('Analyse tab fits 393×852 with insets and the bottom nav (stable, '
        'printer set up)', (tester, rig) async {
      await rig.pump(tester, prefs: {'your_initials': 'EdP'});
      rig.blend
        ..setTargetMix(21, 35)
        ..setTargetPressure(200);
      await rig.stable(tester, 20.6, 33.8);
      expect(_key('analysis-verdict'), findsOneWidget);
      expect(_key('analysis-save-print'), findsOneWidget);
      expect(_key('analyzer-log-on-ok'), findsOneWidget);

      expect(maxScroll(tester), 0);
      expect(tester.getRect(_key('analysis-action-bar')).height, 64);
      // The sizes it takes: fields 40, chips and links at the 32 pt floor.
      expect(
          tester
              .getSize(find.ancestor(
                  of: _key('analysis-pressure'),
                  matching: find.byType(Container)).first)
              .height,
          40);
      expect(tester.getSize(_key('desired-mix-21-35')).height,
          greaterThanOrEqualTo(32));
      expect(tester.getSize(_key('analysis-add-note')).height,
          greaterThanOrEqualTo(32));
      expect(tester.getSize(_key('analyzer-log-on-ok')).height,
          greaterThanOrEqualTo(32));
      expect(tester.takeException(), isNull);
    });

    _test('and without a printer, with its set-up link', (tester, rig) async {
      await rig.pump(tester, prefs: {'your_initials': 'EdP'});
      await rig.stable(tester, 20.6, 33.8);
      expect(_key('analysis-setup-printer'), findsOneWidget);
      expect(maxScroll(tester), 0);
    }, printerSetUp: false);

    _test('no overflow at 320×568 and text scale 1.3 with the save section',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(320, 568), textScale: 1.3);
      await rig.connect(tester);
      await rig.feed(tester, 19.1, 43.0, seconds: 3);
      await _tap(tester, _key('analysis-add-note'));
      await tester.drag(_key('analyzer-scroll'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_key('analysis-unstable-hint'), findsOneWidget);
      expect(_key('analysis-action-bar'), findsOneWidget);
    });

    _test('no overflow at 320×568 and text scale 1.3 without a printer',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(320, 568), textScale: 1.3);
      await rig.stable(tester, 20.4, 33.5);
      expect(tester.takeException(), isNull);
      expect(_key('analysis-setup-printer'), findsOneWidget);
    }, printerSetUp: false);

    testWidgets('the section and the bar render in every theme',
        (tester) async {
      // Every other theme without a printer, for the link and the full-width
      // Save.
      for (final (i, def) in AppThemes.all.indexed) {
        final rig = _Rig(printerSetUp: i.isEven);
        try {
          await rig.pump(tester, theme: def.themeData);
          await rig.connect(tester);
          await rig.feed(tester, 19.1, 43.0, seconds: 3);
          await _tap(tester, _key('analysis-add-note'));
          expect(_key('analysis-verdict'), findsOneWidget, reason: def.id);
          expect(_key('analysis-action-bar'), findsOneWidget, reason: def.id);
          expect(tester.takeException(), isNull, reason: def.id);
        } finally {
          await rig.end(tester);
        }
      }
    });

    _test('the wide layout puts the bar at the bottom of the save column',
        (tester, rig) async {
      await rig.pump(tester, size: const Size(1200, 800));
      await rig.stable(tester, 20.4, 33.5);
      final bar = tester.getRect(_key('analysis-action-bar'));
      final section = tester.getRect(_key('analysis-save-card'));
      expect(bar.left, section.left);
      expect(bar.left, greaterThan(600));
      expect(bar.bottom, tester.getRect(find.byType(BottomNavigationBar)).top);
      expect(find.byType(AnalysisActionBar), findsOneWidget);
    });
  });
}
