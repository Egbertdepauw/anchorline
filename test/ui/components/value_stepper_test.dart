import 'package:ccrlogger/ui/components/value_stepper.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(int value, ValueChanged<int> onChanged,
        {int min = 10, int max = 30}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ValueStepper(
          value: value,
          min: min,
          max: max,
          unit: 'bar',
          keyPrefix: 'fill',
          onChanged: onChanged,
        ),
      ),
    );

IconButton _button(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('+ from 20 calls onChanged(21); - calls onChanged(19)',
      (tester) async {
    final calls = <int>[];
    await tester.pumpWidget(_wrap(20, calls.add));
    await tester.tap(find.byKey(const ValueKey('fill-inc')));
    await tester.tap(find.byKey(const ValueKey('fill-dec')));
    expect(calls, [21, 19]);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
  });

  testWidgets('buttons disable at the limits', (tester) async {
    await tester.pumpWidget(_wrap(30, (_) {}));
    expect(_button(tester, 'fill-inc').onPressed, isNull);
    expect(_button(tester, 'fill-dec').onPressed, isNotNull);
    await tester.pumpWidget(_wrap(10, (_) {}));
    expect(_button(tester, 'fill-dec').onPressed, isNull);
    expect(_button(tester, 'fill-inc').onPressed, isNotNull);
  });

  testWidgets('step is clamped to the limits', (tester) async {
    final calls = <int>[];
    await tester.pumpWidget(Material(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ValueStepper(
            value: 28,
            min: 10,
            max: 30,
            step: 5,
            keyPrefix: 's',
            onChanged: calls.add,
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('s-inc')));
    expect(calls, [30]);
  });
}
