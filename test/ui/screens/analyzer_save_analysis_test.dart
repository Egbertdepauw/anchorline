import 'dart:math';

import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsNotifier> loadSettings() async {
    final s = SettingsNotifier();
    await s.load();
    return s;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    FakeGasAnalysesDao? dao, {
    Size size = const Size(400, 3200),
    bool isDemo = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await loadSettings();
    await tester.pumpWidget(MaterialApp(
      home: AnalyzerScreen(
        settings: settings,
        analysesDao: dao,
        controller: fakeClockAnalyzerController(tester),
        transportOptions: [
          AnalyzerTransportOption(
            label: 'Demo',
            isDemo: isDemo,
            create: () => DemoAnalyzerTransport(
              targetO2: 18.2,
              targetHe: 45.1,
              random: Random(11),
            ),
          ),
        ],
      ),
    ));
    await tester.pump();
  }

  Future<void> seconds(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  }

  Future<void> disconnect(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  }

  Finder saveButton() => find.byKey(const ValueKey('analysis-save'));

  testWidgets('no DAO: no save card and no log action', (tester) async {
    await pumpScreen(tester, null);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    expect(find.byKey(const ValueKey('analyzer-open-log')), findsNothing);
  });

  testWidgets('save is disabled until a reading arrives', (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao());
    expect(find.byKey(const ValueKey('analysis-save-card')), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(saveButton()).onPressed, isNull);
  });

  testWidgets('stable reading saves with cylinder, diver, pressure, notes',
      (tester) async {
    final dao = FakeGasAnalysesDao(cylinders: const [
      CylinderChoice(id: 'c1', label: 'S80 left'),
      CylinderChoice(id: 'c2', label: 'AL40 deco'),
    ]);
    await pumpScreen(tester, dao);
    await connect(tester);
    await seconds(tester, 90);
    expect(find.text('STABLE'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-unstable-hint')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('analysis-cylinder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AL40 deco').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('analysis-diver')), 'Egbert');
    await tester.enterText(
        find.byKey(const ValueKey('analysis-pressure')), '210,5');
    await tester.enterText(
        find.byKey(const ValueKey('analysis-notes')), 'Topped up');
    await disconnect(tester); // freeze the reading
    await tester.tap(saveButton());
    await tester.pump();

    expect(dao.added, hasLength(1));
    final a = dao.added.single;
    expect(a.cylinderId, 'c2');
    expect(a.analysedBy, 'Egbert');
    expect(a.fillPressureBar, 210.5);
    expect(a.notes, 'Topped up');
    expect(a.o2Percent, 18.2);
    expect(a.hePercent, 45.1);
    expect(a.stable, isTrue);
    expect(a.tempC, 21.4);
    expect(a.modPpo2s, isNotEmpty);
    expect(find.text('Saved Tx18/45 to the analysis log.'), findsOneWidget);
    // Per-fill fields clear, cylinder + diver stay for the next fill.
    expect(find.text('Topped up'), findsNothing);
    expect(find.text('Egbert'), findsOneWidget);
  });

  testWidgets('unstable reading warns; cancel skips, save anyway saves',
      (tester) async {
    final dao = FakeGasAnalysesDao();
    await pumpScreen(tester, dao);
    await connect(tester);
    await seconds(tester, 2);
    expect(find.text('SETTLING'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('analysis-unstable-hint')), findsOneWidget);
    await disconnect(tester);

    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.text('Reading not stable'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(dao.added, isEmpty);

    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analysis-save-anyway')));
    await tester.pumpAndSettle();
    expect(dao.added, hasLength(1));
    expect(dao.added.single.stable, isFalse);
    expect(dao.added.single.cylinderId, isNull);
    expect(find.textContaining('(not stable)'), findsOneWidget);
  });

  testWidgets('app-bar action opens the analysis log', (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao());
    await tester.tap(find.byKey(const ValueKey('analyzer-open-log')));
    await tester.pumpAndSettle();
    expect(find.byType(GasAnalysisLogScreen), findsOneWidget);
    expect(find.textContaining('No analyses saved yet'), findsOneWidget);
  });

  testWidgets('demo source: no save card, so demo readings never reach the log',
      (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao(), isDemo: true);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    await connect(tester);
    await seconds(tester, 5);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    await disconnect(tester);
  });

  testWidgets('wide layout also shows the save card', (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao(),
        size: const Size(1200, 1600));
    expect(find.byKey(const ValueKey('analysis-save-card')), findsOneWidget);
  });
}
