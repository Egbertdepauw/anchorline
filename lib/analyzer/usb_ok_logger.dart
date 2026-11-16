/// Log on OK for a SOLO on a USB cable (issue #113).
///
/// [UsbOkLogger] joins the pieces that turn an OK press into a log entry:
/// the live lines of an [AnalyzerTransport] go to a [HoldDetector]; a
/// detected hold becomes a [BridgeRecord] and goes through [recordToAnalysis]
/// with the diver's current setup; the analysis is saved; the label is
/// printed when the pocket print rules allow; and the outcome is reported on
/// [UsbOkLogger.results].
///
/// The entry is saved first, flagged for sign-off, and the flag is cleared
/// only after the label has printed. So a crash or a printer that is off
/// leaves a saved entry that still asks for a sign-off, never a label with no
/// entry and never an entry that claims a label that did not print.
///
/// Pure Dart: `dart:async` only, no Flutter, no database. The DAO is passed
/// in as functions, the clocks are injectable, and a test drives it with
/// [UsbOkLogger.tick] instead of a timer.
library;

import 'dart:async';

import '../data/models/gas_analysis.dart';
import '../data/models/open_blend.dart';
import 'bridge/bridge_protocol.dart';
import 'bridge/record_to_analysis.dart';
import 'hold_detector.dart';
import 'ok_logger.dart';
import 'ok_record_processor.dart';
import 'transport/analyzer_transport.dart';

export 'ok_logger.dart';

/// How often the logger asks the hold detector whether OK was pressed. The
/// screen's logger uses this; a test passes null to drive [UsbOkLogger.tick]
/// itself.
const Duration kOkTickInterval = Duration(milliseconds: 200);

/// A gap between two timer callbacks longer than this means the isolate or
/// the process was stalled (Android freezing a cached app, a long jank), not
/// that the SOLO went quiet.
const Duration kStallGap = Duration(seconds: 1);

/// After a stall the detector is not asked for a hold for this long (on the
/// logger's clock). The lines that piled up during the stall are delivered
/// in that time and bring their fresh delivery times, which clears the
/// "silence" the stall made. A real suspend still fires on the first tick
/// after the grace.
const Duration kStallGrace = Duration(seconds: 1);

/// Detects the OK presses on a USB transport and logs them. See the library
/// comment.
class UsbOkLogger implements OkLogger {
  UsbOkLogger({
    required Future<bool> Function(String id, NewGasAnalysis a) save,
    required Future<void> Function(String id) markComplete,
    Future<void> Function(GasAnalysis a, int copies)? printLabel,
    Future<bool> Function(OpenBlend blend, String analysisId)? closeBlend,
    Duration Function()? elapsed,
    DateTime Function()? now,
    Duration? tickInterval = kOkTickInterval,
    void Function(Object error, StackTrace stack)? onError,
  }) : _processor = OkRecordProcessor(
         save: save,
         markComplete: markComplete,
         printLabel: printLabel,
         closeBlend: closeBlend,
         onError: onError,
       ),
       _elapsed = elapsed ?? _stopwatchClock(),
       _now = now ?? DateTime.now,
       _tickInterval = tickInterval,
       _onError = onError;

  /// The save, print and mark-complete steps, shared with the bridge.
  final OkRecordProcessor _processor;
  final Duration Function() _elapsed;
  final DateTime Function() _now;
  final Duration? _tickInterval;
  final void Function(Object error, StackTrace stack)? _onError;

  /// The setup of the save card, asked for when a hold is handled. Null, or
  /// a provider that throws, means [LogOnOkSetup] with its defaults and one
  /// copy: the reading is still saved, flagged for sign-off, and nothing
  /// prints.
  @override
  OkSetup Function()? setupProvider;

  final HoldDetector _detector = HoldDetector();
  final StreamController<OkLogResult> _results =
      StreamController<OkLogResult>.broadcast();

  StreamSubscription<String>? _linesSub;
  StreamSubscription<AnalyzerConnectionStatus>? _statusSub;
  Timer? _timer;

  /// The holds are handled one after the other: each waits for the one
  /// before it, so a second OK during a slow save or print is not lost and
  /// the two never interleave. Handling a hold never throws, so the chain
  /// never breaks.
  Future<void> _chain = Future<void>.value();

  bool _disposed = false;

  /// The logger's clock at the previous timer callback; null before the
  /// first one after [attach].
  Duration? _lastTimerAt;

  /// The previous timer callback came more than [kStallGap] after the one
  /// before it.
  bool _lastTimerLagged = false;

  /// While set, and the clock is before it, the timer does not ask the
  /// detector for a hold: a stall just ended and the lines it held back are
  /// still on their way.
  Duration? _graceUntil;

  /// The last timer tick threw and it was reported; stays set until a tick
  /// works again, so a broken clock does not flood the results.
  bool _tickFailing = false;

  /// One event per OK press that was handled, also when it failed. Broadcast.
  @override
  Stream<OkLogResult> get results => _results.stream;

