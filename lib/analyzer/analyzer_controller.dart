/// Live gas-analyzer session state, independent of any widget.
///
/// Consumes an [AnalyzerTransport]: parses every line with
/// [parseSoloLine], feeds [StabilityDetector], keeps the latest reading
/// and a rolling history for the chart, and raises [noDataHint] when a
/// connected analyzer stays silent (usually "Send data to USB" is off or
/// printer mode is on).
///
/// Time base: the SOLO sends one line per second, so samples are spaced
/// at a nominal 1 s, both for the stability detector (its default when no
/// timestamp is passed) and for [history]. This keeps the controller free
/// of wall-clock reads and makes it deterministic under fake timers.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protocol/analyzer_reading.dart';
import 'protocol/solo_line_parser.dart';
import 'stability.dart';
import 'transport/analyzer_transport.dart';

/// One chart point. [seconds] counts samples since connect (1 Hz nominal).
class AnalyzerHistoryPoint {
  const AnalyzerHistoryPoint({
    required this.seconds,
    required this.o2,
    required this.he,
  });

  final double seconds;

  /// O2 %, NaN on a sensor error.
  final double o2;

  /// He %, NaN on a sensor error.
  final double he;
}

class AnalyzerController extends ChangeNotifier {
  AnalyzerController({
    this.noDataTimeout = const Duration(seconds: 4),
    this.historyWindow = const Duration(minutes: 2),
    StabilityDetector? detector,
  }) : _detector = detector ?? StabilityDetector();

  /// How long a connected analyzer may stay silent before [noDataHint].
  final Duration noDataTimeout;

  /// Span of [history] (at the nominal 1 Hz rate).
  final Duration historyWindow;

  final StabilityDetector _detector;

  AnalyzerTransport? _transport;
  StreamSubscription<String>? _linesSub;
  StreamSubscription<AnalyzerConnectionStatus>? _statusSub;
  Timer? _watchdog;

  AnalyzerReading? _latest;
  final List<AnalyzerHistoryPoint> _history = [];
  int _sampleCount = 0;
  bool _noDataHint = false;
  bool _disposed = false;

  /// The transport of the current session, or null when not in a session.
  AnalyzerTransport? get transport => _transport;

  AnalyzerConnectionStatus get status =>
      _transport?.status ?? AnalyzerConnectionStatus.disconnected;

  bool get isConnected => status == AnalyzerConnectionStatus.connected;

  bool get isBusy =>
      status == AnalyzerConnectionStatus.connecting ||
      status == AnalyzerConnectionStatus.connected;

  String? get errorMessage => _transport?.errorMessage;

  /// The most recent parsed reading, or null before the first one.
  AnalyzerReading? get latest => _latest;

  /// Stability state after the most recent reading.
  ReadingStability get stability => _detector.state;

  /// Rolling history, oldest first, at most [historyWindow] long.
  List<AnalyzerHistoryPoint> get history => List.unmodifiable(_history);

  /// Seconds (sample count) of the newest history point; the chart's
  /// "now".
  double get historyNowSeconds => _sampleCount.toDouble();

  /// True while connected and no line has arrived for [noDataTimeout].
  bool get noDataHint => _noDataHint;

  /// Starts a session on [transport]. Any previous session is closed and
  /// its transport disposed. The controller takes ownership of
  /// [transport] and disposes it on [disconnect] / [dispose].
  Future<void> connect(AnalyzerTransport transport) async {
    await disconnect();
    _transport = transport;
    _latest = null;
    _history.clear();
    _sampleCount = 0;
    _noDataHint = false;
    _detector.reset();
    _linesSub = transport.lines.listen(_onLine);
    _statusSub = transport.statusChanges.listen(_onStatus);
    _notify();
    await transport.connect();
    if (transport.status == AnalyzerConnectionStatus.connected) {
      _armWatchdog();
    }
  }

  /// Ends the session and disposes its transport. The last reading and
  /// history stay visible until the next [connect].
  Future<void> disconnect() async {
    final t = _transport;
    if (t == null) return;
    _watchdog?.cancel();
    _watchdog = null;
    _noDataHint = false;
    await t.disconnect();
    // Not awaited: cancelling a broadcast subscription returns a root-zone
    // future, which never completes under the fake clock of widget tests.
    // Nothing here depends on the cancel having finished.
    unawaited(_linesSub?.cancel());
    unawaited(_statusSub?.cancel());
    _linesSub = null;
    _statusSub = null;
    _transport = null;
    await t.dispose();
    _notify();
  }

  void _onLine(String line) {
    final reading = parseSoloLine(line);
    if (reading == null) return; // banner / garbage: not data
    _latest = reading;
    _detector.add(reading.o2, reading.he);
    _sampleCount++;
    _history.add(AnalyzerHistoryPoint(
      seconds: _sampleCount.toDouble(),
      o2: reading.o2 ?? double.nan,
      he: reading.he ?? double.nan,
    ));
    final keepFrom = _sampleCount - historyWindow.inSeconds;
    while (_history.isNotEmpty && _history.first.seconds <= keepFrom) {
      _history.removeAt(0);
    }
    _noDataHint = false;
    _armWatchdog();
    _notify();
  }

  void _onStatus(AnalyzerConnectionStatus s) {
    if (s == AnalyzerConnectionStatus.connected) {
      _armWatchdog();
    } else {
      _watchdog?.cancel();
      _watchdog = null;
      _noDataHint = false;
    }
    _notify();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(noDataTimeout, () {
      if (isConnected && !_noDataHint) {
        _noDataHint = true;
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _linesSub?.cancel();
    _statusSub?.cancel();
    final t = _transport;
    if (t != null) {
      // Fire and forget: dispose() can't be async.
      unawaited(t.dispose());
    }
    super.dispose();
  }
}
