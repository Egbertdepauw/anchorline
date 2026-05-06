import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SiteMiniMap builds with given coords', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SiteMiniMap(lat: 51.5, lon: 3.7, size: 56),
      ),
    ));
    expect(find.byType(SiteMiniMap), findsOneWidget);
  });

  testWidgets('SiteMiniMap defaults to size 64', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SiteMiniMap(lat: 0, lon: 0),
      ),
    ));
    final box = tester.getSize(find.byType(SiteMiniMap));
    expect(box.width, 64);
    expect(box.height, 64);
  });
}
