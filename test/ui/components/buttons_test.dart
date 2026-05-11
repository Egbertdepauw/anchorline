import 'package:ccrlogger/ui/components/accent_button.dart';
import 'package:ccrlogger/ui/components/ghost_button.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AccentButton uppercases its label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: AccentButton(label: 'Push to subs', onPressed: () {}),
      ),
    ));
    expect(find.text('PUSH TO SUBS'), findsOneWidget);
  });

  testWidgets('GhostButton uppercases its label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: GhostButton(label: 'Cancel', onPressed: () {}),
      ),
    ));
    expect(find.text('CANCEL'), findsOneWidget);
  });
}
