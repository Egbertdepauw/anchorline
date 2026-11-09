import 'package:ccrlogger/ui/widgets/planner_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the warning text matches the website wording', () {
    // Same text as PLANNER_WARNING in anchorline-web src/content/home.ts.
    expect(kPlannerWarningText, startsWith('A plan from this planner can kill you.'));
    expect(kPlannerWarningText, endsWith('do not use its plans.'));
    expect(kPlannerWarningText, isNot(contains('  ')));
    expect(kPlannerWarningUrl.toString(),
        'https://anchorline.eu/planner-warning');
  });

  testWidgets('gate without onNotNow has no way out but accepting',
      (tester) async {
    var accepted = 0;
    await tester.pumpWidget(MaterialApp(
      home: PlannerWarningGate(onAccept: () => accepted++),
    ));

    expect(find.byKey(const ValueKey('planner-warning-not-now')), findsNothing);
    await tester.tap(find.text('I understand and accept'));
    expect(accepted, 1);
  });

  testWidgets('tapping the short line opens the full warning',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlannerWarningLine(onOpen: () => opened++)),
    ));

    expect(find.textContaining(kPlannerWarningShortText), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-warning-line')));
    expect(opened, 1);
  });
}
