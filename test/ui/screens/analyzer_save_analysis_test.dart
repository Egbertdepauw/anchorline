import 'dart:math';

import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
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
    List<AnalyzerTransportOption>? options,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await loadSettings();
    final session = AnalyzerSession(
      settings: settings,
      analysesDao: dao,
      controller: fakeClockAnalyzerController(tester),
      transportOptions: options ?? [
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
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyzerScreen(settings: settings, session: session),
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
    await tester.tap(find.byKey(const ValueKey('analyzer-disconnect')));
    await tester.pump();
  }

  Finder saveButton() => find.byKey(const ValueKey('analysis-save'));

  testWidgets('no DAO: no save card', (tester) async {
    await pumpScreen(tester, null);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
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

  testWidgets('a mistyped fill pressure says so and blocks Save',
      (tester) async {
    final dao = FakeGasAnalysesDao();
    await pumpScreen(tester, dao);
    await connect(tester);
    await seconds(tester, 90);
    await disconnect(tester); // freeze the reading
    expect(find.text('Enter a pressure in bar'), findsNothing);
    expect(tester.widget<ButtonStyleButton>(saveButton()).onPressed, isNotNull);

    await tester.enterText(
        find.byKey(const ValueKey('analysis-pressure')), '21o');
    await tester.pump();
    expect(find.text('Enter a pressure in bar'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(saveButton()).onPressed, isNull,
        reason: 'not saved as "no pressure" without a word');
    expect(dao.added, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('analysis-pressure')), '210');
    await tester.pump();
    expect(find.text('Enter a pressure in bar'), findsNothing);
    await tester.tap(saveButton());
    await tester.pump();
    expect(dao.added.single.fillPressureBar, 210);
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

  testWidgets('demo source: no save card, so demo readings never reach the log',
      (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao(), isDemo: true);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    await connect(tester);
    await seconds(tester, 5);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    await disconnect(tester);
  });

  // Two sources with the same simulated signal; only the flag differs.
  List<AnalyzerTransportOption> demoAndBench() => [
        for (final demo in [true, false])
          AnalyzerTransportOption(
            label: demo ? 'Demo' : 'Bench',
            isDemo: demo,
            create: () => DemoAnalyzerTransport(
              targetO2: 18.2,
              targetHe: 45.1,
              random: Random(11),
            ),
          ),
      ];

  Future<void> pickSource(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('analyzer-transport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a frozen demo reading stays unsaveable after switching source',
      (tester) async {
    final dao = FakeGasAnalysesDao();
    await pumpScreen(tester, dao, options: demoAndBench());
    await connect(tester);
    await seconds(tester, 90);
    await disconnect(tester); // the demo reading stays on screen
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);

    await pickSource(tester, 'Bench');
    expect(find.byKey(const ValueKey('analysis-save-card')), findsNothing);
    expect(dao.added, isEmpty);
  });

  testWidgets('a frozen real reading stays saveable after switching to Demo',
      (tester) async {
    final dao = FakeGasAnalysesDao();
    await pumpScreen(tester, dao, options: demoAndBench());
    await pickSource(tester, 'Bench');
    await connect(tester);
    await seconds(tester, 90);
    await disconnect(tester);
    expect(find.byKey(const ValueKey('analysis-save-card')), findsOneWidget);

    await pickSource(tester, 'Demo');
    expect(find.byKey(const ValueKey('analysis-save-card')), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(saveButton()).onPressed, isNotNull);
    await tester.tap(saveButton());
    await tester.pump();
    expect(dao.added, hasLength(1));
    expect(dao.added.single.o2Percent, 18.2);
  });

  testWidgets('the MOD rows follow the desired mix picked on the save card',
      (tester) async {
    // 18.2 % at 1.6 is 77.9 m. With no desired mix that is a stop: 78 m
    // would be just over 1.6, so 75 m. Above the desired Tx18/45 it is the
    // exact depth rounded down, 77 m (#145).
    String mod16() => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('analyzer-mod-1.6')),
            matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan!.toPlainText())
        .join(' | ');

    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await loadSettings();
    final dao = FakeGasAnalysesDao();
    final session = AnalyzerSession(
      settings: settings,
      analysesDao: dao,
      controller: fakeClockAnalyzerController(tester),
      transportOptions: [
        AnalyzerTransportOption(
          label: 'Bench',
          create: () => DemoAnalyzerTransport(
            targetO2: 18.2,
            targetHe: 45.1,
            random: Random(11),
          ),
        ),
      ],
    );
    addTearDown(session.dispose);
    final blend = BlendNotifier(settings: settings)
      ..setTargetMix(18, 45)
      ..setTargetPressure(200);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyzerScreen(
            settings: settings, session: session, blend: blend),
      ),
    ));
    await tester.pump();
    await connect(tester);
    await seconds(tester, 90);
    expect(mod16(), contains('75 m'));

    await tester.tap(find.byKey(const ValueKey('desired-mix-18-45')));
    await tester.pump();
    expect(mod16(), contains('77 m'));

    // Saving clears the desired mix for the next cylinder, and the rows
    // go back to the stop rule.
    await disconnect(tester);
    await tester.tap(saveButton());
    await tester.pump();
    expect(mod16(), contains('75 m'));
  });

  testWidgets('wide layout also shows the save card', (tester) async {
    await pumpScreen(tester, FakeGasAnalysesDao(),
        size: const Size(1200, 1600));
    expect(find.byKey(const ValueKey('analysis-save-card')), findsOneWidget);
  });
}
