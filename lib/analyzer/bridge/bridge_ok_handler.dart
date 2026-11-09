/// OK records from the SOLO bridge become saved analyses (issue #113).
///
/// The bridge detects the OK hold itself, keeps a record in flash and sends
/// it as `REC`, `W`..., `H`, `END <rid>`. [BridgeOkHandler] assembles the
/// record, hands it to the [OkRecordProcessor] it shares with the USB
/// logger, answers `ACK <rid>` once the row is committed (or once it is
/// decided that nothing is saved), and then `FB <rid> <code> <text>` for the
/// bridge screen. The bridge deletes a record on its `ACK` and sends the
/// next only after it, so a record whose save failed stays on the bridge and
/// comes again on the next connection.
///
/// Pure Dart: the processor and the transport's `send` are passed in.
library;

import 'dart:async';

import '../../data/models/gas_analysis.dart';
import '../ok_logger.dart';
import '../ok_record_processor.dart';
import 'bridge_protocol.dart';
import 'record_to_analysis.dart';

/// The bridge's clock as last heard, and when it was heard on the app's
/// monotonic clock.
typedef _HeardClock = ({int boot, int upMs, Duration at});

class BridgeOkHandler implements OkLogger {
  BridgeOkHandler({
    required OkRecordProcessor processor,
    required Future<void> Function(String message) send,
    required bool Function() active,
    Duration Function()? elapsed,
    DateTime Function()? now,
    void Function(Object error, StackTrace stack)? onError,
  }) : _processor = processor,
       _send = send,
       _active = active,
       _elapsed = elapsed ?? _stopwatchClock(),
       _now = now ?? DateTime.now,
       _onError = onError;

  final OkRecordProcessor _processor;
  final Future<void> Function(String message) _send;

  /// The session is connected over the bridge, so a fresh record with
  /// `live=1` counts as live (spec §5 "Live or late").
  final bool Function() _active;
  final Duration Function() _elapsed;
  final DateTime Function() _now;
  final void Function(Object error, StackTrace stack)? _onError;

  /// The setup of the save card, asked for when a record is handled. Null,
  /// or a provider that throws, means [kNoOkSetup].
  @override
  OkSetup Function()? setupProvider;

  final StreamController<OkLogResult> _results =
      StreamController<OkLogResult>.broadcast();

  BridgeRecordAssembler _assembler = BridgeRecordAssembler();

  /// The bridge id of the latest `HELLO`; null before the first.
  String? _bridgeId;

  /// The bridge's boot and uptime from the latest `HELLO` or `ST`.
  _HeardClock? _clock;

  /// Records are handled one after the other: each waits for the one before
  /// it, also for its `FB`. Handling never throws, so the chain never breaks.
  Future<void> _chain = Future<void>.value();

  bool _disposed = false;

  /// One event per record that was handled, also when it failed. Broadcast.
  @override
  Stream<OkLogResult> get results => _results.stream;

  /// Feeds one message from the bridge.
  ///
  /// `HELLO` starts a new connection: a fresh assembler (a record cut off by
  /// the drop is sent again from its `REC`) and the bridge's clock. `ST`
  /// moves the clock on. A complete record is queued for handling; one that
  /// ends before any `HELLO` is dropped without an `ACK`, and the bridge
  /// sends it again.
  void onMessage(BridgeMessage m) {
    if (_disposed) return;
    switch (m) {
      case BridgeHello():
        _assembler = BridgeRecordAssembler();
        _bridgeId = m.bridgeId;
        _clock = (boot: m.boot, upMs: m.upMs, at: _elapsed());
        return;
      case BridgeStatus():
        final c = _clock;
        if (c != null) _clock = (boot: c.boot, upMs: m.upMs, at: _elapsed());
        return;
      default:
        final record = _assembler.add(m);
        final bridgeId = _bridgeId;
        if (record == null || bridgeId == null) return;
        _chain = _chain.then((_) => _handle(record, bridgeId));
    }
  }

  /// Stops taking messages, lets a record that is being handled finish (its
  /// result is still delivered) and closes [results].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _chain;
    await _results.close();
  }

  /// The bridge's clock now: the last one heard, moved on by the time since
  /// it was heard (the plan 1 ruling: rebase at receipt).
  BridgeClock _clockNow() {
    final c = _clock!;
    final since = _elapsed() - c.at;
    return BridgeClock(boot: c.boot, upMs: c.upMs + since.inMilliseconds);
  }

  /// Handles one record: process, `ACK` (from the processor, right after the
  /// save), `FB`, and the result. Never throws.
  Future<void> _handle(BridgeRecord record, String bridgeId) async {
    final rid = record.rid;
    OkSetup setup;
    try {
      setup = setupProvider?.call() ?? kNoOkSetup;
    } catch (e, st) {
      _report(e, st);
      setup = kNoOkSetup;
    }

    OkLogResult result;
    try {
      result = await _processor.process(
        record: record,
        bridgeId: bridgeId,
        source: CaptureSource.bridgeOk,
        clock: _clockNow(),
        now: _now(),
        active: _active(),
        setup: setup,
        afterSave: () => _send(formatAck(rid)),
      );
    } catch (e, st) {
      _report(e, st);
      // Nothing was saved and nothing was ACKed: the record stays on the
      // bridge.
      result = OkLogResult(
        code: FeedbackCode.error,
        text: 'LOG FAILED',
        analysisId: null,
        complete: false,
        setupUsed: setup,
      );
    }

    if (result.alreadySaved) {
      // Delivered again after its ACK was lost: the entry is in the log.
      result = OkLogResult(
        code: FeedbackCode.saved,
        text: 'ALREADY SAVED',
        analysisId: null,
        complete: false,
        setupUsed: setup,
        alreadySaved: true,
      );
    }

    try {
      await _send(formatFeedback(rid, result.code, result.text));
    } catch (e, st) {
      _report(e, st);
    }
    if (!_results.isClosed) _results.add(result);
  }

  /// Hands a caught error to the owner's [onError]; whatever that does,
  /// it must not break the handler.
  void _report(Object error, StackTrace stack) {
    try {
      _onError?.call(error, stack);
    } catch (_) {}
  }

  /// A monotonic clock that starts now.
  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
