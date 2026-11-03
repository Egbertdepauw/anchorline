import 'dart:math';

import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsNotifier> loadSettings() async {
    final s = SettingsNotifier();
    await s.load();
    return s;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    SettingsNotifier settings, {
    double targetO2 = 18.2,
    double targetHe = 45.1,
    Size size = const Size(400, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AnalyzerScreen(
        settings: settings,
        controller: fakeClockAnalyzerController(tester),
        transportOptions: [
          AnalyzerTransportOption(
            label: 'Demo',
            create: () => DemoAnalyzerTransport(
              targetO2: targetO2,
              targetHe: targetHe,
              random: Random(11),
            ),
          ),
        ],
      ),
    ));
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  String rowText(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan!.toPlainText())
      .join(' | ');

  Future<void> seconds(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('NO DATA before connecting, placeholders everywhere',
      (tester) async {
    await pumpScreen(tester, await loadSettings());
    expect(find.text('NO DATA'), findsOneWidget);
    expect(textOf(tester, 'analyzer-o2'), '--.-');
    expect(textOf(tester, 'analyzer-he'), '--.-');
    expect(textOf(tester, 'analyzer-mix'), '—');
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('demo: one-decimal readouts, SETTLING → STABLE, Tx18.2/45.1',
      (tester) async {
    await pumpScreen(tester, await loadSettings());
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
    expect(find.text('Connected · Demo'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);

    await seconds(tester, 1);
    expect(textOf(tester, 'analyzer-o2'), matches(RegExp(r'^\d+\.\d$')));
    expect(textOf(tester, 'analyzer-he'), matches(RegExp(r'^\d+\.\d$')));
    expect(find.text('SETTLING'), findsOneWidget);
    expect(textOf(tester, 'analyzer-mix'), 'Air');

    await seconds(tester, 89);
    expect(find.text('STABLE'), findsOneWidget);
    expect(textOf(tester, 'analyzer-o2'), '18.2');
    expect(textOf(tester, 'analyzer-he'), '45.1');
    expect(textOf(tester, 'analyzer-mix'), 'Tx18.2/45.1');
    expect(find.text('N₂ balance 36.7 %'), findsOneWidget);
    expect(find.byKey(const ValueKey('analyzer-no-data-hint')), findsNothing);

    // Normoxic trimix: breathable at the surface.
    expect(rowText(tester, 'analyzer-min-depth'), contains('surface'));
    // MOD rows follow the default ppO2 set; 1.1 is the CCR diluent row.
    expect(rowText(tester, 'analyzer-mod-1.1'), contains('CCR dil'));
    expect(rowText(tester, 'analyzer-mod-1.1'), contains('MOD @ ppO₂ 1.1'));
    expect(rowText(tester, 'analyzer-mod-1.4'), contains('MOD @ ppO₂ 1.4'));
    expect(rowText(tester, 'analyzer-mod-1.6'), contains('MOD @ ppO₂ 1.6'));
    expect(rowText(tester, 'analyzer-mod-1.4'), isNot(contains('CCR dil')));
    // (1.4 / 0.182 − 1) × 10 = 66.9 m: the nearest 3 m stop, 66, as the
    // cylinder label shows it (#145).
    expect(rowText(tester, 'analyzer-mod-1.4'), contains('66 m'));
    expect(rowText(tester, 'analyzer-temp'), contains('21.4 °C'));
    expect(rowText(tester, 'analyzer-baro'), contains('1013 hPa'));

    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // Last reading stays visible after disconnecting.
    expect(textOf(tester, 'analyzer-mix'), 'Tx18.2/45.1');
  });

  test('exactly one built-in transport option is the demo source', () {
    final demo =
        defaultAnalyzerTransportOptions().where((o) => o.isDemo).toList();
    expect(demo, hasLength(1));
    expect(demo.single.label, 'Demo');
  });

  testWidgets('hypoxic mix shows a minimum depth instead of surface',
      (tester) async {
    await pumpScreen(tester, await loadSettings(), targetO2: 10, targetHe: 70);
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await seconds(tester, 90);
    expect(textOf(tester, 'analyzer-mix'), 'Tx10.0/70.0');
    // (0.16 / 0.10 − 1) × 10 = 6 m
    expect(rowText(tester, 'analyzer-min-depth'), contains('6 m'));
    expect(rowText(tester, 'analyzer-min-depth'), isNot(contains('surface')));
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  });

  testWidgets('an exact whole-metre MOD is not floored down a metre',
      (tester) async {
    // (1.4 / 0.2 - 1) * 10 is 59.99999999999999 in doubles; the true MOD of
    // 20.0 % at 1.4 bar is exactly 60 m, as the label prints it.
    await pumpScreen(tester, await loadSettings(), targetO2: 20, targetHe: 0);
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await seconds(tester, 90);
    expect(textOf(tester, 'analyzer-o2'), '20.0');
    expect(rowText(tester, 'analyzer-mod-1.4'), contains('60 m'));
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  });

  testWidgets('END follows the endCountsOxygen setting', (tester) async {
    final settings = await loadSettings();
    await pumpScreen(tester, settings);
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await seconds(tester, 90);
    // MOD 1.4 = 66.92 m. Counting O2: (76.92 × 0.549) − 10 = 32 m.
    expect(rowText(tester, 'analyzer-end'), contains('32 m'));
    await settings.setEndCountsOxygen(false);
    await tester.pump();
    // N2 only: 76.92 × (0.367 / 0.79) − 10 = 26 m.
    expect(rowText(tester, 'analyzer-end'), contains('26 m'));
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  });

  testWidgets('MOD rows follow the ppO2 setting', (tester) async {
    final settings = await loadSettings();
    await settings.setAnalyzerModPpo2s([1.2, 1.3]);
    await pumpScreen(tester, settings);
    expect(find.byKey(const ValueKey('analyzer-mod-1.2')), findsOneWidget);
    expect(find.byKey(const ValueKey('analyzer-mod-1.3')), findsOneWidget);
    expect(find.byKey(const ValueKey('analyzer-mod-1.1')), findsNothing);
    expect(find.text('CCR dil', findRichText: true), findsNothing);
  });

  testWidgets('wide layout renders without overflow', (tester) async {
    await pumpScreen(tester, await loadSettings(),
        size: const Size(1200, 1000));
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await seconds(tester, 5);
    expect(tester.takeException(), isNull);
    expect(find.text('SETTLING'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analyzer-connect')));
    await tester.pump();
  });
}
