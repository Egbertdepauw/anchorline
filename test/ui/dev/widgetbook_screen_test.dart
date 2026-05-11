import 'package:ccrlogger/ui/dev/widgetbook_screen.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WidgetbookScreen renders without exceptions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const WidgetbookScreen(),
    ));
    await tester.pumpAndSettle();
    // Spot-check that key sections rendered. Sections beyond the initial
    // viewport are lazily built by ListView, so we scroll to each one.
    expect(find.text('PALETTE'), findsOneWidget);
    expect(find.text('CARDS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('NUMERIC READOUTS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('NUMERIC READOUTS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('STAT TILES'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('STAT TILES'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('BUTTONS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BUTTONS'), findsOneWidget);
  });
}