  /// Starts watching [t]: its lines go to the hold detector and any status
  /// other than connected resets it (the cable is gone, so a pending silence
  /// is not an OK press). Replaces a transport attached before, and starts
  /// from a clean detector. Does not connect or dispose [t].
  void attach(AnalyzerTransport t) {
    if (_disposed) return;
    detach();
    _linesSub = t.lines.listen(_onLine);
    _statusSub = t.statusChanges.listen(_onStatus);
    final interval = _tickInterval;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => _onTimer());
    }
  }

  /// Stops watching the transport and forgets the flow. A hold that is
  /// being handled finishes and is reported.
  void detach() {
    _timer?.cancel();
    _timer = null;
    _linesSub?.cancel();
    _linesSub = null;
    _statusSub?.cancel();
    _statusSub = null;
    _lastTimerAt = null;
    _lastTimerLagged = false;
    _graceUntil = null;
    _detector.detached();
  }

  /// Asks the detector, at the logger's clock, whether OK was pressed, and
  /// handles the hold if so. Call it yourself when the logger was made
  /// without a timer.
  ///
  /// This asks the detector at once. The periodic timer does not call it: it
  /// goes through the stall guard first (see [kStallGap]), and a caller that
  /// drives [tick] itself is responsible for its own pacing.
  void tick() => _tickAt(_elapsed());

  void _tickAt(Duration elapsed) {
    if (_disposed) return;
    final hold = _detector.tick(elapsed);
    if (hold != null) {
      _chain = _chain.then((_) => _handle(hold));
    }
  }

  /// Stops watching, lets a hold that is being handled finish (its result is
  /// still delivered) and closes [results].
  Future<void> dispose() async {
    if (_disposed) return;
    detach();
    _disposed = true;
    await _chain;
    await _results.close();
  }

  void _onLine(String line) => _detector.addLine(_elapsed(), line);

  void _onStatus(AnalyzerConnectionStatus status) {
    if (status != AnalyzerConnectionStatus.connected) _detector.detached();
  }

  /// What the periodic timer calls every `tickInterval`. Public so a test
  /// can play a timer that is late; the screen never calls it.
  void timerFired() => _onTimer();

  /// A timer callback must not throw: that would be an uncaught error in the
  /// zone. A failing tick is reported once per streak of failures.
  ///
  /// If the isolate stalled while the SOLO kept streaming, the periodic
  /// timer can run before the lines that queued up are delivered, and the
  /// detector would see a silence nobody caused: an OK press that was never
  /// made. A gap of more than [kStallGap] since the last callback therefore
  /// starts a grace of [kStallGrace] in which the detector is not asked.
  /// Lines keep going to the detector, and the detector is not reset: an OK
  /// pressed during the stall is still found by the first tick after the
  /// grace.
  ///
  /// The grace is for one stall. A callback that is late and directly
  /// follows another late one starts none: timers that stay throttled (App
  /// Nap, a covered window) would otherwise never tick the detector, and no
  /// press would be seen. The lines that piled up in a throttled period have
  /// been delivered by the time the next callback runs.
  void _onTimer() {
    try {
      final now = _elapsed();
      final last = _lastTimerAt;
      _lastTimerAt = now;
      final lagged = last != null && now - last > kStallGap;
      if (lagged && !_lastTimerLagged) {
        _graceUntil = now + kStallGrace;
      }
      _lastTimerLagged = lagged;
      final graceUntil = _graceUntil;
      if (graceUntil != null) {
        if (now < graceUntil) return;
        _graceUntil = null;
      }
      _tickAt(now);
      _tickFailing = false;
    } catch (e, st) {
      if (_tickFailing) return;
      _tickFailing = true;
      _report(e, st);
      _emit(
        const OkLogResult(
          code: FeedbackCode.error,
          text: 'LOG FAILED',
          analysisId: null,
          complete: false,
        ),
      );
    }
  }

  /// Hands a caught error to the owner's [onError]; whatever that does,
  /// it must not break the logger.
  void _report(Object error, StackTrace stack) {
    try {
      _onError?.call(error, stack);
    } catch (_) {}
  }

  void _emit(OkLogResult r) {
    if (!_results.isClosed) _results.add(r);
  }

  /// Handles one hold and reports it. Never throws.
  Future<void> _handle(DetectedHold hold) async {
    OkLogResult result;
    try {
      result = await _process(hold);
    } catch (e, st) {
      _report(e, st);
      // Nothing was saved (the steps after the save catch their own
      // failures), but the press must not vanish.
      result = const OkLogResult(
        code: FeedbackCode.error,
        text: 'LOG FAILED',
        analysisId: null,
        complete: false,
      );
    }
    _emit(result);
  }

  Future<OkLogResult> _process(DetectedHold hold) async {
    OkSetup setup;
    try {
      setup = setupProvider?.call() ?? kNoOkSetup;
    } catch (e, st) {
      _report(e, st);
      setup = kNoOkSetup;
    }

    final elapsed = _elapsed();
    final now = _now();
    final rid = now.microsecondsSinceEpoch.toString();
    final record = BridgeRecord(
      rid: rid,
      boot: 0,
      upMs: hold.heldAt.inMilliseconds,
      wallMs: 0,
      live: true,
      window: hold.window,
      heldLine: hold.heldLine,
    );
    return _processor.process(
      record: record,
      bridgeId: 'usb',
      source: CaptureSource.usbOk,
      clock: BridgeClock(boot: 0, upMs: elapsed.inMilliseconds),
      now: now,
      active: true,
      setup: setup,
    );
  }

  /// A monotonic clock that starts now.
  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
