import 'dart:async';

import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// A SOLO line as the trimix model prints it.
String _line(String o2, String he) =>
    'He  ${he.padLeft(5)} %  O2  ${o2.padLeft(5)} %  '
    'Ti  21.4 ~C  1013.2 hPa   2026/11/03 15:21:00';

/// A transport the test drives: lines, status, and a connect that can wait
/// or fail.
class _FakeSolo implements AnalyzerTransport {
  _FakeSolo({this.failWith, this.gate});

  final String? failWith;

  /// While set, connect() waits for it (status stays "connecting").
  final Completer<void>? gate;

  final _lines = StreamController<String>.broadcast(sync: true);
  final _statuses =
      StreamController<AnalyzerConnectionStatus>.broadcast(sync: true);
  AnalyzerConnectionStatus _status = AnalyzerConnectionStatus.disconnected;
  String? _error;

  void emit(String line) => _lines.add(line);

  void _set(AnalyzerConnectionStatus s) {
    _status = s;
    _statuses.add(s);
  }

  @override
  String get name => 'USB';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  AnalyzerConnectionStatus get status => _status;
  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _statuses.stream;
  @override
  String? get errorMessage => _error;
  @override
  Future<void> connect() async {
    _set(AnalyzerConnectionStatus.connecting);
    await gate?.future;
    if (failWith != null) {
      _error = failWith;
      _set(AnalyzerConnectionStatus.error);
      return;
    }
    _set(AnalyzerConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async =>
      _set(AnalyzerConnectionStatus.disconnected);
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakeSolo solo;
  late AnalyzerSession session;

  /// Pumps the screen (no log, so no save section) on a [_FakeSolo].
  Future<void> pump(
    WidgetTester tester, {
    _FakeSolo? transport,
    Size size = const Size(400, 2400),
    double textScale = 1.0,
    ThemeData? theme,
    String? note,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = SettingsNotifier();
    await settings.load();
    solo = transport ?? _FakeSolo();
    session = AnalyzerSession(
      settings: settings,
      controller: fakeClockAnalyzerController(tester),
      transportOptions: [
        AnalyzerTransportOption(
            label: 'USB', create: () => solo, note: note),
        AnalyzerTransportOption(label: 'Demo', isDemo: true, create: () => solo),
      ],
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
          body: AnalyzerScreen(settings: settings, session: session)),
    ));
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(_key('analyzer-connect'));
    await tester.pump();
  }

  /// Streams [o2]/[he] once a second for [n] seconds.
  Future<void> stream(WidgetTester tester, String o2, String he, int n) async {
    for (var i = 0; i < n; i++) {
      solo.emit(_line(o2, he));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(_key(key)).data!;

  String statusText(WidgetTester tester) => textOf(tester, 'analyzer-status');

  /// Ends the session (cancels the controller's watchdog, which the test
  /// binding insists on) and leaves the screen.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await session.disconnect();
  }

  testWidgets(
      'before connecting: Source and Connect in the strip, dashes and NO DATA',
      (tester) async {
    await pump(tester);
    expect(_key('analyzer-transport'), findsOneWidget);
    expect(_key('analyzer-connect'), findsOneWidget);
    expect(_key('analyzer-disconnect'), findsNothing);
    expect(statusText(tester), 'Not connected');
    expect(textOf(tester, 'analyzer-o2'), '--.-');
    expect(textOf(tester, 'analyzer-he'), '--.-');
    expect(textOf(tester, 'analyzer-n2'), '--.-');
    expect(textOf(tester, 'analyzer-mix'), '—');
    expect(find.text('NO DATA'), findsOneWidget);
  });

  testWidgets('connected: transport name and Disconnect', (tester) async {
    await pump(tester);
    await connect(tester);
    expect(statusText(tester), contains('SOLO connected · '));
    expect(statusText(tester), 'SOLO connected · USB');
    expect(_key('analyzer-disconnect'), findsOneWidget);
    expect(_key('analyzer-connect'), findsNothing);
    expect(_key('analyzer-transport'), findsNothing);
    await end(tester);
  });

  testWidgets('stable 20.6/33.8 shows Tx20.6/33.8, 20.6, 33.8, 45.6 and STABLE',
      (tester) async {
    await pump(tester);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 30);
    expect(textOf(tester, 'analyzer-mix'), 'Tx20.6/33.8');
    expect(textOf(tester, 'analyzer-o2'), '20.6');
    expect(textOf(tester, 'analyzer-he'), '33.8');
    expect(textOf(tester, 'analyzer-n2'), '45.6');
    expect(find.text('STABLE'), findsOneWidget);
    await end(tester);
  });

  testWidgets('a sensor error shows ***.* and SENSOR ERROR', (tester) async {
    await pump(tester);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 2);
    solo.emit(_line('***.*', '33.8'));
    await tester.pump();
    expect(textOf(tester, 'analyzer-o2'), '***.*');
    expect(textOf(tester, 'analyzer-n2'), '***.*');
    expect(find.text('SENSOR ERROR'), findsOneWidget);
    await end(tester);
  });

  testWidgets('connecting shows Connecting…', (tester) async {
    final gate = Completer<void>();
    await pump(tester, transport: _FakeSolo(gate: gate));
    await connect(tester);
    expect(statusText(tester), 'Connecting…');
    expect(_key('analyzer-connect'), findsNothing);
    gate.complete();
    await tester.pump();
    expect(statusText(tester), 'SOLO connected · USB');
    await end(tester);
  });

  testWidgets(
      'a failed connect shows the error banner and the strip goes back to '
      'Not connected', (tester) async {
    await pump(tester, transport: _FakeSolo(failWith: 'Port is busy.'));
    await connect(tester);
    expect(_key('analyzer-error-banner'), findsOneWidget);
    expect(find.text('Port is busy.'), findsOneWidget);
    expect(statusText(tester), 'Not connected');
    expect(_key('analyzer-connect'), findsOneWidget);
    await end(tester);
  });

