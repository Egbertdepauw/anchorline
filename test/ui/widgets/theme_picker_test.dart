import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/theme_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsNotifier> pump(WidgetTester tester,
      {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ThemePicker(notifier: settings)),
      ),
    ));
    return settings;
  }

  Finder checkIn(String id) => find.descendant(
      of: find.byKey(ValueKey('theme-$id')), matching: find.byIcon(Icons.check));

  testWidgets('lists every registered theme by name', (tester) async {
    await pump(tester);
    for (final t in AppThemes.all) {
      expect(find.byKey(ValueKey('theme-${t.id}')), findsOneWidget);
      expect(find.text(t.name), findsOneWidget);
    }
  });

  testWidgets('marks only the active theme', (tester) async {
    await pump(tester, prefs: {'app_theme': 'retro82'});
    expect(checkIn('retro82'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping a row selects that theme and moves the mark',
      (tester) async {
    final settings = await pump(tester);
    expect(checkIn('wreck'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-hackerman')));
    await tester.pumpAndSettle();

    expect(settings.themeId, 'hackerman');
    expect(checkIn('hackerman'), findsOneWidget);
    expect(checkIn('wreck'), findsNothing);
  });

  testWidgets('each row shows four swatches from its own palette',
      (tester) async {
    await pump(tester);
    final palette = AppThemes.byId('catppuccin').palette;
    final swatchColors = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const ValueKey('theme-catppuccin')),
            matching: find.byKey(const ValueKey('theme-swatch'))))
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toList();
    expect(swatchColors, [
      palette.surfaceBg,
      palette.surfaceCard,
      palette.textPrimary,
      palette.accentPrimary,
    ]);
  });
}
