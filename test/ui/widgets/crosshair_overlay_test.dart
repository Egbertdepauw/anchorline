import 'package:ccrlogger/ui/widgets/crosshair_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders child widget', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CrosshairOverlay(
                sampleCount: 100,
                chartLeftPad: 40,
                chartRightPad: 44,
                onIndexChanged: (_) {},
                onRelease: () {},
                child: const SizedBox(width: 360, height: 250)))));
    expect(find.byType(CrosshairOverlay), findsOneWidget);
  });

  testWidgets('long press triggers callback', (tester) async {
    int? reportedIndex;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: CrosshairOverlay(
                    sampleCount: 100,
                    chartLeftPad: 40,
                    chartRightPad: 44,
                    onIndexChanged: (i) => reportedIndex = i,
                    onRelease: () {},
                    child: Container(color: Colors.black))))));
    final center = tester.getCenter(find.byType(CrosshairOverlay));
    await tester.longPressAt(center);
    await tester.pump();
    expect(reportedIndex, isNotNull);
    expect(reportedIndex, greaterThanOrEqualTo(0));
    expect(reportedIndex, lessThan(100));
  });
}
