/// BLE transport for the Phomemo M110 label printer (issue #114).
///
/// A thin `flutter_blue_plus` layer, mirroring
/// `lib/shearwater/ble/ble_io_impl.dart`: it connects, runs the write plan
/// from [planPhomemoM110Writes] and turns notifications into
/// [PrinterFault]s with [parsePhomemoNotification]. It holds no protocol
/// logic, so it has no unit tests; everything testable is in
/// `phomemo_encoder.dart` and `phomemo_status.dart`. It is checked on the
/// hardware in Task 15 of the issue #114 plan.
///
/// This directory is the only place under `lib/label_printer/` that may
/// import Flutter or `flutter_blue_plus`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../label_bitmap.dart';
import '../../label_printer.dart';
import '../phomemo_encoder.dart';
import '../phomemo_status.dart';

/// How long [PhomemoBlePrinter.connect] and the scanner wait for the
/// Bluetooth adapter to be on.
const Duration kBluetoothOnTimeout = Duration(seconds: 10);

const Duration _kConnectTimeout = Duration(seconds: 10);

/// MTU asked for on Android, as `ble_io_impl.dart` does. iOS and macOS
/// negotiate it themselves.
const int _kAndroidMtu = 247;

/// Gap between the three status queries before a print.
const Duration _kQueryGap = Duration(milliseconds: 100);

/// How long the answers to the status queries get after the last one.
const Duration _kQueryAnswerWait = Duration(milliseconds: 300);

/// A write that throws is back pressure (SpoolmanScale saw this on an
/// M220): it is retried every [_kWriteRetryDelay], up to [_kWriteRetries]
/// times.
const Duration _kWriteRetryDelay = Duration(milliseconds: 25);
const int _kWriteRetries = 40;

/// Per-write timeout, in seconds as `flutter_blue_plus` takes it. A write
/// normally completes within one connection interval. A timed-out write is
/// not retried: it may have reached the printer, and a resent chunk would
/// corrupt the raster.
const int _kWriteTimeoutSeconds = 5;

/// How long `disconnect()` waits for the link to report closed, in seconds.
/// Shorter than the `flutter_blue_plus` default of 35 s, so a stuck stack
/// can't hold up the print service's `finally`.
const int _kDisconnectTimeoutSeconds = 5;

const LabelPrinterException _kNotFound = LabelPrinterException(
  'Printer not found',
);
const LabelPrinterException _kNotSupported = LabelPrinterException(
  'Not a supported Phomemo printer',
);
const LabelPrinterException _kConnectionLost = LabelPrinterException(
  'Printer connection lost',
);

/// Waits up to [timeout] for the Bluetooth adapter to be on, and returns
/// whether it is.
///
/// On macOS and iOS the adapter starts as `unknown` and only reaches `on`
/// once the OS has initialised it and the user has answered the Bluetooth
/// prompt (see `ImportNotifier._startRealScan`), so the current state alone
/// isn't enough. Unlike `.first.timeout()`, this cancels its subscription
/// and timer on every exit.
Future<bool> waitForBluetoothOn(Duration timeout) async {
  if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
    return true;
  }
  final on = Completer<bool>();
  void settle(bool value) {
    if (!on.isCompleted) on.complete(value);
  }

  final timer = Timer(timeout, () => settle(false));
  final sub = FlutterBluePlus.adapterState.listen(
    (state) {
      if (state == BluetoothAdapterState.on) settle(true);
    },
    onError: (Object e) {
      debugPrint('Phomemo BLE: adapter state failed: $e');
      settle(false);
    },
  );
  try {
    return await on.future;
  } finally {
    timer.cancel();
    // Not awaited: adapterState is an async* stream, and cancelling it
    // waits for a pending platform call that could hang.
    unawaited(sub.cancel());
  }
}

/// A Phomemo M110 reached over BLE by its remote id.
///
/// Call [connect], then [printLabel], then [disconnect]. [disconnect] is
/// safe at any time, including while [connect] or [printLabel] is still
/// running: those then fail and leave the link closed. The instance can be
/// connected again after a [disconnect].
class PhomemoBlePrinter implements LabelPrinter {
  PhomemoBlePrinter({required String remoteId})
    : _device = BluetoothDevice.fromId(remoteId);

