import 'package:ccrlogger/ui/util/pop_to_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester t, {required bool guarded}) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Text('root'),
    ));
    key.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => PopScope(
        canPop: !guarded,
        child: const Text('detail'),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('pops to the root when nothing guards', (t) async {
    await pump(t, guarded: false);
    await popToRootRespectingGuards(key.currentState!);
    await t.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('stops at a screen whose PopScope refuses', (t) async {
    await pump(t, guarded: true);
    await popToRootRespectingGuards(key.currentState!);
    await t.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });
}
