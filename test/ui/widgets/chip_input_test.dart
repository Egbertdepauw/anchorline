import 'package:ccrlogger/ui/widgets/chip_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders initial chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChipInput(
          values: const ['Alex', 'Sam'],
          autocompleteOptions: const [],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('typing + Enter promotes text to a chip', (tester) async {
    final captured = <List<String>>[];
    var values = const <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ChipInput(
            values: values,
            autocompleteOptions: const [],
            onChanged: (v) {
              captured.add(v);
              setState(() => values = v);
            },
          ),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Robin');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.widgetWithText(Chip, 'Robin'), findsOneWidget);
    expect(captured.last, ['Robin']);
  });

  testWidgets('tap chip × removes it', (tester) async {
    final captured = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChipInput(
          values: const ['Alex', 'Sam'],
          autocompleteOptions: const [],
          onChanged: captured.add,
        ),
      ),
    ));

    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsNWidgets(2));
    await tester.tap(closeIcons.first);
    await tester.pump();

    expect(captured.last, ['Sam']);
  });
}
