import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/theme/active_theme_builder.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(SettingsNotifier settings, void Function(ThemePalette) onSeen) {
    return ActiveThemeBuilder(
      settings: settings,
      child: Builder(builder: (context) {
        onSeen(context.palette);
        return const SizedBox();
      }),
      builder: (context, theme, child) =>
          MaterialApp(theme: theme, home: child),
    );
  }

  testWidgets('starts in the stored theme', (tester) async {
    SharedPreferences.setMockInitialValues({'app_theme': 'ethereal'});
    final settings = SettingsNotifier();
    await settings.load();
    late ThemePalette seen;
    await tester.pumpWidget(app(settings, (p) => seen = p));
    expect(seen, same(AppThemes.byId('ethereal').palette));
  });

  testWidgets('switches when the setting changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsNotifier();
    await settings.load();
    late ThemePalette seen;
    await tester.pumpWidget(app(settings, (p) => seen = p));
    expect(seen, same(AppColors.wreck));

    await settings.setThemeId('catppuccin');
    await tester.pumpAndSettle();
    expect(seen.surfaceBg, AppThemes.byId('catppuccin').palette.surfaceBg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hands MaterialApp the registry ThemeData', (tester) async {
    SharedPreferences.setMockInitialValues({'app_theme': 'miasma'});
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(app(settings, (_) {}));
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme, same(AppThemes.byId('miasma').themeData));
  });
}