  final BluetoothDevice _device;

  /// Everything the printer has told us, as it arrives. Closed by
  /// [disconnect]; [connect] opens a new one.
  StreamController<PhomemoEvent> _events =
      StreamController<PhomemoEvent>.broadcast();

  StreamSubscription<List<int>>? _notifySub;
  BluetoothCharacteristic? _writeChar;
  bool _writeWithoutResponse = false;

  /// Bumped by every [connect] and [disconnect]. A [connect] or
  /// [printLabel] that sees a newer value was overtaken and stops.
  int _session = 0;

  /// The session of the latest [connect]. Only that one may close the
  /// link when it fails; an older one would cut a newer connection.
  int _latestConnect = 0;

  /// The printer's faults, as they arrive. Listen after [connect]: each
  /// connection has its own stream, and [disconnect] ends it.
  @override
  Stream<PrinterFault> get faults => _events.stream
      .map(_faultFor)
      .where((fault) => fault != null)
      .cast<PrinterFault>();

  /// Throws `LabelPrinterException('Bluetooth is off')` when the adapter
  /// isn't on within 10 s, `'Not a supported Phomemo printer'` when the
  /// device lacks the Phomemo service or characteristics, and `'Printer
  /// not found'` for any BLE failure. On failure the link is closed.
  @override
  Future<void> connect() async {
    final session = ++_session;
    _latestConnect = session;
    if (_events.isClosed) {
      _events = StreamController<PhomemoEvent>.broadcast();
    }

    if (!await waitForBluetoothOn(kBluetoothOnTimeout)) {
      throw const LabelPrinterException('Bluetooth is off');
    }
    // Overtaken while waiting: the link hasn't been touched, so there is
    // nothing to close.
    _ensureCurrent(session);

    StreamSubscription<List<int>>? sub;
    try {
      // mtu: null stops flutter_blue_plus from asking for 512 inside
      // connect(), where a refusal would fail the connect. We ask for 247
      // ourselves below and ignore a refusal.
      await _device.connect(timeout: _kConnectTimeout, mtu: null);
      _ensureCurrent(session);

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final mtu = await _device.requestMtu(_kAndroidMtu);
          debugPrint('Phomemo BLE: negotiated MTU=${mtu}B');
        } catch (e) {
          debugPrint('Phomemo BLE: requestMtu failed: $e');
        }
        _ensureCurrent(session);
      }

      final services = await _device.discoverServices();
      _ensureCurrent(session);
      final (:write, :notify) = _findCharacteristics(services);

      // Listen before enabling notifications so an answer that arrives
      // straight away isn't lost.
      sub = notify.onValueReceived.listen(
        _onNotification,
        onError: (Object e) => debugPrint('Phomemo BLE: notify error: $e'),
      );
      await notify.setNotifyValue(true);
      _ensureCurrent(session);

