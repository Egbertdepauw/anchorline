import 'package:ccrlogger/ui/licences.dart';
import 'package:ccrlogger/ui/screens/settings/about_tab.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the About tab shows the libdivecomputer version', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppThemes.byId(null).themeData,
      home: const Scaffold(body: AboutTab()),
    ));
    await t.pump();
    // The line proves the native library loaded on the device it runs on.
    expect(find.textContaining('libdivecomputer 0.10.0'), findsOneWidget);
  });

  testWidgets('a library that fails to load shows "not available"', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppThemes.byId(null).themeData,
      home: Scaffold(
        body: AboutTab(readLibdcVersion: () => throw StateError('no library')),
      ),
    ));
    await t.pump();
    expect(find.text('libdivecomputer: not available'), findsOneWidget);
    expect(find.text('Dive log and analysis for CCR divers'), findsOneWidget);
  });

  testWidgets('Open-source licences opens the licence page with libdivecomputer',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    registerLicences();
    await t.pumpWidget(MaterialApp(
      theme: AppThemes.byId(null).themeData,
      home: const Scaffold(body: AboutTab()),
    ));
    await t.pump();
    await t.tap(find.text('Open-source licences'));
    await t.pumpAndSettle();
    expect(find.text('libdivecomputer'), findsWidgets);
  });
}
