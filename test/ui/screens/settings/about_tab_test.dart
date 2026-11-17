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
}
