import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/plan_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows resolved one-line summary collapsed by default',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    DivePlanSettings? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSettingsPanel(
          settings: settings,
          overrides: const DivePlanSettings(),
          onChange: (s) => captured = s,
        ),
      ),
    ));
    expect(find.text('30/85'), findsOneWidget,
        reason: 'shows resolved GF in the summary');
    expect(find.text('1.3 / 0.7 / 1.4'), findsOneWidget,
        reason: 'shows resolved bottom/ascent/deco setpoints');
    captured; // not asserted; just keep the closure alive.
  });

  testWidgets('tapping the summary expands the override controls',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSettingsPanel(
          settings: settings,
          overrides: const DivePlanSettings(),
          onChange: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('plan-settings-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('GF Low'), findsOneWidget);
    expect(find.text('GF High'), findsOneWidget);
    expect(find.text('Last stop'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Algorithm'), findsOneWidget);
  });

  testWidgets('selecting VPM-B reveals a Conservatism control and hides GF',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    DivePlanSettings overrides = const DivePlanSettings();
    await tester.pumpWidget(
      StatefulBuilder(builder: (context, setState) {
        return MaterialApp(
          home: Scaffold(
            body: PlanSettingsPanel(
              settings: settings,
              overrides: overrides,
              onChange: (s) => setState(() => overrides = s),
            ),
          ),
        );
      }),
    );
    await tester.tap(find.byKey(const ValueKey('plan-settings-toggle')));
    await tester.pumpAndSettle();
    // Default = ZHL → GF rows visible, no Conservatism.
    expect(find.text('Conservatism'), findsNothing);
    expect(find.byKey(const ValueKey('gf-low')), findsOneWidget);
    // Tap the VPM-B segment.
    await tester.tap(find.text('VPM-B'));
    await tester.pumpAndSettle();
    expect(overrides.useVpmb, isTrue);
    expect(find.text('Conservatism'), findsOneWidget);
    expect(find.byKey(const ValueKey('vpmb-conservatism')), findsOneWidget);
    expect(find.byKey(const ValueKey('gf-low')), findsNothing);
  });

  testWidgets('switching to OC hides the setpoint rows', (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    DivePlanMode mode = DivePlanMode.cc;
    await tester.pumpWidget(
      StatefulBuilder(builder: (context, setState) {
        return MaterialApp(
          home: Scaffold(
            body: PlanSettingsPanel(
              settings: settings,
              overrides: const DivePlanSettings(),
              onChange: (_) {},
              mode: mode,
              onModeChange: (m) => setState(() => mode = m),
            ),
          ),
        );
      }),
    );
    await tester.tap(find.byKey(const ValueKey('plan-settings-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Bottom SP'), findsOneWidget);
    await tester.tap(find.text('OC'));
    await tester.pumpAndSettle();
    expect(mode, DivePlanMode.oc);
    expect(find.text('Bottom SP'), findsNothing);
    expect(find.text('Deco SP'), findsNothing);
  });
}
