import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the selected transport note (OTG power hint)',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = AnalyzerSession(
      settings: settings,
      transportOptions: [
        AnalyzerTransportOption(
          label: 'USB',
          create: () => DemoAnalyzerTransport(),
          note: 'The phone powers the analyzer over the USB OTG cable.',
        ),
        AnalyzerTransportOption(
          label: 'Demo',
          create: () => DemoAnalyzerTransport(),
        ),
      ],
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AnalyzerScreen(settings: settings, session: session)),
    ));

    expect(find.byKey(const ValueKey('analyzer-transport-note')),
        findsOneWidget);
    expect(find.textContaining('USB OTG'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('analyzer-transport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analyzer-transport-note')),
        findsNothing);
  });
}
