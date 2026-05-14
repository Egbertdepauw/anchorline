import 'package:ccrlogger/ui/widgets/background_watermark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BackgroundWatermark with opacity 0 renders only the child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets(
      'BackgroundWatermark with opacity > 0 renders an Opacity + Image '
      'alongside the child', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, closeTo(0.1, 0.001));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('BackgroundWatermark wraps the watermark in IgnorePointer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    // MaterialApp/Navigator introduces additional IgnorePointer nodes;
    // scope to the one owned by BackgroundWatermark (ignoring: true).
    expect(
      find.ancestor(
        of: find.byType(Opacity),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsOneWidget,
    );
  });
}
