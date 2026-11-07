import 'dart:async';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport_options.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:ccrlogger/ui/screens/gas_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

String _line(double o2, double he) =>
    'He  ${he.toStringAsFixed(1).padLeft(5)} %  '
    'O2  ${o2.toStringAsFixed(1).padLeft(5)} %  '
    'Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';

/// A transport the test drives line by line (synchronous delivery).
class _FakeSolo implements AnalyzerTransport {
  final _lines = StreamController<String>.broadcast(sync: true);
  final _statuses =
      StreamController<AnalyzerConnectionStatus>.broadcast(sync: true);
  AnalyzerConnectionStatus _status = AnalyzerConnectionStatus.disconnected;

  void emitLine(String line) => _lines.add(line);

  void _set(AnalyzerConnectionStatus s) {
    _status = s;
    _statuses.add(s);
  }

  @override
  String get name => 'Fake SOLO';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  AnalyzerConnectionStatus get status => _status;
  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _statuses.stream;
  @override
  String? get errorMessage => null;
  @override
  Future<void> connect() async => _set(AnalyzerConnectionStatus.connected);
  @override
  Future<void> disconnect() async =>
      _set(AnalyzerConnectionStatus.disconnected);
  @override
  Future<void> dispose() async {}
}

class _Rig {
  late SettingsNotifier settings;
  late BlendNotifier blend;
  late AnalyzerSession session;
  late AnalyzerController controller;
  final dao = FakeGasAnalysesDao();
  _FakeSolo? solo;
  UsbOkLogger? logger;
  int homeTaps = 0;

