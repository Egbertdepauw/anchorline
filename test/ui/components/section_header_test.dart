import 'package:ccrlogger/ui/components/section_header.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SectionHeader renders uppercase label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: SectionHeader('Environment')),
    ));
    expect(find.text('ENVIRONMENT'), findsOneWidget);
  });
}
