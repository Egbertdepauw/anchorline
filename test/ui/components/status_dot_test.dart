import 'package:ccrlogger/ui/components/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatusDot renders a coloured circle of the right size',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusDot(color: Colors.red)),
    ));
    final container = tester.widget<Container>(find.byType(Container));
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, Colors.red);
    expect(dec.shape, BoxShape.circle);
    expect(container.constraints?.maxWidth, 8);
  });
}