  testWidgets('a settling reading shows SETTLING', (tester) async {
    await pump(tester);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 3);
    expect(find.text('SETTLING'), findsOneWidget);
    await end(tester);
  });

  testWidgets(
      'after Disconnect the last reading stays and the strip shows Source '
      'and Connect', (tester) async {
    await pump(tester);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 3);
    await tester.tap(_key('analyzer-disconnect'));
    await tester.pump();
    expect(statusText(tester), 'Not connected');
    expect(_key('analyzer-transport'), findsOneWidget);
    expect(_key('analyzer-connect'), findsOneWidget);
    expect(textOf(tester, 'analyzer-mix'), 'Tx20.6/33.8');
    expect(textOf(tester, 'analyzer-o2'), '20.6');
    await end(tester);
  });

  testWidgets(
      'a SOLO that never sent a line shows the no-data banner; one that '
      'streamed and went quiet does not', (tester) async {
    await pump(tester);
    await connect(tester);
    expect(_key('analyzer-no-data-hint'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(_key('analyzer-no-data-hint'), findsOneWidget);
    expect(
        find.text('No data is arriving. On the SOLO set Menu → Preferences → '
            '"Send data to USB" above zero, and turn printer mode off.'),
        findsOneWidget);
    await end(tester);

    await pump(tester);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 2);
    await tester.pump(const Duration(seconds: 6));
    expect(_key('analyzer-no-data-hint'), findsNothing);
    await end(tester);
  });

  testWidgets('the Android note is a caption while the source is not connected',
      (tester) async {
    await pump(tester, note: 'The phone powers the analyzer.');
    expect(_key('analyzer-transport-note'), findsOneWidget);
    await connect(tester);
    expect(_key('analyzer-transport-note'), findsNothing);
    await end(tester);
  });

  group('planning', () {
    testWidgets('keeps today\'s values and the new labels', (tester) async {
      await pump(tester);
      await connect(tester);
      await stream(tester, '20.6', '33.8', 30);
      String tile(String key) => tester
          .widgetList<Text>(find.descendant(
              of: _key(key), matching: find.byType(Text)))
          .map((t) => t.data ?? t.textSpan!.toPlainText())
          .join(' | ');
      // MOD 1.1 is the diluent tile, with an accent tag.
      expect(tile('analyzer-mod-1.1'), 'MOD 1.1 DIL | 42 m');
      expect(tile('analyzer-mod-1.4'), 'MOD 1.4 | 57 m');
      expect(tile('analyzer-mod-1.6'), 'MOD 1.6 | 66 m');
      expect(tile('analyzer-end'), 'END | 35 m');
      expect(tile('analyzer-density'), 'DENSITY | 6.0 g/L');
      expect(tile('analyzer-min-depth'), 'MIN. DEPTH | surface');
      expect(tile('analyzer-temp'), 'GAS TEMP | 21.4 °C');
      expect(tile('analyzer-baro'), 'AMBIENT | 1013 hPa');
      await end(tester);
    });

    testWidgets('before data every planning value is a dash', (tester) async {
      await pump(tester);
      for (final k in [
        'analyzer-mod-1.4',
        'analyzer-end',
        'analyzer-density',
        'analyzer-min-depth',
        'analyzer-temp',
        'analyzer-baro',
      ]) {
        expect(
            find.descendant(of: _key(k), matching: find.text('–')),
            findsOneWidget,
            reason: k);
      }
    });

    testWidgets(
        'on a phone the footnote is behind the info button; on wide it is '
        'shown', (tester) async {
      await pump(tester);
      expect(_key('analyzer-planning-footnote'), findsNothing);
      await tester.tap(_key('analyzer-planning-info'));
      await tester.pump();
      expect(
          tester.widget<Text>(_key('analyzer-planning-footnote')).data,
          'END and density at the 1.4 MOD. Seawater, 10 m/bar. '
          'END counts O₂ and N₂ as narcotic. '
          'Orientation only — plan with your own tools.');
      await tester.tap(_key('analyzer-planning-info'));
      await tester.pump();
      expect(_key('analyzer-planning-footnote'), findsNothing);

      await pump(tester, size: const Size(1200, 1000));
      expect(_key('analyzer-planning-footnote'), findsOneWidget);
      expect(_key('analyzer-planning-info'), findsNothing);
    });
  });

  testWidgets('the trend starts collapsed and opens on tap', (tester) async {
    await pump(tester);
    expect(_key('analyzer-trend-chart'), findsNothing);
    expect(find.text('Trend, last 2 minutes'), findsOneWidget);
    await tester.tap(_key('analyzer-trend'));
    await tester.pump();
    expect(_key('analyzer-trend-chart'), findsOneWidget);
    await tester.tap(_key('analyzer-trend'));
    await tester.pump();
    expect(_key('analyzer-trend-chart'), findsNothing);
  });

  testWidgets('no overflow at 320×568 and text scale 1.3', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 1.3);
    await connect(tester);
    await stream(tester, '20.6', '33.8', 30);
    await tester.tap(_key('analyzer-planning-info'));
    await tester.tap(_key('analyzer-trend'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_key('analyzer-trend-chart'), findsOneWidget);
    await end(tester);
  });

  testWidgets('renders in every theme', (tester) async {
    for (final def in AppThemes.all) {
      await pump(tester, theme: def.themeData);
      await connect(tester);
      await stream(tester, '20.6', '33.8', 3);
      expect(tester.takeException(), isNull, reason: def.id);
      await end(tester);
    }
  });
}