      // Commit. Synchronous from the last check, so a disconnect() can't
      // slip in between.
      final previous = _notifySub;
      _notifySub = sub;
      _writeChar = write;
      _writeWithoutResponse = write.properties.writeWithoutResponse;
      unawaited(previous?.cancel());
      debugPrint(
        'Phomemo BLE: connected. MTU=${_device.mtuNow}B, '
        'write ${_writeWithoutResponse ? 'without' : 'with'} response',
      );
    } catch (e) {
      await _abandon(session, sub);
      if (e is LabelPrinterException) rethrow;
      if (e is FlutterBluePlusException ||
          e is TimeoutException ||
          e is PlatformException) {
        debugPrint('Phomemo BLE: connect failed: $e');
        throw _kNotFound;
      }
      rethrow;
    }
  }

  /// Prints [copies] (clamped to 1-[kPhomemoMaxCopies]) of [bitmap].
  ///
  /// Asks the printer for paper, cover and battery first, and throws
  /// before sending any raster when it reports no labels or an open cover.
  /// A fatal fault later stops the writes and throws too. Returns the
  /// warnings (low battery) seen. Throws `'Printer connection lost'` when
  /// writes keep failing or the link goes down.
  @override
  Future<List<PrinterFault>> printLabel(
    LabelBitmap bitmap, {
    int copies = 1,
  }) async {
    final write = _writeChar;
    if (write == null) {
      throw StateError('PhomemoBlePrinter is not connected');
    }
    final session = _session;
    final count = copies.clamp(1, kPhomemoMaxCopies).toInt();
    final plan = planPhomemoM110Writes(
      bitmap,
      copies: count,
      chunkSize: min(kPhomemoChunkSize, _device.mtuNow - 3),
    );

    // Watch the printer for the whole job, from the status queries on, so
    // faults and job-done events during the writes count too.
    final job = _PrintJob(count);
    final sub = _events.stream.listen(job.onEvent, onDone: job.onClosed);
    try {
      // 1. Pre-print check. No answer is fine: the printer may not answer.
      const queries = [
        kPhomemoQueryPaper,
        kPhomemoQueryCover,
        kPhomemoQueryBattery,
      ];
      for (var i = 0; i < queries.length; i++) {
        await _send(write, queries[i], session, job);
        await Future<void>.delayed(
          i < queries.length - 1 ? _kQueryGap : _kQueryAnswerWait,
        );
        job.throwIfFatal();
      }

      // 2. The label(s), paced as the plan says.
      for (final step in plan) {
        await _send(write, step.bytes, session, job);
        await Future<void>.delayed(step.pauseAfter);
        job.throwIfFatal();
      }

      // 3. Wait for the printer to finish before anyone disconnects:
      // vivier found that closing the link early stops the print. Reaching
      // the timeout counts as printed, since the M110 may never send
      // job done.
      await job.waitForDone(kPhomemoDoneTimeout * count);
      job.throwIfFatal();
      if (!job.allDone && (session != _session || _device.isDisconnected)) {
        throw _kConnectionLost;
      }
      return job.warnings;
    } finally {
      job.dispose();
      await sub.cancel();
    }
  }

  /// Closes the link. Never throws; safe to call more than once, before
  /// [connect], and while [connect] or [printLabel] is running.
  @override
  Future<void> disconnect() async {
    _session++;
    final sub = _notifySub;
    _notifySub = null;
    _writeChar = null;
    try {
      await sub?.cancel();
    } catch (e) {
      debugPrint('Phomemo BLE: cancel notify failed: $e');
    }
    if (!_events.isClosed) unawaited(_events.close());
    await _closeLink();
  }

  /// Writes [bytes], retrying while the printer pushes back.
  Future<void> _send(
    BluetoothCharacteristic c,
    List<int> bytes,
    int session,
    _PrintJob job,
  ) async {
    for (var retry = 0; ; retry++) {
      if (session != _session || _device.isDisconnected) {
        throw _kConnectionLost;
      }
      try {
        await c.write(
          bytes,
          withoutResponse: _writeWithoutResponse,
          timeout: _kWriteTimeoutSeconds,
        );
        return;
      } on Exception catch (e) {
        if (retry >= _kWriteRetries || _isTimeout(e)) {
          debugPrint('Phomemo BLE: write failed after $retry retries: $e');
          throw _kConnectionLost;
        }
      }
      await Future<void>.delayed(_kWriteRetryDelay);
      job.throwIfFatal();
    }
  }

  void _onNotification(List<int> value) {
    final hex = value.map((b) => b.toRadixString(16).padLeft(2, '0'));
    debugPrint('Phomemo BLE: notify ${hex.join(' ')}');
    final event = parsePhomemoNotification(value);
    if (event == null || _events.isClosed) return;
    _events.add(event);
  }

  /// Throws when a [disconnect] or a newer [connect] overtook [session].
  void _ensureCurrent(int session) {
    if (session != _session) throw _kNotFound;
  }

  /// Cleans up after a failed [connect]. The link is closed only when no
  /// newer [connect] has started, since that one owns it now.
  Future<void> _abandon(int session, StreamSubscription<List<int>>? sub) async {
    try {
      await sub?.cancel();
    } catch (e) {
      debugPrint('Phomemo BLE: cancel notify failed: $e');
    }
    if (session == _latestConnect) await _closeLink();
  }

  Future<void> _closeLink() async {
    try {
      // queue: false skips the flutter_blue_plus operation queue, so this
      // also cancels a connect that is still in progress.
      await _device.disconnect(
        queue: false,
        timeout: _kDisconnectTimeoutSeconds,
      );
    } catch (e) {
      debugPrint('Phomemo BLE: disconnect failed: $e');
    }
  }
}

