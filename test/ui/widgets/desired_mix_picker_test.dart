import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ean32 = DesiredMix(32, 0);
const _tx2135 = DesiredMix(21, 35);
const _options = [_ean32, _tx2135];

Finder _key(String k) => find.byKey(ValueKey(k));

bool _selected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(_key(key)).selected;

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

/// Holds the selection like a screen would, and records every change.
class _Host extends StatefulWidget {
  const _Host({this.initial, this.options = _options});

  final DesiredMix? initial;
  final List<DesiredMix> options;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late DesiredMix? selected = widget.initial;
  final changes = <DesiredMix?>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: DesiredMixPicker(
          options: widget.options,
          selected: selected,
          onChanged: (m) {
            changes.add(m);
            setState(() => selected = m);
          },
        ),
      ),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester, {
  DesiredMix? initial,
  List<DesiredMix> options = _options,
}) async {
  await tester.pumpWidget(_Host(initial: initial, options: options));
  return tester.state<_HostState>(find.byType(_Host));
}

Future<void> _openOther(WidgetTester tester) async {
  await tester.tap(_key('desired-mix-other'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String? o2, String? he}) async {
  if (o2 != null) await tester.enterText(_key('desired-mix-other-o2'), o2);
  if (he != null) await tester.enterText(_key('desired-mix-other-he'), he);
  await tester.pump();
}

void main() {
  group('chips', () {
    testWidgets('shows one chip per option, then "Other…", none selected',
        (tester) async {
      await _pump(tester);

      expect(_key('desired-mix-32-0'), findsOneWidget);
      expect(_key('desired-mix-21-35'), findsOneWidget);
      expect(find.text('EAN32'), findsOneWidget);
      expect(find.text('Tx21/35'), findsOneWidget);
      expect(_key('desired-mix-other'), findsOneWidget);
      expect(find.text('Other…'), findsOneWidget);
      expect(_selected(tester, 'desired-mix-32-0'), isFalse);
      expect(_selected(tester, 'desired-mix-21-35'), isFalse);
    });

    testWidgets('shows only "Other…" when there are no options',
        (tester) async {
      await _pump(tester, options: const []);

      expect(find.byType(ChoiceChip), findsNothing);
      expect(_key('desired-mix-other'), findsOneWidget);
    });

    testWidgets('marks the selected option', (tester) async {
      await _pump(tester, initial: _tx2135);

      expect(_selected(tester, 'desired-mix-21-35'), isTrue);
      expect(_selected(tester, 'desired-mix-32-0'), isFalse);
    });

    testWidgets('tapping a chip selects it, and another chip moves it',
        (tester) async {
      final host = await _pump(tester);

      await tester.tap(_key('desired-mix-32-0'));
      await tester.pump();
      expect(host.changes, [_ean32]);
      expect(_selected(tester, 'desired-mix-32-0'), isTrue);

      await tester.tap(_key('desired-mix-21-35'));
      await tester.pump();
      expect(host.changes, [_ean32, _tx2135]);
      expect(_selected(tester, 'desired-mix-21-35'), isTrue);
      expect(_selected(tester, 'desired-mix-32-0'), isFalse);
    });

    testWidgets('tapping the selected chip deselects it', (tester) async {
      final host = await _pump(tester, initial: _ean32);

      await tester.tap(_key('desired-mix-32-0'));
      await tester.pump();

      expect(host.changes, [null]);
      expect(_selected(tester, 'desired-mix-32-0'), isFalse);
    });

    testWidgets('a selected mix that is not an option gets its own chip',
        (tester) async {
      await _pump(tester, initial: const DesiredMix(36, 0));

      expect(_key('desired-mix-36-0'), findsOneWidget);
      expect(find.text('EAN36'), findsOneWidget);
      expect(_selected(tester, 'desired-mix-36-0'), isTrue);
      // The options are still there.
      expect(_key('desired-mix-32-0'), findsOneWidget);
    });

    testWidgets('a selected option is not shown twice', (tester) async {
      await _pump(tester, initial: _ean32);

      expect(_key('desired-mix-32-0'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
    });
  });

  group('Other…', () {
    testWidgets('opens a dialog with O2 empty and He 0', (tester) async {
      await _pump(tester);
      await _openOther(tester);

      expect(_key('desired-mix-other-o2'), findsOneWidget);
      expect(_key('desired-mix-other-he'), findsOneWidget);
      expect(_key('desired-mix-other-ok'), findsOneWidget);
      expect(_text(tester, 'desired-mix-other-o2'), isEmpty);
      expect(_text(tester, 'desired-mix-other-he'), '0');
    });

    testWidgets('O2 alone picks a nitrox, and it shows as a selected chip',
        (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);

      await _fill(tester, o2: '36');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();

      expect(host.changes, [const DesiredMix(36, 0)]);
      expect(_key('desired-mix-other-ok'), findsNothing);
      expect(_key('desired-mix-36-0'), findsOneWidget);
      expect(_selected(tester, 'desired-mix-36-0'), isTrue);
    });

    testWidgets('O2 and He pick a trimix', (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);

      await _fill(tester, o2: '18', he: '45');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();

      expect(host.changes, [const DesiredMix(18, 45)]);
    });

    testWidgets('an emptied He counts as 0', (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);

      await _fill(tester, o2: '50', he: '');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();

      expect(host.changes, [const DesiredMix(50, 0)]);
    });

    testWidgets('accepts the limits: O2 100, O2 1 with He 99',
        (tester) async {
      final host = await _pump(tester);

      await _openOther(tester);
      await _fill(tester, o2: '100');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();

      await _openOther(tester);
      await _fill(tester, o2: '1', he: '99');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();

      expect(
        host.changes,
        [const DesiredMix(100, 0), const DesiredMix(1, 99)],
      );
    });

    testWidgets('O2 + He above 100 shows the error and keeps the dialog open',
        (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);
      expect(find.text("O2 + He can't exceed 100 %"), findsNothing);

      await _fill(tester, o2: '50', he: '60');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pump();

      expect(find.text("O2 + He can't exceed 100 %"), findsOneWidget);
      expect(_key('desired-mix-other-ok'), findsOneWidget);
      expect(host.changes, isEmpty);
    });

    testWidgets('fixing the values clears the error and accepts them',
        (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);
      await _fill(tester, o2: '50', he: '60');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pump();
      expect(find.text("O2 + He can't exceed 100 %"), findsOneWidget);

      await _fill(tester, he: '50');
      expect(find.text("O2 + He can't exceed 100 %"), findsNothing);

      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();
      expect(host.changes, [const DesiredMix(50, 50)]);
    });

    for (final o2 in ['', '0', '101']) {
      testWidgets('O2 "$o2" is rejected', (tester) async {
        final host = await _pump(tester);
        await _openOther(tester);

        await _fill(tester, o2: o2);
        await tester.tap(_key('desired-mix-other-ok'));
        await tester.pump();

        expect(find.text('O2 must be 1–100 %'), findsOneWidget);
        expect(_key('desired-mix-other-ok'), findsOneWidget);
        expect(host.changes, isEmpty);
      });
    }

    testWidgets('He 100 is rejected', (tester) async {
      final host = await _pump(tester);
      await _openOther(tester);

      await _fill(tester, o2: '1', he: '100');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pump();

      expect(find.text('He must be 0–99 %'), findsOneWidget);
      expect(host.changes, isEmpty);
    });

    testWidgets('only digits can be typed', (tester) async {
      await _pump(tester);
      await _openOther(tester);

      await _fill(tester, o2: '3.6-x');

      expect(_text(tester, 'desired-mix-other-o2'), '36');
    });

    testWidgets('Cancel closes the dialog without a change', (tester) async {
      final host = await _pump(tester, initial: _ean32);
      await _openOther(tester);
      await _fill(tester, o2: '36');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(_key('desired-mix-other-ok'), findsNothing);
      expect(host.changes, isEmpty);
      expect(_selected(tester, 'desired-mix-32-0'), isTrue);
    });
  });
}
