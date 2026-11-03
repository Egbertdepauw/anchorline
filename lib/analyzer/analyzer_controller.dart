/// Live gas-analyzer session state, independent of any widget.
///
/// Consumes an [AnalyzerTransport]: parses every line with
/// [parseSoloLine], feeds [StabilityDetector], keeps the latest reading
/// and a rolling history for the chart, and raises [noDataHint] when a
/// connected analyzer stays silent (usually "Send data to USB" is off or
/// printer mode is on).
///
/// Time base: every parsed line is stamped with real elapsed time since
/// [AnalyzerController.connect], read from a monotonic clock (a
/// [Stopwatch] by default, injectable for tests). The stability detector
/// and [AnalyzerController.history] both work on that time, so any output
/// rate works (the SOLO trimix sends ~5 lines per second, #127). The
/// device's own timestamps are not used: its clock can be far off.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hold_detector.dart' show kHoldSilence;
import 'protocol/analyzer_reading.dart';
import 'protocol/solo_line_parser.dart';
import 'stability.dart';
import 'transport/analyzer_transport.dart';

/// One chart point. [seconds] is elapsed time since connect.
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
    Duration Function()? elapsed,
  }) : _detector = detector ?? StabilityDetector(),
       _elapsed = elapsed ?? _stopwatchElapsed();

  /// A monotonic clock: a started [Stopwatch]'s elapsed time.
  static Duration Function() _stopwatchElapsed() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// How long a connected analyzer may stay silent before [noDataHint].
  final Duration noDataTimeout;

  /// Span of [history], in elapsed time.
  final Duration historyWindow;

  final StabilityDetector _detector;

  /// Monotonic time source; only differences matter.
  final Duration Function() _elapsed;

  /// [_elapsed] at the start of the current session.
  Duration _sessionStart = Duration.zero;

  /// When the previous data line of this session arrived, on the session
  /// clock; null before the first one.
  Duration? _lastLineAt;

  AnalyzerTransport? _transport;
  StreamSubscription<String>? _linesSub;
  StreamSubscription<AnalyzerConnectionStatus>? _statusSub;
  Timer? _watchdog;

  AnalyzerReading? _latest;
  final List<AnalyzerHistoryPoint> _history = [];
  double _nowSeconds = 0;
  bool _noDataHint = false;
  bool _hasHadData = false;
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

  /// Elapsed seconds of the newest history point; the chart's "now".
  double get historyNowSeconds => _nowSeconds;

  /// True while connected and no line has arrived for [noDataTimeout].
  bool get noDataHint => _noDataHint;

  /// True once a data line has arrived in this session (since the last
  /// [connect]). A SOLO that has streamed and then goes quiet is on hold
  /// (OK was pressed), not misconfigured: the screen shows the "no data is
  /// arriving" setup hint only while this is false.
  bool get hasHadData => _hasHadData;

  /// Starts a session on [transport]. Any previous session is closed and
  /// its transport disposed. The controller takes ownership of
  /// [transport] and disposes it on [disconnect] / [dispose].
  Future<void> connect(AnalyzerTransport transport) async {
    await disconnect();
    _transport = transport;
    _latest = null;
    _history.clear();
    _nowSeconds = 0;
    _sessionStart = _elapsed();
    _lastLineAt = null;
    _hasHadData = false;
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
    final now = _elapsed() - _sessionStart;
    // The SOLO only goes quiet this long when OK suspended it, so this line
    // is a resume: a new cylinder's gas. The OK logger restarts its record
    // window at the same moment (HoldDetector), so the pill must too, or it
    // says STABLE on readings the record would not accept yet.
    final last = _lastLineAt;
    if (last != null && now - last >= kHoldSilence) _detector.reset();
    _lastLineAt = now;
    _hasHadData = true;
    _detector.add(reading.o2, reading.he, elapsed: now);
    _nowSeconds = now.inMicroseconds / Duration.microsecondsPerSecond;
    _history.add(AnalyzerHistoryPoint(
      seconds: _nowSeconds,
      o2: reading.o2 ?? double.nan,
      he: reading.he ?? double.nan,
    ));
    final keepFrom = _nowSeconds -
        historyWindow.inMicroseconds / Duration.microsecondsPerSecond;
    var drop = 0;
    while (drop < _history.length && _history[drop].seconds < keepFrom) {
      drop++;
    }
    if (drop > 0) _history.removeRange(0, drop);
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
