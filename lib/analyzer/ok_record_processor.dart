/// One OK record turned into a saved analysis and, when the pocket print
/// rules allow, a label (issue #113). Shared by the USB logger and the
/// bridge's record handler.
///
/// The order is spec §5 "Order of operations":
///
///  1. the row is saved, flagged for sign-off while a print is about to be
///     tried;
///  2. `afterSave` runs (over the bridge: the `ACK`);
///  3. when printing: the label prints from an in-memory copy marked
///     complete, and the stored flag is cleared once it has;
///  4. the result says what the bridge screen and the save card show.
///
/// A crash between the steps leaves the entry flagged, never unflagged
/// without a label.
///
/// Pure Dart: the DAO and the printer are passed in as functions.
library;

import '../analysis/gas_naming.dart';
import '../data/models/gas_analysis.dart';
import 'bridge/bridge_protocol.dart';
import 'bridge/record_to_analysis.dart';
import 'ok_logger.dart';

class OkRecordProcessor {
  OkRecordProcessor({
    required Future<bool> Function(String id, NewGasAnalysis a) save,
    required Future<void> Function(String id) markComplete,
    Future<void> Function(GasAnalysis a, int copies)? printLabel,
    void Function(Object error, StackTrace stack)? onError,
  }) : _save = save,
       _markComplete = markComplete,
       _printLabel = printLabel,
       _onError = onError;

  /// False means a row with this id was already there, and nothing was
  /// written.
  final Future<bool> Function(String id, NewGasAnalysis a) _save;
  final Future<void> Function(String id) _markComplete;
  final Future<void> Function(GasAnalysis a, int copies)? _printLabel;
  final void Function(Object error, StackTrace stack)? _onError;

  /// Steps 1, 3 and 4 of spec §5 "Order of operations" for [record].
  ///
  /// [afterSave] runs right after the row is committed, right after the
  /// decision not to save (no reading, room air), or when the row existed
  /// already; never when the save threw. An [afterSave] that throws is
  /// reported and the steps go on.
  ///
  /// The save, the print and the mark-complete catch their own failures and
  /// say so in the result. Only [recordToAnalysis] itself could throw out of
  /// here.
  Future<OkLogResult> process({
    required BridgeRecord record,
    required String bridgeId,
    required CaptureSource source,
    required BridgeClock clock,
    required DateTime now,
    required bool active,
    required OkSetup setup,
    Future<void> Function()? afterSave,
  }) async {
    final outcome = recordToAnalysis(
      record: record,
      bridgeId: bridgeId,
      setup: setup.setup,
      clock: clock,
      now: now,
      active: active,
      source: source,
    );

    switch (outcome) {
      case SkipRecord():
        await _after(afterSave);
        return OkLogResult(
          code: outcome.feedback,
          text: outcome.feedbackText,
          analysisId: null,
          complete: false,
          setupUsed: setup,
        );
      case SaveRecord():
        return _saveAndPrint(outcome, setup, afterSave);
    }
  }

  Future<void> _after(Future<void> Function()? afterSave) async {
    if (afterSave == null) return;
    try {
      await afterSave();
    } catch (e, st) {
      _report(e, st);
    }
  }

  /// Hands a caught error to the owner's [onError]; whatever that does,
  /// it must not break the processor.
  void _report(Object error, StackTrace stack) {
    try {
      _onError?.call(error, stack);
    } catch (_) {}
  }

  Future<OkLogResult> _saveAndPrint(
    SaveRecord outcome,
    OkSetup setup,
    Future<void> Function()? afterSave,
  ) async {
    final copies = setup.copies;
    final rowId = outcome.rowId;
    final analysis = outcome.analysis;

    try {
      // False means a row with this id was already there, and nothing was
      // written. Do not print for it or touch it: [_markComplete] only ever
      // clears a row this press wrote.
      final inserted = await _save(rowId, analysis);
      if (!inserted) {
        await _after(afterSave);
        return OkLogResult(
          code: FeedbackCode.error,
          text: 'SAVE FAILED',
          analysisId: null,
          complete: false,
          setupUsed: setup,
          alreadySaved: true,
        );
      }
    } catch (e, st) {
      _report(e, st);
      return OkLogResult(
        code: FeedbackCode.error,
        text: 'SAVE FAILED',
        analysisId: null,
        complete: false,
        setupUsed: setup,
      );
    }
    await _after(afterSave);

    if (!outcome.printLabel) {
      return OkLogResult(
        code: outcome.feedback,
        text: outcome.feedbackText,
        analysisId: rowId,
        complete: !analysis.needsSignoff,
        setupUsed: setup,
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
        setupUsed: setup,
      );
    }
    try {
      await print(
        GasAnalysis.fromNew(rowId, analysis).withNeedsSignoff(false),
        copies < 1 ? 1 : copies,
      );
    } catch (e, st) {
      _report(e, st);
      return OkLogResult(
        code: FeedbackCode.check,
        text: 'PRINT FAILED',
        analysisId: rowId,
        complete: false,
        setupUsed: setup,
      );
    }
    final mixName = gasMixName(analysis.o2Percent, analysis.hePercent);
    try {
      await _markComplete(rowId);
    } catch (e, st) {
      _report(e, st);
      // The label is out but the stored flag could not be cleared: the diver
      // is told it printed, and the entry still asks for a sign-off.
      return OkLogResult(
        code: FeedbackCode.printed,
        text: mixName,
        analysisId: rowId,
        complete: false,
        setupUsed: setup,
      );
    }
    return OkLogResult(
      code: FeedbackCode.printed,
      text: mixName,
      analysisId: rowId,
      complete: true,
      setupUsed: setup,
    );
  }
}
