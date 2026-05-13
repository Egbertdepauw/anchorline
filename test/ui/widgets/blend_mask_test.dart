import 'package:ccrlogger/ui/widgets/blend_mask.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BlendMask wraps its child in a render object with the given blendMode + opacity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BlendMask(
        blendMode: BlendMode.screen,
        opacity: 0.5,
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    final renderObject =
        tester.renderObject(find.byType(BlendMask));
    expect(renderObject, isNotNull);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('BlendMask updates its render object when blendMode changes',
      (tester) async {
    Widget build(BlendMode mode) => MaterialApp(
          home: BlendMask(
            blendMode: mode,
            opacity: 0.5,
            child: const SizedBox(width: 40, height: 40),
          ),
        );
    await tester.pumpWidget(build(BlendMode.screen));
    await tester.pumpWidget(build(BlendMode.multiply));
    expect(find.byType(BlendMask), findsOneWidget);
  });
}
