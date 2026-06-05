import 'package:ccrlogger/ui/widgets/renumber_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows preview and returns RenumberApply with the start number',
      (tester) async {
    RenumberResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showRenumberDialog(context, 5),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Renumber 5 dives'), findsOneWidget);
    expect(find.textContaining('#1 → #5'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '482');
    await tester.pump();
    expect(find.textContaining('#482 → #486'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, isA<RenumberApply>());
    expect((result as RenumberApply).start, 482);
  });
}
