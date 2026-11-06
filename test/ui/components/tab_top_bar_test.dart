import 'package:ccrlogger/ui/components/tab_top_bar.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(VoidCallback onHome) => MaterialApp(
      theme: AppTheme.dark(),
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: TabTopBar(
            tabs: const [Tab(text: 'Analyse'), Tab(text: 'Log')],
            onHome: onHome,
          ),
          body: const SizedBox(),
        ),
      ),
    );

void main() {
  testWidgets('tapping the anchor calls onHome once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(() => taps++));
    await tester.tap(find.byKey(const ValueKey('tab-top-bar-home')));
    expect(taps, 1);
  });

  testWidgets('renders the tab labels', (tester) async {
    await tester.pumpWidget(_wrap(() {}));
    expect(find.text('Analyse'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
  });

  test('preferredSize is 56 tall', () {
    const bar = TabTopBar(tabs: [Tab(text: 'A')], onHome: _noop);
    expect(bar.preferredSize.height, 56);
  });
}

void _noop() {}
