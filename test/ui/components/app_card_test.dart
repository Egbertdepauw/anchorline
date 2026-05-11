import 'package:ccrlogger/ui/components/app_card.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppCard renders surface.card background',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: AppCard(child: Text('hello'))),
    ));
    expect(find.text('hello'), findsOneWidget);
    final container = tester.widget<Container>(find.byType(Container).first);
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, AppColors.wreck.surfaceCard);
    expect(dec.border, isNull); // default withBezel: false
  });

  testWidgets('AppCard with bezel adds an outline', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: AppCard(withBezel: true, child: Text('x')),
      ),
    ));
    final container = tester.widget<Container>(find.byType(Container).first);
    final dec = container.decoration as BoxDecoration;
    expect(dec.border, isNotNull);
  });
}
