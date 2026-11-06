import 'dart:async';

import 'package:ccrlogger/analyzer/analyzer_controller.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport_options.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';

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
  final dao = FakeGasAnalysesDao();
  final awake = <bool>[];
  final solos = <_FakeSolo>[];
  int loggersBuilt = 0;
  late SettingsNotifier settings;
  late AnalyzerController controller;
  late AnalyzerSession session;
  late BuildContext context;

  Future<void> start(
    WidgetTester tester, {
    bool withDao = true,
    bool logOnOk = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsNotifier();
    await settings.load();
    if (logOnOk) await settings.setAnalyzerLogOnOk(true);
    controller = AnalyzerController(elapsed: fakeElapsed(tester));
    session = AnalyzerSession(
      settings: settings,
      analysesDao: withDao ? dao : null,
      controller: controller,
      keepAwake: (on) async => awake.add(on),
      okLoggerFactory: () {
        loggersBuilt++;
        return buildOkLogger(
          dao: dao,
          elapsed: fakeElapsed(tester),
          tickInterval: null,
        );
      },
      transportOptions: [
        AnalyzerTransportOption(
          label: 'Bench',
          create: () {
            final s = _FakeSolo();
            solos.add(s);
            return s;
          },
        ),
        AnalyzerTransportOption(
          label: 'Demo',
          isDemo: true,
          create: () => _FakeSolo(),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    ));
  }

  bool _sessionDisposed = false;

  void disposeSession() {
    _sessionDisposed = true;
    session.dispose();
  }

  Future<void> end() async {
    if (!_sessionDisposed) session.dispose();
    controller.dispose();
  }
}

void _test(
  String description,
  Future<void> Function(WidgetTester tester, _Rig r) body,
) {
  testWidgets(description, (tester) async {
    final r = _Rig();
    try {
      await body(tester, r);
    } finally {
      await r.end();
    }
  });
}

void main() {
  group('the logger', () {
    _test('exists only with the switch on, a log and a real connection',
        (tester, r) async {
      await r.start(tester);
      expect(r.session.okLogger, isNull);
      await r.session.connectSelected(r.context);
      expect(r.session.okLogger, isNotNull);
      expect(r.session.okRunning, isTrue);
      expect(r.loggersBuilt, 1);

      await r.settings.setAnalyzerLogOnOk(false);
      expect(r.session.okLogger, isNull);
      await r.settings.setAnalyzerLogOnOk(true);
      expect(r.session.okLogger, isNotNull);
      expect(r.loggersBuilt, 2);
    });

    _test('is never built with the switch off', (tester, r) async {
      await r.start(tester, logOnOk: false);
      await r.session.connectSelected(r.context);
      expect(r.controller.isConnected, isTrue);
      expect(r.session.okLogger, isNull);
      expect(r.loggersBuilt, 0);
    });

    _test('is never built without a log to save to', (tester, r) async {
      await r.start(tester, withDao: false);
      await r.session.connectSelected(r.context);
      expect(r.session.okLogger, isNull);
      expect(r.loggersBuilt, 0);
    });

    _test('is never built for the demo source', (tester, r) async {
      await r.start(tester);
      r.session.select(1);
      await r.session.connectSelected(r.context);
      expect(r.controller.isConnected, isTrue);
      expect(r.session.sessionIsDemo, isTrue);
      expect(r.session.sourceIsDemo, isTrue);
      expect(r.session.okLogger, isNull);
      expect(r.awake, isEmpty);
    });

    _test('goes when the connection does and is rebuilt on the next',
        (tester, r) async {
      await r.start(tester);
      await r.session.connectSelected(r.context);
      final first = r.session.okLogger;
      await r.session.disconnect();
      expect(r.session.okLogger, isNull);

      await r.session.connectSelected(r.context);
      expect(r.session.okLogger, isNotNull);
      expect(identical(r.session.okLogger, first), isFalse);
      expect(r.loggersBuilt, 2);
      expect(r.solos, hasLength(2), reason: 'a new transport per session');
    });

    _test('readings do not rebuild it', (tester, r) async {
      await r.start(tester);
      await r.session.connectSelected(r.context);
      for (var i = 0; i < 6; i++) {
        r.solos.single.emitLine(_line(32, 0));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(r.loggersBuilt, 1);
    });
  });

  group('the wakelock', () {
    _test('is taken when the logger starts and released when it stops',
        (tester, r) async {
      await r.start(tester);
      expect(r.awake, isEmpty);
      await r.session.connectSelected(r.context);
      expect(r.awake, [true]);
      await r.settings.setAnalyzerLogOnOk(false);
      expect(r.awake, [true, false]);
      await r.settings.setAnalyzerLogOnOk(true);
      expect(r.awake, [true, false, true]);
      await r.session.disconnect();
      expect(r.awake, [true, false, true, false]);
    });

    _test('disposing the session releases it', (tester, r) async {
      await r.start(tester);
      await r.session.connectSelected(r.context);
      r.disposeSession();
      expect(r.awake, [true, false]);
    });
  });

  group('the session', () {
    _test('stays connected when no screen is showing it', (tester, r) async {
      await r.start(tester);
      await r.session.connectSelected(r.context);
      // Nothing listens to the session but the test; the connection and the
      // logger live on, and readings still arrive.
      r.solos.single.emitLine(_line(32, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(r.controller.isConnected, isTrue);
      expect(r.controller.latest, isNotNull);
      expect(r.session.okRunning, isTrue);
    });

    _test('notifies on controller and settings changes', (tester, r) async {
      await r.start(tester, logOnOk: false);
      var n = 0;
      r.session.addListener(() => n++);
      await r.session.connectSelected(r.context);
      expect(n, greaterThan(0));
      n = 0;
      await r.settings.setAnalyzerLogOnOk(true);
      expect(n, greaterThan(0));
      n = 0;
      r.solos.single.emitLine(_line(32, 0));
      expect(n, greaterThan(0));
    });

    _test('select is ignored while a session is on', (tester, r) async {
      await r.start(tester);
      expect(r.session.selected, 0);
      r.session.select(1);
      expect(r.session.selected, 1);
      r.session.select(0);
      await r.session.connectSelected(r.context);
      r.session.select(1);
      expect(r.session.selected, 0);
      await r.session.disconnect();
      r.session.select(1);
      expect(r.session.selected, 1);
    });

    _test('held means the logger watches and the SOLO went quiet',
        (tester, r) async {
      await r.start(tester);
      await r.session.connectSelected(r.context);
      expect(r.session.held, isFalse, reason: 'never streamed');
      r.solos.single.emitLine(_line(32, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(r.session.held, isFalse, reason: 'still streaming');
      await tester.pump(const Duration(seconds: 5));
      expect(r.controller.noDataHint, isTrue);
      expect(r.session.held, isTrue);

      await r.settings.setAnalyzerLogOnOk(false);
      expect(r.session.held, isFalse, reason: 'no logger, nothing held');
    });
  });
}
