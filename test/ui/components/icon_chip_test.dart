import 'package:ccrlogger/ui/components/icon_chip.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('IconChip renders icon + label and is tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: IconChip(
          label: 'CCR',
          icon: Icons.air,
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('CCR'), findsOneWidget);
    expect(find.byIcon(Icons.air), findsOneWidget);
    await tester.tap(find.byType(IconChip));
    expect(taps, 1);
  });
}
