import 'dart:typed_data';
import 'package:ccrlogger/ui/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthSparkline widget', () {
    testWidgets('renders without error', (tester) async {
      final depths = Float32List.fromList([0, 5, 10, 20, 30, 30, 25, 15, 5, 0]);
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(depths: depths, color: Colors.cyan),
        ),
      ));
      expect(find.byType(DepthSparkline), findsOneWidget);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('renders with empty data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(depths: Float32List(0), color: Colors.cyan),
        ),
      ));
      expect(find.byType(DepthSparkline), findsOneWidget);
    });

    testWidgets('renders with single point', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(
              depths: Float32List.fromList([10.0]), color: Colors.orange),
        ),
      ));
      expect(find.byType(DepthSparkline), findsOneWidget);
    });
  });

  group('downsample', () {
    test('returns original if <= maxPoints', () {
      final data = Float32List.fromList([1, 2, 3, 4, 5]);
      final result = downsampleDepth(data, 30);
      expect(result, equals(data));
    });

    test('downsamples large arrays to ~maxPoints', () {
      final data = Float32List(1000);
      for (var i = 0; i < 1000; i++) {
        data[i] = i.toDouble();
      }
      final result = downsampleDepth(data, 30);
      expect(result.length, lessThanOrEqualTo(34));
      expect(result.length, greaterThanOrEqualTo(28));
    });
  });
}
