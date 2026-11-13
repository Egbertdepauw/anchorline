import 'dart:async';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/usb_ok_logger.dart';
import 'package:ccrlogger/sync/cloud/sync_health_service.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport_options.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:ccrlogger/ui/components/tab_top_bar.dart';
import 'package:ccrlogger/ui/screens/gas_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:ccrlogger/ui/widgets/sync_health_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_label_printer.dart';
import '../../_helpers/fake_open_blends_dao.dart';

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

/// A sync-health RPC that reports one slot holding [retainedMb] of WAL.
class _FakeHealthClient implements SyncHealthClient {
  _FakeHealthClient(this.retainedMb);

  final int retainedMb;

  @override
  Future<List<SyncHealthSlot>> fetch() async => [
        SyncHealthSlot(
          slotName: 'powersync_test',
          active: true,
          walStatus: 'reserved',
          retainedMb: retainedMb,
        ),
      ];
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
      {bool logOnOk = false,
      ThemeData? theme,
      Size size = const Size(600, 3200),
      LabelPrintService? labelPrinting,
      OpenBlendsDaoLike? openBlendsDao,
      Widget Function(Widget gas)? around}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = SettingsNotifier();
    await settings.load();
    if (logOnOk) await settings.setAnalyzerLogOnOk(true);
    blend = BlendNotifier(settings: settings);
    session = AnalyzerSession(
      settings: settings,
      analysesDao: dao,
      labelPrinting: labelPrinting,
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
    final gas = GasScreen(
      blend: blend,
      settings: settings,
      session: session,
      analysesDao: dao,
      openBlendsDao: openBlendsDao,
      labelPrinting: labelPrinting,
      onHome: () => homeTaps++,
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: around == null ? gas : around(gas),
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

/// A gas blended to [target] and not analysed yet.
Future<void> _addOpenBlend(FakeOpenBlendsDao dao, DesiredMix target) =>
    dao.add(NewOpenBlend(
      target: target,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 3,
      role: GasRole.bailout,
      blendedBy: null,
      blendedAt: DateTime(2026, 11, 13),
    ));

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

  _test('gas tab shows the open count', (tester, rig) async {
    OpenBlend b(String id) => OpenBlend(
          id: id,
          target: const DesiredMix(18, 45),
          targetPressureBar: 230,
          residual: const DesiredMix(21, 0),
          residualPressureBar: 0,
          topoff: const DesiredMix(21, 0),
          waterCapacityL: 12,
          role: GasRole.bailout,
          blendedBy: null,
          blendedAt: DateTime(2026, 11, 13),
        );
    final blends = FakeOpenBlendsDao(blends: [b('x'), b('y')]);
    await rig.pump(tester, openBlendsDao: blends);
    expect(find.descendant(of: _key('gas-tab-blend-count'),
        matching: find.text('2')), findsOneWidget);
    await blends.dismiss('x');
    await blends.dismiss('y');
    await tester.pump();
    expect(_key('gas-tab-blend-count'), findsNothing);
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

  _test('the Analyse tab follows the open blends added after it was built',
      (tester, rig) async {
    final blends = FakeOpenBlendsDao();
    await rig.pump(tester, openBlendsDao: blends);
    await _tab(tester, 'gas-tab-analyse');
    expect(_key('desired-mix-32-0'), findsNothing);

    await _tab(tester, 'gas-tab-blend');
    await _addOpenBlend(blends, const DesiredMix(32, 0));
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

  _test('"Change desired mix" on the wide layout stays on the Analyse tab',
      (tester, rig) async {
    // A Mac at the bench, or an iPhone in landscape: the save card is the
    // right-hand column.
    const size = Size(1200, 800);
    final blends = FakeOpenBlendsDao();
    await rig.pump(
      tester,
      size: size,
      openBlendsDao: blends,
      labelPrinting: LabelPrintService(
        render: (label) async => LabelBitmap.blank(384, 240),
        printerFor: (_) => FakeLabelPrinter(),
        scanner: FakeLabelPrinterScanner(),
        printerId: () => 'dev-1',
        use14ForDeeperMixes: () => false,
      ),
    );
    await _addOpenBlend(blends, const DesiredMix(50, 0));
    await tester.pump();
    await _tab(tester, 'gas-tab-analyse');
    await rig.connect(tester);
    await rig.feed(tester, 32.0, 0);
    // EAN50 against a 32 % reading: a hard mismatch.
    await tester.tap(_key('desired-mix-50-0'));
    await tester.pumpAndSettle();
    await tester.tap(_key('analysis-save-print'));
    await tester.pumpAndSettle();
    expect(find.text('Mix does not conform to analysis'), findsOneWidget);

    await tester.tap(_key('mix-mismatch-change'));
    await tester.pumpAndSettle();

    final tabs =
        DefaultTabController.of(tester.element(find.byType(TabBarView)));
    expect(tabs.index, 1, reason: 'still on Analyse');
    expect(rig.dao.added, isEmpty);
    final picker = tester.getRect(find.byType(DesiredMixPicker));
    final bar = tester.getRect(_key('analysis-action-bar'));
    expect(picker.left, greaterThanOrEqualTo(0));
    expect(picker.right, lessThanOrEqualTo(size.width));
    expect(picker.top, greaterThanOrEqualTo(0));
    expect(picker.bottom, lessThanOrEqualTo(bar.top));
  });

  group('under the sync-health banner', () {
    // An iPhone's status bar.
    const inset = 59.0;

    /// The Gas destination as the shell lays it out: no shell app bar, the
    /// banner column as its body.
    Widget shell(SyncHealthService health, Widget gas) => Scaffold(
          body: SyncHealthBannerColumn(service: health, child: gas),
        );

    _test('a showing banner takes the status-bar inset, and the top bar '
        'starts right under it', (tester, rig) async {
      final health = SyncHealthService(_FakeHealthClient(300));
      addTearDown(health.dispose);
      await health.refresh();
      tester.view.padding = const FakeViewPadding(top: inset);
      await rig.pump(tester, around: (gas) => shell(health, gas));

      final banner = tester.getRect(find.byType(SyncHealthBanner));
      final bar = tester.getRect(find.byType(TabTopBar));
      expect(banner.top, 0);
      expect(banner.height, greaterThan(inset));
      expect(bar.top, banner.bottom);
      expect(bar.height, 56, reason: 'no second inset');
    });

    _test('with the banner hidden the top bar takes the inset itself',
        (tester, rig) async {
      // Never polled: nothing to show.
      final health = SyncHealthService(_FakeHealthClient(300));
      addTearDown(health.dispose);
      tester.view.padding = const FakeViewPadding(top: inset);
      await rig.pump(tester, around: (gas) => shell(health, gas));

      expect(tester.getSize(find.byType(SyncHealthBanner)).height, 0);
      final bar = tester.getRect(find.byType(TabTopBar));
      expect(bar.top, 0);
      expect(bar.height, 56 + inset);
    });

    _test('the banner showing later keeps the tab state and drops the inset',
        (tester, rig) async {
      final health = SyncHealthService(_FakeHealthClient(300));
      addTearDown(health.dispose);
      tester.view.padding = const FakeViewPadding(top: inset);
      await rig.pump(tester, around: (gas) => shell(health, gas));
      await _tab(tester, 'gas-tab-log');

      await health.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(GasAnalysisLogScreen), findsOneWidget,
          reason: 'still on the Log tab');
      final banner = tester.getRect(find.byType(SyncHealthBanner));
      expect(tester.getRect(find.byType(TabTopBar)).top, banner.bottom);
      expect(tester.getSize(find.byType(TabTopBar)).height, 56);
    });
  });
}
