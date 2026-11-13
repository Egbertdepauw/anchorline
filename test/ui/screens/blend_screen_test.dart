import 'dart:async';

import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/blend_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_open_blends_dao.dart';

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

  group('gas chip grid', () {
    double x(WidgetTester t, String key) => t.getTopLeft(k(key)).dx;
    double y(WidgetTester t, String key) => t.getTopLeft(k(key)).dy;

    testWidgets('three per row on an iPhone 15, lined up with the fields',
        (tester) async {
      await pumpBlend(tester, width: 393);
      final row1 = y(tester, 'blend-target-chip-21-35');
      expect(y(tester, 'blend-target-chip-18-45'), row1);
      expect(y(tester, 'blend-target-chip-15-55'), row1);
      expect(y(tester, 'blend-target-chip-32-0'), greaterThan(row1));
      expect(y(tester, 'blend-target-chip-50-0'),
          y(tester, 'blend-target-chip-32-0'));
      // The columns are the O₂ / He / Pressure columns under the chips.
      expect(x(tester, 'blend-target-chip-21-35'),
          moreOrLessEquals(x(tester, 'tgt-o2')));
      expect(x(tester, 'blend-target-chip-18-45'),
          moreOrLessEquals(x(tester, 'tgt-he')));
      expect(x(tester, 'blend-target-chip-15-55'),
          moreOrLessEquals(x(tester, 'tgt-pressure')));
      expect(x(tester, 'blend-target-chip-32-0'),
          moreOrLessEquals(x(tester, 'blend-target-chip-21-35')));
      expect(tester.getSize(k('blend-target-chip-21-35')).width,
          moreOrLessEquals(tester.getSize(k('tgt-o2')).width));

      final topoff = y(tester, 'blend-topoff-chip-21-0');
      expect(y(tester, 'blend-topoff-chip-32-0'), topoff);
      expect(y(tester, 'blend-topoff-chip-50-0'), topoff);
      expect(y(tester, 'blend-topoff-other'), greaterThan(topoff));
    });

    testWidgets('two per row on a 320 pt phone and with large text',
        (tester) async {
      for (final (width, scale) in [(320.0, 1.0), (393.0, 1.3)]) {
        await pumpBlend(tester, width: width, textScale: scale);
        final row1 = y(tester, 'blend-target-chip-21-35');
        expect(y(tester, 'blend-target-chip-18-45'), row1,
            reason: '$width pt at ×$scale');
        expect(y(tester, 'blend-target-chip-15-55'), greaterThan(row1),
            reason: '$width pt at ×$scale');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('more columns on a wide screen', (tester) async {
      await pumpBlend(tester, width: 700);
      final targets = y(tester, 'blend-target-chip-21-35');
      for (final key in [
        'blend-target-chip-18-45',
        'blend-target-chip-15-55',
        'blend-target-chip-32-0',
        'blend-target-chip-50-0',
      ]) {
        expect(y(tester, key), targets, reason: key);
      }
      final topoff = y(tester, 'blend-topoff-chip-21-0');
      for (final key in [
        'blend-topoff-chip-32-0',
        'blend-topoff-chip-50-0',
        'blend-topoff-other',
      ]) {
        expect(y(tester, key), topoff, reason: key);
      }
    });
  });

  group('open blends', () {
    final fixedNow = DateTime(2026, 11, 13, 12);

    Future<(BlendNotifier, FakeOpenBlendsDao, SettingsNotifier)> pumpOpen(
        WidgetTester tester,
        {void Function(BlendNotifier)? setup,
        bool withDao = true}) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = SettingsNotifier();
      await settings.load();
      final notifier = BlendNotifier(settings: settings);
      setup?.call(notifier);
      final dao = FakeOpenBlendsDao();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BlendScreen(
            notifier: notifier,
            settings: settings,
            openBlends: withDao ? dao : null,
            now: () => fixedNow,
          ),
        ),
      ));
      await tester.pump();
      return (notifier, dao, settings);
    }

    Future<void> leave(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('Blended saves the draft and shows it in the list',
        (tester) async {
      final (n, dao, settings) = await pumpOpen(tester);
      await settings.setYourInitials('EdP');
      await tester.tap(k('blend-save-open'));
      await tester.pump();
      await tester.pump();
      expect(dao.added, hasLength(1));
      expect(dao.added.single.target, const DesiredMix(18, 45));
      expect(dao.added.single.blendedBy, 'EdP');
      expect(dao.added.single.blendedAt, fixedNow);
      expect(find.text('Tx18/45 added to open blends'), findsOneWidget);
      expect(find.text('Not yet analysed (1)'), findsOneWidget);
      expect(find.text('just now'), findsOneWidget);
      expect(n.roleOverridden, isFalse);
      await leave(tester);
    });

    testWidgets(
        'role chip shows the guess with its reason and an override sticks '
        'for one blend', (tester) async {
      final (n, dao, _) = await pumpOpen(tester);
      final chip = find.descendant(
          of: k('blend-role-chip'),
          matching: find.text(
              '${n.roleGuess.role.label} (${n.roleGuess.reason})'));
      expect(chip, findsOneWidget);

      await tester.tap(k('blend-role-chip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deco').last);
      await tester.pumpAndSettle();
      expect(n.role, GasRole.deco);
      expect(find.descendant(of: k('blend-role-chip'), matching: find.text('Deco')),
          findsOneWidget);

      await tester.tap(k('blend-save-open'));
      await tester.pump();
      await tester.pump();
      expect(dao.added.single.role, GasRole.deco);
      expect(n.roleOverridden, isFalse);
      expect(chip, findsOneWidget);
      await leave(tester);
    });

    testWidgets('two quick taps add one blend', (tester) async {
      final (_, dao, _) = await pumpOpen(tester);
      final gate = Completer<void>();
      dao.addGate = gate.future;
      await tester.tap(k('blend-save-open'));
      await tester.pump();
      await tester.tap(k('blend-save-open'), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(dao.blends, hasLength(1));
      expect(dao.added, hasLength(1));
      await leave(tester);
    });

    testWidgets('a failing add shows the error and keeps the role override',
        (tester) async {
      final (n, dao, _) = await pumpOpen(tester);
      n.overrideRole(GasRole.deco);
      dao.addError = StateError('boom');
      await tester.tap(k('blend-save-open'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not save the open blend:'),
          findsOneWidget);
      expect(n.roleOverridden, isTrue);
      await leave(tester);
    });

    testWidgets('rebuilding does not open a new watch query', (tester) async {
      final (n, dao, _) = await pumpOpen(tester);
      final before = dao.watchOpenCalls;
      n.setTargetPressure(200);
      await tester.pump();
      n.setTargetMix(21, 35);
      await tester.pump();
      expect(dao.watchOpenCalls, before);
      await leave(tester);
    });

    testWidgets('the list sits after the inputs', (tester) async {
      final (_, dao, _) = await pumpOpen(tester);
      await tester.tap(k('blend-save-open'));
      await tester.pump();
      await tester.pump();
      expect(
          tester.getTopLeft(find.textContaining('Not yet analysed')).dy,
          greaterThan(tester.getTopLeft(k('blend-fill-options')).dy));
      expect(dao.added, hasLength(1));
      await leave(tester);
    });

    testWidgets('without a DAO the button and list hide but the chip stays',
        (tester) async {
      await pumpOpen(tester, withDao: false);
      expect(k('blend-save-open'), findsNothing);
      expect(find.textContaining('Not yet analysed'), findsNothing);
      expect(k('blend-role-chip'), findsOneWidget);
      await leave(tester);
    });
  });
}
