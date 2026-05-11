import 'package:ccrlogger/ui/components/data_row.dart' as components;
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DataRow renders label + value', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: components.DataRow(label: 'Atm. pressure', value: '1003 mbar'),
      ),
    ));
    expect(find.text('Atm. pressure'), findsOneWidget);
    expect(find.text('1003 mbar'), findsOneWidget);
  });

  testWidgets('DataRow with numeric:true uses monospace', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: components.DataRow(label: 'GF', value: '14%', numeric: true),
      ),
    ));
    final valueText = tester.widget<Text>(find.text('14%'));
    expect(valueText.style?.fontFamily, 'JetBrainsMono');
  });
}
