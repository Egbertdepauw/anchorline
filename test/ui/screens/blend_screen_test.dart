import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/blend_screen.dart';
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
      home: BlendScreen(notifier: notifier, settings: settings),
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
      home: BlendScreen(notifier: notifier, settings: settings),
    ));
    await tester.enterText(
      find.byKey(const ValueKey('tgt-pressure')),
      '210',
    );
    await tester.pump();
    expect(notifier.targetPressureBar, 210,
        reason: 'typing into the target pressure field must update the notifier');
  });

  testWidgets('labelled "Analyze gas" button opens the gas analyzer',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final notifier = BlendNotifier(settings: settings);
    await tester.pumpWidget(MaterialApp(
      home: BlendScreen(notifier: notifier, settings: settings),
    ));
    expect(find.text('Analyze gas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blend-open-analyzer')));
    await tester.pumpAndSettle();
    expect(find.text('Gas analyzer'), findsOneWidget);
  });
}
