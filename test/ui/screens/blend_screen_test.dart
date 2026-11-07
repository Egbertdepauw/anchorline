import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/blend_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('target O2 field is editable and updates the notifier',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final notifier = BlendNotifier(settings: settings);
    expect(notifier.targetOxygenPercent, 18);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlendScreen(notifier: notifier, settings: settings),
      ),
    ));
    await tester.enterText(
      find.byKey(const ValueKey('tgt-o2')),
      '22',
    );
    await tester.pump();
    expect(notifier.targetOxygenPercent, 22,
        reason: 'typing into the target O₂ field must update the notifier');
  });

  testWidgets('target pressure field is editable and updates the notifier',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final notifier = BlendNotifier(settings: settings);
    expect(notifier.targetPressureBar, 230);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlendScreen(notifier: notifier, settings: settings),
      ),
    ));
    await tester.enterText(
      find.byKey(const ValueKey('tgt-pressure')),
      '210',
    );
    await tester.pump();
    expect(notifier.targetPressureBar, 210,
        reason: 'typing into the target pressure field must update the notifier');
  });

  Finder k(String key) => find.byKey(ValueKey(key));

  Future<BlendNotifier> pumpBlend(
    WidgetTester tester, {
    ThemeData? theme,
    void Function(BlendNotifier)? setup,
    double? width,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width ?? 400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = SettingsNotifier();
    await settings.load();
    final notifier = BlendNotifier(settings: settings);
    setup?.call(notifier);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width ?? 400, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: BlendScreen(notifier: notifier, settings: settings),
        ),
      ),
    ));
    await tester.pump();
    return notifier;
  }

  void tx2135(BlendNotifier n) {
    n.setTargetMix(21, 35);
    n.setCurrentPressure(50);
  }

  testWidgets('the band shows the target and one stat per step',
      (tester) async {
    await pumpBlend(tester, setup: tx2135);
    final band = k('blend-plan-band');
    expect(find.descendant(of: band, matching: find.text('Tx21/35')),
        findsOneWidget);
    expect(find.descendant(of: band, matching: find.text('to 230 bar')),
        findsOneWidget);
    expect(find.descendant(of: k('blend-step-0'), matching: find.text('1 · Helium')),
        findsOneWidget);
    expect(find.descendant(of: k('blend-step-1'), matching: find.text('2 · Oxygen')),
        findsOneWidget);
    expect(find.descendant(of: k('blend-step-2'), matching: find.text('3 · Air')),
        findsOneWidget);
    expect(k('blend-step-3'), findsNothing);
    expect(find.descendant(of: k('blend-step-0'), matching: find.textContaining('to ')),
        findsOneWidget);
  });

  testWidgets('a drain step comes first, numbered, in the warning colour',
      (tester) async {
    await pumpBlend(tester, setup: (n) {
      n.setCurrentPressure(100);
      n.setTargetPressure(200);
    });
    expect(find.text('1 · Drain'), findsOneWidget);
    expect(find.textContaining('Drain to'), findsOneWidget);
  });

  testWidgets('tapping a target chip fills the fields', (tester) async {
    final n = await pumpBlend(tester);
    await tester.tap(k('blend-target-chip-18-45'));
    await tester.pump();
    expect(n.targetOxygenPercent, 18);
    expect(n.targetHeliumPercent, 45);
    await tester.tap(k('blend-target-chip-32-0'));
    await tester.pump();
    expect(tester.widget<TextField>(find.descendant(of: k('tgt-o2'), matching: find.byType(TextField))).controller!.text, '32');
    expect(tester.widget<TextField>(find.descendant(of: k('tgt-he'), matching: find.byType(TextField))).controller!.text, '0');
  });

  testWidgets('typing a non-standard target deselects the chips',
      (tester) async {
    await pumpBlend(tester);
    bool selected(String key) => tester
        .widgetList<Semantics>(find.descendant(
            of: k(key), matching: find.byType(Semantics)))
        .any((s) => s.properties.selected == true);
    await tester.tap(k('blend-target-chip-18-45'));
    await tester.pump();
    expect(selected('blend-target-chip-18-45'), isTrue);
    await tester.enterText(
        find.descendant(of: k('tgt-o2'), matching: find.byType(TextField)),
        '19');
    await tester.pump();
    for (final key in [
      'blend-target-chip-21-35',
      'blend-target-chip-18-45',
      'blend-target-chip-15-55',
      'blend-target-chip-32-0',
      'blend-target-chip-50-0',
    ]) {
      expect(selected(key), isFalse, reason: key);
    }
  });

  testWidgets('Other… sets a custom top-off with its own chip',
      (tester) async {
    final n = await pumpBlend(tester);
    expect(k('blend-topoff-chip-28-0'), findsNothing);
    await tester.tap(k('blend-topoff-other'));
    await tester.pumpAndSettle();
    await tester.enterText(k('desired-mix-other-o2'), '28');
    await tester.tap(k('desired-mix-other-ok'));
    await tester.pumpAndSettle();
    expect(n.topoffOxygenPercent, 28);
    expect(n.topoffHeliumPercent, 0);
    expect(k('blend-topoff-chip-28-0'), findsOneWidget);
    await tester.tap(k('blend-topoff-chip-50-0'));
    await tester.pump();
    expect(n.topoffOxygenPercent, 50);
  });

  testWidgets('fill options start collapsed and open on tap', (tester) async {
    await pumpBlend(tester);
    expect(k('blend-fill-order'), findsNothing);
    expect(k('use-real-gas'), findsNothing);
    expect(
        find.descendant(
            of: k('blend-fill-options'),
            matching: find.text('He → O₂ → top-off · real gas · 18 °C')),
        findsOneWidget);
    await tester.tap(k('blend-fill-options'));
    await tester.pumpAndSettle();
    expect(k('blend-fill-order'), findsOneWidget);
    expect(k('use-real-gas'), findsOneWidget);
    expect(k('fill-temp'), findsOneWidget);
    expect(k('settled-temp'), findsOneWidget);
  });

  testWidgets('the cost opens the breakdown', (tester) async {
    await pumpBlend(tester, setup: tx2135);
    expect(k('blend-cost'), findsOneWidget);
    await tester.tap(k('blend-cost'));
    await tester.pumpAndSettle();
    expect(find.textContaining('He '), findsWidgets);
    expect(find.textContaining('air '), findsOneWidget);
  });

  testWidgets('an impossible blend shows the danger banner in place of the steps',
      (tester) async {
    final n = await pumpBlend(tester, setup: (n) {
      n.setCurrentPressure(100);
      n.setTargetMix(10, 0);
    });
    expect(n.result!.isOk, isFalse);
    expect(k('blend-step-0'), findsNothing);
    expect(find.text(n.result!.errorMessage ?? 'Impossible blend.'),
        findsOneWidget);
  });

  testWidgets('"Nothing to do" replaces the steps when the cylinder matches',
      (tester) async {
    await pumpBlend(tester, setup: (n) {
      n.setCurrentMix(18, 45);
      n.setCurrentPressure(230);
    });
    expect(k('blend-step-0'), findsNothing);
    expect(find.textContaining('Nothing to do'), findsOneWidget);
  });

  testWidgets('no overflow at 320 pt wide and text scale 1.3', (tester) async {
    await pumpBlend(tester, setup: (n) {
      n.setCurrentMix(32, 0);
      n.setCurrentPressure(100);
      n.setTargetMix(21, 35);
      n.setFillTempC(40);
      n.setSettledTempC(18);
    }, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.tap(k('blend-fill-options'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in every theme', (tester) async {
    for (final def in AppThemes.all) {
      await pumpBlend(tester, theme: def.themeData, setup: tx2135);
      await tester.tap(k('blend-fill-options'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: def.id);
    }
  });

  testWidgets('a chip tap refreshes a focused field', (tester) async {
    final n = await pumpBlend(tester);
    final o2 = find.descendant(of: k('tgt-o2'), matching: find.byType(TextField));
    final he = find.descendant(of: k('tgt-he'), matching: find.byType(TextField));
    await tester.enterText(o2, '30');
    await tester.pump();
    await tester.tap(k('blend-target-chip-15-55'));
    await tester.pump();
    expect(n.targetOxygenPercent, 15);
    expect(tester.widget<TextField>(o2).controller!.text, '15');
    expect(tester.widget<TextField>(he).controller!.text, '55');
  });

  testWidgets('the cost hit area is at least 44 pt high', (tester) async {
    await pumpBlend(tester, setup: tx2135);
    expect(tester.getSize(k('blend-cost')).height, greaterThanOrEqualTo(44));
  });
}
