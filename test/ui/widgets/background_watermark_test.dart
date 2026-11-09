import 'package:ccrlogger/ui/widgets/background_watermark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BackgroundWatermark with opacity 0 renders only the child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets(
      'BackgroundWatermark with opacity > 0 renders an Opacity + Image '
      'alongside the child', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, closeTo(0.1, 0.001));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('BackgroundWatermark wraps the watermark in IgnorePointer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    // MaterialApp/Navigator introduces additional IgnorePointer nodes;
    // scope to the one owned by BackgroundWatermark (ignoring: true).
    expect(
      find.ancestor(
        of: find.byType(Opacity),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'BackgroundWatermark keeps the child\'s state when the opacity drops '
      'to 0 and comes back (#183)', (tester) async {
    // The Settings tab hides the watermark. Returning the bare child at
    // opacity 0 used to rebuild every tab below it from scratch.
    _probeInits = 0;
    Future<void> pumpAt(double opacity) => tester.pumpWidget(MaterialApp(
          home: BackgroundWatermark(opacity: opacity, child: const _Probe()),
        ));
    await pumpAt(0.06);
    await pumpAt(0);
    await pumpAt(0.06);
    expect(find.text('probe'), findsOneWidget);
    expect(_probeInits, 1);
  });

  group('WatermarkSuppressionScope / SuppressWatermark', () {
    testWidgets(
        'SuppressWatermark under a scope counts up after a frame and back '
        'down to 0 when removed', (tester) async {
      final suppressors = ValueNotifier<int>(0);
      addTearDown(suppressors.dispose);

      Widget host({required bool suppressed}) => MaterialApp(
            home: WatermarkSuppressionScope(
              suppressors: suppressors,
              child: suppressed
                  ? const SuppressWatermark(child: Text('content'))
                  : const Text('content'),
            ),
          );

      await tester.pumpWidget(host(suppressed: true));
      await tester.pump();
      expect(find.text('content'), findsOneWidget);
      expect(suppressors.value, 1);

      await tester.pumpWidget(host(suppressed: false));
      await tester.pump();
      expect(suppressors.value, 0);
    });

    testWidgets('two stacked SuppressWatermark widgets count as 2',
        (tester) async {
      final suppressors = ValueNotifier<int>(0);
      addTearDown(suppressors.dispose);

      Widget host({required bool suppressed}) => MaterialApp(
            home: WatermarkSuppressionScope(
              suppressors: suppressors,
              child: suppressed
                  ? const SuppressWatermark(
                      child: SuppressWatermark(child: Text('content')),
                    )
                  : const Text('content'),
            ),
          );

      await tester.pumpWidget(host(suppressed: true));
      await tester.pump();
      expect(suppressors.value, 2);

      await tester.pumpWidget(host(suppressed: false));
      await tester.pump();
      expect(suppressors.value, 0);
    });

    testWidgets('SuppressWatermark without a scope is a silent no-op',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: SuppressWatermark(child: Text('content')),
      ));
      await tester.pump();
      expect(find.text('content'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Removing it again must be just as quiet.
      await tester.pumpWidget(const MaterialApp(home: Text('content')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

var _probeInits = 0;

/// Counts how often its State is created, to detect remounts.
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _probeInits++;
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
