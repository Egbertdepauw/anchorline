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

import '../analysis/gas_naming.dart';
import '../data/models/gas_analysis.dart';
import 'bridge/bridge_protocol.dart';
import 'bridge/record_to_analysis.dart';
import 'hold_detector.dart';
import 'transport/analyzer_transport.dart';

/// What the diver set up for the next OK, and how many labels to print.
typedef OkSetup = ({LogOnOkSetup setup, int copies});

/// The setup used when the screen has none to give.
const OkSetup _noSetup = (setup: LogOnOkSetup(), copies: 1);

/// How one OK press went, for the screen and the save card.
class OkLogResult {
  const OkLogResult({
    required this.code,
    required this.text,
    required this.analysisId,
    required this.complete,
  });

  /// The feedback: printed, saved, check, skipped or error.
  final FeedbackCode code;

  /// The feedback text, ASCII and at most [kFeedbackTextMax] characters
  /// (`EAN32`, `NOT STABLE`, `PRINT FAILED`, ...).
  final String text;

  /// The id of the saved row; null when nothing was saved.
  final String? analysisId;

  /// The row was saved with `needs_signoff = 0`: nothing is left for the
  /// diver to do (and the label printed, if a print was wanted).
  final bool complete;

  @override
  String toString() =>
      'OkLogResult($code, "$text", id: $analysisId, complete: $complete)';
}

/// Detects the OK presses on a USB transport and logs them. See the library
/// comment.
class UsbOkLogger {
  UsbOkLogger({
    required Future<bool> Function(String id, NewGasAnalysis a) save,
    required Future<void> Function(String id) markComplete,
    Future<void> Function(GasAnalysis a, int copies)? printLabel,
    Duration Function()? elapsed,
    DateTime Function()? now,
    Duration? tickInterval = const Duration(milliseconds: 200),
  }) : _save = save,
       _markComplete = markComplete,
       _printLabel = printLabel,
       _elapsed = elapsed ?? _stopwatchClock(),
       _now = now ?? DateTime.now,
       _tickInterval = tickInterval;

  final Future<bool> Function(String id, NewGasAnalysis a) _save;
  final Future<void> Function(String id) _markComplete;
  final Future<void> Function(GasAnalysis a, int copies)? _printLabel;
  final Duration Function() _elapsed;
  final DateTime Function() _now;
  final Duration? _tickInterval;

  /// The setup of the save card, asked for when a hold is handled. Null, or
  /// a provider that throws, means [LogOnOkSetup] with its defaults and one
  /// copy: the reading is still saved, flagged for sign-off, and nothing
  /// prints.
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

  /// The last timer tick threw and it was reported; stays set until a tick
  /// works again, so a broken clock does not flood the results.
  bool _tickFailing = false;

  /// One event per OK press that was handled, also when it failed. Broadcast.
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
    _detector.detached();
  }

  /// Asks the detector, at the logger's clock, whether OK was pressed, and
  /// handles the hold if so. The timer calls this every `tickInterval`; call
  /// it yourself when the logger was made without a timer.
  void tick() {
    if (_disposed) return;
    final hold = _detector.tick(_elapsed());
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

  /// A timer callback must not throw: that would be an uncaught error in the
  /// zone. A failing tick is reported once.
  void _onTimer() {
    try {
      tick();
      _tickFailing = false;
    } catch (_) {
      if (_tickFailing) return;
      _tickFailing = true;
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

  void _emit(OkLogResult r) {
    if (!_results.isClosed) _results.add(r);
  }

  /// Handles one hold and reports it. Never throws.
  Future<void> _handle(DetectedHold hold) async {
    OkLogResult result;
    try {
      result = await _process(hold);
    } catch (_) {
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
      setup = setupProvider?.call() ?? _noSetup;
    } catch (_) {
      setup = _noSetup;
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
    final outcome = recordToAnalysis(
      record: record,
      bridgeId: 'usb',
      setup: setup.setup,
      clock: BridgeClock(boot: 0, upMs: elapsed.inMilliseconds),
      now: now,
      active: true,
      source: CaptureSource.usbOk,
    );

    switch (outcome) {
      case SkipRecord():
        return OkLogResult(
          code: outcome.feedback,
          text: outcome.feedbackText,
          analysisId: null,
          complete: false,
        );
      case SaveRecord():
        return _saveAndPrint(outcome, setup.copies);
    }
  }

  Future<OkLogResult> _saveAndPrint(SaveRecord outcome, int copies) async {
    final rowId = outcome.rowId;
    final analysis = outcome.analysis;

    try {
      await _save(rowId, analysis);
    } catch (_) {
      return const OkLogResult(
        code: FeedbackCode.error,
        text: 'SAVE FAILED',
        analysisId: null,
        complete: false,
      );
    }

    if (!outcome.printLabel) {
      return OkLogResult(
        code: outcome.feedback,
        text: outcome.feedbackText,
        analysisId: rowId,
        complete: !analysis.needsSignoff,
      );
    }

    // A label is wanted. The row is saved flagged; the printable copy is the
    // entry as it will be once the print has worked, because the print
    // service refuses an entry that still needs a sign-off.
    final print = _printLabel;
    if (print == null) {
      return OkLogResult(
        code: FeedbackCode.check,
        text: 'NO PRINTER',
        analysisId: rowId,
        complete: false,
      );
    }
    try {
      await print(
        GasAnalysis.fromNew(rowId, analysis).withNeedsSignoff(false),
        copies < 1 ? 1 : copies,
      );
    } catch (_) {
      return OkLogResult(
        code: FeedbackCode.check,
        text: 'PRINT FAILED',
        analysisId: rowId,
        complete: false,
      );
    }
    final mixName = gasMixName(analysis.o2Percent, analysis.hePercent);
    try {
      await _markComplete(rowId);
    } catch (_) {
      // The label is out but the stored flag could not be cleared: the diver
      // is told it printed, and the entry still asks for a sign-off.
      return OkLogResult(
        code: FeedbackCode.printed,
        text: mixName,
        analysisId: rowId,
        complete: false,
      );
    }
    return OkLogResult(
      code: FeedbackCode.printed,
      text: mixName,
      analysisId: rowId,
      complete: true,
    );
  }

  /// A monotonic clock that starts now.
  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
