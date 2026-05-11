import 'package:ccrlogger/ui/components/numeric_readout.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NumericReadout uses JetBrainsMono', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: NumericReadout('57:30')),
    ));
    final text = tester.widget<Text>(find.text('57:30'));
    expect(text.style?.fontFamily, 'JetBrainsMono');
  });

  testWidgets('NumericReadout sizes match tokens', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(children: [
          NumericReadout('A', size: ReadoutSize.sm),
          NumericReadout('B', size: ReadoutSize.md),
          NumericReadout('C', size: ReadoutSize.lg),
        ]),
      ),
    ));
    final a = tester.widget<Text>(find.text('A')).style!;
    final b = tester.widget<Text>(find.text('B')).style!;
    final c = tester.widget<Text>(find.text('C')).style!;
    expect(a.fontSize, 13);
    expect(b.fontSize, 16);
    expect(c.fontSize, 24);
  });
}
