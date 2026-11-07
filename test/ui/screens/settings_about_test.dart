import 'package:ccrlogger/ui/screens/settings/about_tab.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _k(String key) => find.byKey(ValueKey(key));

Future<void> _pump(WidgetTester t, AboutTab tab, {ThemeData? theme}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: theme ?? AppThemes.byId(null).themeData,
    home: Scaffold(body: tab),
  ));
  await t.pump();
}

void main() {
  testWidgets('a release build shows version, build and date', (t) async {
    await _pump(
        t,
        const AboutTab(
            version: '1.1.0',
            build: '43',
            buildDate: '2026-11-06',
            channel: 'release'));
    expect(find.text('Dive log and analysis for CCR divers'), findsOneWidget);
    expect(t.widget<Text>(_k('about-version')).data, '1.1.0');
    expect(t.widget<Text>(_k('about-build')).data, '43');
    expect(t.widget<Text>(_k('about-date')).data, '6 Nov 2026');
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    expect(find.text('Egbert de Pauw'), findsOneWidget);
    expect(_k('about-dev-build'), findsNothing);
  });

  testWidgets('no date define hides the Date stat', (t) async {
    await _pump(t,
        const AboutTab(version: '1.1.0', build: '43', channel: 'nightly'));
    expect(_k('about-date'), findsNothing);
    expect(find.text('Date'), findsNothing);
    expect(_k('about-version'), findsOneWidget);
    expect(find.text('Nightly'), findsOneWidget);
  });

  testWidgets('a development build shows "Development build"', (t) async {
    await _pump(t, const AboutTab(version: '', build: '', channel: 'dev'));
    expect(find.text('Development build'), findsOneWidget);
    expect(_k('about-version'), findsNothing);
    expect(_k('about-build'), findsNothing);
    expect(find.text('Development'), findsOneWidget);
  });

  testWidgets('the licence row is hidden without a licence', (t) async {
    await _pump(t, const AboutTab());
    expect(_k('about-licence'), findsNothing);
    await _pump(t, const AboutTab(hasLicence: true));
    expect(_k('about-licence'), findsOneWidget);
    expect(find.text('GPLv2'), findsOneWidget);
  });

  testWidgets('long-pressing the logo calls onLongPressLogo', (t) async {
    var calls = 0;
    await _pump(t, AboutTab(onLongPressLogo: () => calls++));
    await t.longPress(_k('about-logo'));
    expect(calls, 1);
  });

  testWidgets('the support row calls onShareBleLog', (t) async {
    var calls = 0;
    await _pump(t, AboutTab(onShareBleLog: () => calls++));
    await t.tap(_k('about-share-ble-log'));
    expect(calls, 1);
  });

  testWidgets('renders without overflow in every theme', (t) async {
    for (final def in AppThemes.all) {
      await _pump(
          t,
          const AboutTab(
              version: '1.1.0',
              build: '43',
              buildDate: '2026-11-06',
              channel: 'release',
              hasLicence: true),
          theme: def.themeData);
      expect(t.takeException(), isNull, reason: def.id);
    }
  });
}
