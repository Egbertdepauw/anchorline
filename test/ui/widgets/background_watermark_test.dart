import 'package:ccrlogger/ui/widgets/background_watermark.dart';
import 'package:ccrlogger/ui/widgets/blend_mask.dart';
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
    expect(find.byType(BlendMask), findsNothing);
  });

  testWidgets('BackgroundWatermark with opacity > 0 renders a BlendMask + Image alongside the child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    final blendMask = tester.widget<BlendMask>(find.byType(BlendMask));
    expect(blendMask.blendMode, BlendMode.screen);
    expect(blendMask.opacity, closeTo(0.1, 0.001));
  });

  testWidgets('BackgroundWatermark wraps the watermark in IgnorePointer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    // The MaterialApp/Navigator stack introduces additional IgnorePointer nodes;
    // scope the check to the one owned by BackgroundWatermark (ignoring: true).
    expect(
      find.ancestor(
        of: find.byType(BlendMask),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsOneWidget,
    );
  });
}