  Future<void> pump(WidgetTester tester,
      {bool logOnOk = false, ThemeData? theme}) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = SettingsNotifier();
    await settings.load();
    if (logOnOk) await settings.setAnalyzerLogOnOk(true);
    blend = BlendNotifier(settings: settings);
    session = AnalyzerSession(
      settings: settings,
      analysesDao: dao,
      blend: blend,
      controller: controller = AnalyzerController(elapsed: fakeElapsed(tester)),
      keepAwake: (_) async {},
      transportOptions: [
        AnalyzerTransportOption(
            label: 'Bench', create: () => solo = _FakeSolo()),
      ],
      okLoggerFactory: () => logger = buildOkLogger(
        dao: dao,
        elapsed: fakeElapsed(tester),
        tickInterval: null,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: GasScreen(
        blend: blend,
        settings: settings,
        session: session,
        analysesDao: dao,
        onHome: () => homeTaps++,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Leaves the screen and stops the controller's timers, which the test
  /// binding insists on at the end of a test.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    controller.dispose();
  }

  Future<void> connect(WidgetTester tester) async {
    await session.connectSelected(tester.element(find.byType(GasScreen)));
    await tester.pump();
  }

  Future<void> feed(WidgetTester tester, double o2, double he,
      {int seconds = 25}) async {
    for (var i = 0; i < seconds * 2; i++) {
      solo!.emitLine(_line(o2, he));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> pressOk(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2200));
    logger!.tick();
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _tab(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// A widget test on a [_Rig] that is ended properly afterwards.
void _test(String description,
    Future<void> Function(WidgetTester tester, _Rig rig) body) {
  testWidgets(description, (tester) async {
    final rig = _Rig();
    try {
      await body(tester, rig);
    } finally {
      await rig.end(tester);
    }
  });
}

Widget _navItemIcon(BottomNavigationBarItem item) => item.icon;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _test('opens on the Blend tab with three tabs', (tester, rig) async {
    await rig.pump(tester);
    expect(_key('gas-tab-blend'), findsOneWidget);
    expect(_key('gas-tab-analyse'), findsOneWidget);
    expect(_key('gas-tab-log'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byIcon(Icons.science_outlined), findsNothing);
    // Blend's fields are showing; the log is not.
    expect(_key('tgt-o2'), findsOneWidget);
    expect(find.byType(GasAnalysisLogScreen), findsNothing);
  });

  _test('switching to Log and back keeps the analyzer connected',
      (tester, rig) async {
    await rig.pump(tester);
    await _tab(tester, 'gas-tab-analyse');
    await rig.connect(tester);
    await rig.feed(tester, 32.0, 0, seconds: 3);
    expect(rig.session.controller.isConnected, isTrue);
    expect(find.text('32.0'), findsWidgets);

    await _tab(tester, 'gas-tab-log');
    expect(find.byType(GasAnalysisLogScreen), findsOneWidget);
    await _tab(tester, 'gas-tab-analyse');

    expect(rig.session.controller.isConnected, isTrue);
    expect(rig.session.controller.latest, isNotNull);
    expect(find.text('32.0'), findsWidgets);
  });

  _test('an OK press while on the Log tab is still saved',
      (tester, rig) async {
    await rig.pump(tester, logOnOk: true);
    await _tab(tester, 'gas-tab-analyse');
    await rig.connect(tester);
    final logger = rig.logger;
    expect(logger, isNotNull);
    expect(rig.session.okLogger, same(logger));

    await tester.enterText(_key('analysis-diver'), 'EdP');
    await tester.pump();
    // Let go of the field: a focused field would keep its page alive by
    // itself and hide a missing keep-alive.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tab(tester, 'gas-tab-log');

    await rig.feed(tester, 32.0, 0);
    await rig.pressOk(tester);

    expect(rig.dao.addedFromBridge, hasLength(1));
    expect(rig.dao.addedFromBridge.single.$2.analysedBy, 'EdP');
    expect(rig.session.okLogger, same(logger));
  });

  _test('an OK press after Analyse, Blend, Log is still saved',
      (tester, rig) async {
    await rig.pump(tester, logOnOk: true);
    await _tab(tester, 'gas-tab-analyse');
    await rig.connect(tester);
    await tester.enterText(_key('analysis-diver'), 'EdP');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tab(tester, 'gas-tab-blend');
    await _tab(tester, 'gas-tab-log');

    await rig.feed(tester, 32.0, 0);
    await rig.pressOk(tester);

    expect(rig.dao.addedFromBridge, hasLength(1));
    expect(rig.dao.addedFromBridge.single.$2.analysedBy, 'EdP');
  });

  _test('the anchor calls onHome', (tester, rig) async {
    await rig.pump(tester);
    await tester.tap(_key('tab-top-bar-home'));
    expect(rig.homeTaps, 1);
  });

  _test('the Analyse dot shows while connected and turns accent '
      'while logging', (tester, rig) async {
    await rig.pump(tester, logOnOk: true);
    expect(_key('gas-tab-analyse-dot'), findsNothing);

    await rig.connect(tester);
    await tester.pump();
    expect(rig.session.okRunning, isTrue);
    final dot = tester.widget<Container>(_key('gas-tab-analyse-dot'));
    final accent = tester.element(_key('gas-tab-analyse-dot')).palette
        .accentPrimary;
    expect((dot.decoration! as BoxDecoration).color, accent);

    await rig.session.disconnect();
    await tester.pump();
    expect(_key('gas-tab-analyse-dot'), findsNothing);
  });

  _test('the Analyse dot is green while connected without logging',
      (tester, rig) async {
    await rig.pump(tester);
    await rig.connect(tester);
    expect(rig.session.okRunning, isFalse);
    final dot = tester.widget<Container>(_key('gas-tab-analyse-dot'));
    expect((dot.decoration! as BoxDecoration).color, SafetyColors.success);
  });

  _test('on a 393 pt phone the Analyse label shows in full beside its dot',
      (tester, rig) async {
    // The app's theme, so the label is set in Inter as on a device (the
    // default test font is far wider).
    await rig.pump(tester, theme: AppThemes.byId(null).themeData);
    await _tab(tester, 'gas-tab-analyse');
    await rig.connect(tester);
    expect(_key('gas-tab-analyse-dot'), findsOneWidget);
    tester.view.physicalSize = const Size(393, 852);
    await tester.pumpAndSettle();

    // The test font (Ahem) is far wider than Inter, so a TextPainter cannot
    // say whether the word fits. In Inter / Roboto 14 sp medium "Analyse" is
    // about 52 pt; the label must be given at least 58 pt beside the icon and
    // the dot. (With the default 16 pt tab padding it got about 45 pt and
    // showed "Analy…".)
    final label = find.descendant(
        of: _key('gas-tab-analyse'), matching: find.text('Analyse'));
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.size.width, greaterThanOrEqualTo(58));
  });

  _test('the Analyse tab follows the Blend target set after it was built',
      (tester, rig) async {
    await rig.pump(tester);
    await _tab(tester, 'gas-tab-analyse');
    expect(_key('desired-mix-32-0'), findsNothing);

    await _tab(tester, 'gas-tab-blend');
    rig.blend.setTargetMix(32, 0);
    await tester.pump();
    await _tab(tester, 'gas-tab-analyse');

    expect(_key('desired-mix-32-0'), findsOneWidget);
  });

  testWidgets('gasNavItem shows the dot only when connected and not selected',
      (tester) async {
    Future<bool> dotFor(bool connected, bool selected, bool ok) async {
      final item = gasNavItem(
          connected: connected, okRunning: ok, selected: selected);
      expect(item.label, 'Gas');
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const []),
        home: Scaffold(body: _navItemIcon(item)),
      ));
      return find.byKey(const ValueKey('nav-gas-dot')).evaluate().isNotEmpty;
    }

    expect(await dotFor(true, false, false), isTrue);
    expect(await dotFor(true, true, false), isFalse);
    expect(await dotFor(false, false, false), isFalse);
    expect(await dotFor(true, false, true), isTrue);
  });

  _test('the embedded log has no app bar but keeps Export',
      (tester, rig) async {
    await rig.pump(tester);
    await _tab(tester, 'gas-tab-log');
    expect(find.byType(AppBar), findsNothing);
    expect(_key('analysis-log-export'), findsOneWidget);
  });
}
