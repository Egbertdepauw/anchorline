import 'package:ccrlogger/ui/components/stat_tile.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatTile renders label uppercased + value + hint',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: StatTile(
          label: 'Max depth',
          value: '18.0',
          unit: 'm',
          hint: 'avg 9.6',
        ),
      ),
    ));
    expect(find.text('MAX DEPTH  M'), findsOneWidget);
    expect(find.text('18.0'), findsOneWidget);
    expect(find.text('avg 9.6'), findsOneWidget);
  });

  testWidgets('StatTile without hint omits the auxiliary line',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: StatTile(label: 'CNS', value: '45%')),
    ));
    expect(find.text('CNS'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
  });
}