/// The Phomemo service's write and notify characteristics in [services].
/// Throws `'Not a supported Phomemo printer'` when either is missing or
/// can't be written to or notify.
({BluetoothCharacteristic write, BluetoothCharacteristic notify})
_findCharacteristics(List<BluetoothService> services) {
  final serviceUuid = Guid(kPhomemoServiceUuid);
  final writeUuid = Guid(kPhomemoWriteUuid);
  final notifyUuid = Guid(kPhomemoNotifyUuid);

  BluetoothService? service;
  for (final s in services) {
    if (s.uuid == serviceUuid) {
      service = s;
      break;
    }
  }
  if (service == null) throw _kNotSupported;

  BluetoothCharacteristic? write;
  BluetoothCharacteristic? notify;
  for (final c in service.characteristics) {
    if (c.uuid == writeUuid) write = c;
    if (c.uuid == notifyUuid) notify = c;
  }
  if (write == null || notify == null) throw _kNotSupported;
  final w = write.properties;
  final n = notify.properties;
  if (!(w.write || w.writeWithoutResponse) || !(n.notify || n.indicate)) {
    throw _kNotSupported;
  }
  return (write: write, notify: notify);
}

bool _isTimeout(Exception e) =>
    e is TimeoutException ||
    (e is FlutterBluePlusException &&
        e.platform == ErrorPlatform.fbp &&
        e.code == FbpErrorCode.timeout.index);

PrinterFault? _faultFor(PhomemoEvent event) => switch (event) {
  PhomemoEvent.jobDone => null,
  PhomemoEvent.noLabels => PrinterFault.noLabels,
  PhomemoEvent.coverOpen => PrinterFault.coverOpen,
  PhomemoEvent.lowBattery => PrinterFault.lowBattery,
};

/// What the printer has said during one [PhomemoBlePrinter.printLabel].
/// Nothing here throws on its own: a fatal fault is stored and only
/// thrown by [throwIfFatal], so an event after the job ends is harmless.
class _PrintJob {
  _PrintJob(this._copies);

  final int _copies;
  int _done = 0;
  bool _closed = false;
  PrinterFault? _fatal;
  final List<PrinterFault> warnings = [];
  Completer<void>? _waiter;
  Timer? _timer;

  bool get allDone => _done >= _copies;

  bool get _finished => allDone || _fatal != null || _closed;

  void onEvent(PhomemoEvent event) {
    if (event == PhomemoEvent.jobDone) {
      _done++;
    } else if (_faultFor(event) case final fault?) {
      if (isFatalPrinterFault(fault)) {
        _fatal ??= fault;
      } else if (!warnings.contains(fault)) {
        warnings.add(fault);
      }
    }
    _wake();
  }

  /// The event stream ended: the printer was disconnected.
  void onClosed() {
    _closed = true;
    _wake();
  }

  /// Completes when every copy is done, a fatal fault arrives, the link
  /// closes, or [timeout] passes. Never completes with an error.
  Future<void> waitForDone(Duration timeout) {
    if (_finished) return Future<void>.value();
    final waiter = _waiter = Completer<void>();
    _timer = Timer(timeout, () {
      if (!waiter.isCompleted) waiter.complete();
    });
    return waiter.future;
  }

  void throwIfFatal() {
    final fault = _fatal;
    if (fault != null) {
      throw LabelPrinterException(printerFaultMessage(fault), fault: fault);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _wake() {
    final waiter = _waiter;
    if (_finished && waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }
}
