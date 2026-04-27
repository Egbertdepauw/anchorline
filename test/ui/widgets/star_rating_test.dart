import 'package:ccrlogger/ui/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders 5 star icons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: null, onChanged: (_) {}),
      ),
    ));
    expect(find.byIcon(Icons.star_outline), findsNWidgets(5));
  });

  testWidgets('value=3 fills first 3 stars', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: 3, onChanged: (_) {}),
      ),
    ));
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_outline), findsNWidgets(2));
  });

  testWidgets('tap star N → onChanged(N)', (tester) async {
    int? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: null, onChanged: (v) => captured = v),
      ),
    ));
    await tester.tap(find.byIcon(Icons.star_outline).at(2));
    expect(captured, 3);
  });

  testWidgets('tap currently-active star → onChanged(null)', (tester) async {
    int? captured = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: 3, onChanged: (v) => captured = v),
      ),
    ));
    await tester.tap(find.byIcon(Icons.star).at(2));
    expect(captured, isNull);
  });
}
