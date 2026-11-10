import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/mix_mismatch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GasAnalysis _analysis({
  required double o2,
  double he = 0,
  required int targetO2,
  int targetHe = 0,
}) {
  return GasAnalysis(
    id: 'a1',
    analysedAt: DateTime(2026, 10, 31, 9),
    o2Percent: o2,
    hePercent: he,
    stable: true,
    targetO2Percent: targetO2,
    targetHePercent: targetHe,
  );
}

/// A screen with one button that opens the dialog and keeps the result.
class _Host extends StatefulWidget {
  const _Host(this.analysis);

  final GasAnalysis analysis;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  MismatchChoice? result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () async {
                final r = await showMixMismatchDialog(
                  context,
                  analysis: widget.analysis,
                );
                setState(() => result = r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

Future<_HostState> _open(WidgetTester tester, GasAnalysis a) async {
  await tester.pumpWidget(_Host(a));
  await tester.tap(_key('open'));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

final _ean50AsEan32 = _analysis(o2: 32.1, targetO2: 50);

void main() {
  testWidgets('shows the red header and the explanation', (tester) async {
    await _open(tester, _ean50AsEan32);

    expect(find.text('Mix does not conform to analysis'), findsOneWidget);
    expect(
      tester.widget<ColoredBox>(_key('mix-mismatch-header')).color,
      SafetyColors.alertCriticalSurface,
    );
    expect(
      tester
          .widget<Text>(find.text('Mix does not conform to analysis'))
          .style
          ?.color,
      SafetyColors.onAlert,
    );
    expect(
      find.text(
        'Desired EAN50, analysed O2 32.1 % (EAN32). '
        'The label will show EAN32.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('offers the three choices, "Print as …" being primary',
      (tester) async {
    await _open(tester, _ean50AsEan32);

    expect(find.text('Print as EAN32'), findsOneWidget);
    expect(find.text('Change desired mix'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.widget(_key('mix-mismatch-print')), isA<FilledButton>());
    expect(tester.widget(_key('mix-mismatch-change')), isA<TextButton>());
    expect(tester.widget(_key('mix-mismatch-cancel')), isA<TextButton>());
  });

  testWidgets('names the helium too when helium is involved', (tester) async {
    await _open(
      tester,
      _analysis(o2: 21, he: 20, targetO2: 21, targetHe: 35),
    );

    expect(
      find.text(
        'Desired Tx21/35, analysed O2 21.0 %, He 20.0 % (Tx21/20). '
        'The label will show Tx21/20.',
      ),
      findsOneWidget,
    );
    expect(find.text('Print as Tx21/20'), findsOneWidget);
  });

  testWidgets('leaves out helium that is only sensor offset', (tester) async {
    await _open(tester, _analysis(o2: 32.1, he: 0.4, targetO2: 50));

    expect(
      find.text(
        'Desired EAN50, analysed O2 32.1 % (EAN32). '
        'The label will show EAN32.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Print as …" returns printAnalysed', (tester) async {
    final host = await _open(tester, _ean50AsEan32);

    await tester.tap(_key('mix-mismatch-print'));
    await tester.pumpAndSettle();

    expect(host.result, MismatchChoice.printAnalysed);
    expect(_key('mix-mismatch-print'), findsNothing);
  });

  testWidgets('"Change desired mix" returns changeMix', (tester) async {
    final host = await _open(tester, _ean50AsEan32);

    await tester.tap(_key('mix-mismatch-change'));
    await tester.pumpAndSettle();

    expect(host.result, MismatchChoice.changeMix);
  });

  testWidgets('"Cancel" returns cancel', (tester) async {
    final host = await _open(tester, _ean50AsEan32);

    await tester.tap(_key('mix-mismatch-cancel'));
    await tester.pumpAndSettle();

    expect(host.result, MismatchChoice.cancel);
  });

  testWidgets('dismissing the dialog counts as cancel', (tester) async {
    final host = await _open(tester, _ean50AsEan32);

    // Tap the barrier, outside the dialog.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(_key('mix-mismatch-print'), findsNothing);
    expect(host.result, MismatchChoice.cancel);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await _open(tester, _ean50AsEan32);

    expect(tester.takeException(), isNull);
    expect(_key('mix-mismatch-print'), findsOneWidget);
  });
}
