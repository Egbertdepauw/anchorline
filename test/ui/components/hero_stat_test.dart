import 'package:ccrlogger/ui/components/hero_stat.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('HeroStat shows value, unit and label', (tester) async {
    await tester.pumpWidget(_wrap(const HeroStat(
      value: '18.0',
      unit: 'm',
      label: 'MAX DEPTH',
      valueKey: ValueKey('v'),
    )));
    expect(find.text('18.0'), findsOneWidget);
    expect(find.text('m'), findsOneWidget);
    expect(find.text('MAX DEPTH'), findsOneWidget);
    expect(find.byKey(const ValueKey('v')), findsOneWidget);
  });

  testWidgets('HeroStatRow puts n - 1 dividers between n stats',
      (tester) async {
    await tester.pumpWidget(_wrap(const HeroStatRow(children: [
      HeroStat(value: '1', label: 'A'),
      HeroStat(value: '2', label: 'B'),
      HeroStat(value: '3', label: 'C'),
    ])));
    expect(find.byType(VerticalDivider), findsNWidgets(2));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });
}
