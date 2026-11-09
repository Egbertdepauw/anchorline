/// The BLE side of the SOLO bridge link: [CentralBridgeLink] and the
/// bridge scan, over the shared [BleCentral] seam (`lib/ble/`).
///
/// A thin layer: it connects, subscribes to the Nordic UART TX
/// characteristic, turns notifications into lines with a
/// `SerialLineBuffer` and writes messages to RX in MTU-sized chunks. It
/// holds no protocol logic. Its connection handling is unit-tested against
/// a fake central (`test/analyzer/bridge/bridge_link_ble_test.dart`); the
/// real radios are checked on the bench.
///
/// One of the two files under `lib/analyzer/` that may import Flutter
/// (for `debugPrint`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../ble/ble_central.dart';
import '../../ble/ble_central_default.dart';
import '../../ble/ble_device_scan.dart';
import '../transport/serial_line_buffer.dart';
import 'bridge_link.dart';
import '../../ble/ble_log.dart';

/// MTU asked for on Android. iOS and macOS negotiate it themselves;
/// elsewhere the request is a no-op.
const int _kAndroidMtu = 247;

/// How long the Bluetooth adapter gets to be on.
const Duration kBridgeBluetoothOnTimeout = Duration(seconds: 10);

/// Where the platform can't reconnect by itself (Windows, Linux): the
/// pauses between reconnection attempts after a drop. The last one repeats
/// until the bridge is back or the link is closed.
const List<Duration> kBridgeReconnectDelays = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 10),
];

/// The pause between attempts of a first connection that the platform
/// does not retry itself.
const Duration _kFirstConnectRetry = Duration(milliseconds: 500);

/// How long one connection attempt may take where the link reconnects in
/// Dart.
const Duration kBridgeAttemptTimeout = Duration(seconds: 10);

const BridgeLinkException _kNotFound = BridgeLinkException(
  'Bridge not found. Is it switched on?',
);
const BridgeLinkException _kNotABridge = BridgeLinkException(
  'Not an Anchorline bridge',
);

/// A bridge reached over BLE by its remote id.
///
/// Where the central supports it (Android, iOS, macOS), [connect] connects
/// with `autoConnect`, so after the first connection the operating system
/// reconnects by itself when the bridge comes back in range. Elsewhere
/// (Windows, Linux) the link reconnects itself: on a drop it retries with
/// the pauses in [reconnectDelays] until the bridge is back or
/// [disconnect] is called. Either way each reconnection re-discovers the
/// service and re-subscribes, then reports [BridgeLinkState.connected]
/// again.
class CentralBridgeLink implements BridgeLink {
  CentralBridgeLink({
    required String remoteId,
    BleCentral? central,
    this.firstConnectTimeout = kBridgeFirstConnectTimeout,
    this.attemptTimeout = kBridgeAttemptTimeout,
    this.reconnectDelays = kBridgeReconnectDelays,
  })  : _central = central ?? defaultBleCentral(),
        _remoteId = remoteId {
    _device = _central.peripheral(remoteId);
  }

  final BleCentral _central;
  final String _remoteId;
  late final BlePeripheral _device;

  final Duration firstConnectTimeout;
  final Duration attemptTimeout;
  final List<Duration> reconnectDelays;

  final _lines = StreamController<String>.broadcast();
  final _states = StreamController<BridgeLinkState>.broadcast();
  final _buffer = SerialLineBuffer();

  BridgeLinkState _state = BridgeLinkState.disconnected;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  BleCharacteristic? _rx;

  /// Completes when the first connection is fully set up, or fails.
  /// autoConnect mode only.
  Completer<void>? _first;

  /// Bumped by [connect] and [disconnect]; stale setups see it and stop.
  int _session = 0;
  bool _everConnected = false;
  bool _disposed = false;

  /// Dart-reconnect mode: the link is up (set up and subscribed).
  bool _linkUp = false;

  /// Dart-reconnect mode: a reconnection loop is running.
  bool _reconnecting = false;

  /// Serialises [send] so chunks of two messages never interleave.
  Future<void> _sendChain = Future<void>.value();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<BridgeLinkState> get states => _states.stream;

  @override
  BridgeLinkState get state => _state;

  @override
  Future<void> connect() async {
    if (_disposed || _state != BridgeLinkState.disconnected) return;
    final session = ++_session;
    _everConnected = false;
    _setState(BridgeLinkState.connecting);

    final adapter = await waitForAdapterOn(_central, kBridgeBluetoothOnTimeout);
    final problem = bleAdapterProblem(adapter);
    if (problem != null) {
      _giveUp(session);
      throw BridgeLinkException(problem);
    }
    if (session != _session) throw _kNotFound;

    if (_central.supportsAutoConnect) {
      await _connectAuto(session);
    } else {
      await _connectManual(session);
    }
  }

  // -------------------------------------------------------------------------
  // autoConnect mode: Android, iOS, macOS
  // -------------------------------------------------------------------------

  Future<void> _connectAuto(int session) async {
    final first = _first = Completer<void>();
    _connectionSub = _device.connectionChanges.listen(
      (up) => _onAutoConnectionState(up, session),
    );
    try {
      // With autoConnect this returns once the request is made, not when
      // the bridge answers, so the wait below carries the timeout.
      await _device.connect(autoConnect: true);
      await first.future.timeout(firstConnectTimeout);
    } on TimeoutException {
      await _giveUpAndClose(session);
      throw _kNotFound;
    } on BridgeLinkException {
      await _giveUpAndClose(session);
      rethrow;
    } catch (e) {
      bleLog('Bridge BLE: connect failed: $e');
      await _giveUpAndClose(session);
      throw _kNotFound;
    }
  }

  void _onAutoConnectionState(bool up, int session) {
    if (session != _session) return;
    if (up) {
      unawaited(_setupAuto(session));
    } else if (_everConnected) {
      // autoConnect brings the link back by itself.
      _dropNotifications();
      _setState(BridgeLinkState.connecting);
    }
  }

  /// Runs on every connection, the first and each reconnection.
  Future<void> _setupAuto(int session) async {
    try {
      await _setup(session);
      if (session != _session) return;
      final first = _first;
      if (first != null && !first.isCompleted) first.complete();
    } catch (e) {
      if (session != _session) return;
      bleLog('Bridge BLE: setup failed: $e');
      final first = _first;
      if (first != null && !first.isCompleted) {
        // Only the first connection reports to the caller; a later failure
        // leaves the link connecting and the transport's HELLO timeout
        // speaks.
        first.completeError(e is BridgeLinkException ? e : _kNotABridge);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Dart-reconnect mode: Windows, Linux
  // -------------------------------------------------------------------------

  Future<void> _connectManual(int session) async {
    _linkUp = false;
    _connectionSub = _device.connectionChanges.listen(
      (up) => _onManualConnectionState(up, session),
    );
    // Completes with false when the first connection has had its time.
    final deadline = Completer<bool>();
    final timer = Timer(firstConnectTimeout, () => deadline.complete(false));
    Object? lastError;
    try {
      while (!deadline.isCompleted) {
        if (session != _session) throw _kNotFound;
        try {
          final done = await Future.any([
            _attempt(session, attemptTimeout).then((_) => true),
            deadline.future,
          ]);
          if (done) return;
          break;
        } on BridgeLinkException catch (e) {
          // Reached the device, and it is not a bridge: retrying won't
          // help. (Also a session ended by disconnect().)
          lastError = e;
          break;
        } catch (e) {
          lastError = e;
          bleLog('Bridge BLE: connect attempt failed: $e');
        }
        if (session != _session) throw _kNotFound;
        await _sleep(_kFirstConnectRetry, until: deadline.future);
      }
    } finally {
      timer.cancel();
    }
    await _giveUpAndClose(session);
    if (lastError is BridgeLinkException) throw lastError;
    throw _kNotFound;
  }

  /// One connection attempt with set-up. Throws on failure, with the link
  /// closed again; a [BridgeLinkException] means the device answered but
  /// is not a bridge.
  Future<void> _attempt(int session, Duration timeout) async {
    try {
      await _device.connect(timeout: timeout);
      if (session != _session) throw _kNotFound;
      // No timeout here: a stale set-up that finished late would report
      // connected on a link already given up. A GATT call on a dropped
      // link fails by itself.
      await _setup(session);
      if (session != _session) throw _kNotFound;
    } catch (e) {
      if (session == _session) {
        _dropNotifications();
        await _device.disconnect();
      }
      rethrow;
    }
  }

  void _onManualConnectionState(bool up, int session) {
    if (session != _session || up || !_linkUp) return;
    // The link dropped. Reconnect until it is back or disconnect() ends
    // the session.
    _linkUp = false;
    _dropNotifications();
    _setState(BridgeLinkState.connecting);
    unawaited(_reconnect(session));
  }

  Future<void> _reconnect(int session) async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      // The old link's resources go first, so the new connection starts
      // clean.
      await _device.disconnect();
      for (var i = 0; session == _session; i++) {
        final delay = reconnectDelays.isEmpty
            ? const Duration(seconds: 1)
            : reconnectDelays[min(i, reconnectDelays.length - 1)];
        await _sleep(delay);
        if (session != _session) return;
        try {
          await _attempt(session, attemptTimeout);
          bleLog('Bridge BLE: reconnected after ${i + 1} attempt(s)');
          return;
        } catch (e) {
          bleLog('Bridge BLE: reconnect attempt ${i + 1} failed: $e');
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  Timer? _sleepTimer;
  Completer<void>? _sleeping;

  /// Waits [d], or until [until] completes, or until [disconnect] wakes
  /// it, whichever comes first.
  Future<void> _sleep(Duration d, {Future<Object?>? until}) {
    _wake();
    final c = _sleeping = Completer<void>();
    _sleepTimer = Timer(d, _wake);
    until?.then((_) => _wake());
    return c.future;
  }

  void _wake() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final c = _sleeping;
    _sleeping = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  /// Discovers, subscribes and reports connected. Throws a
  /// [BridgeLinkException] when the device is not a bridge.
  Future<void> _setup(int session) async {
    StreamSubscription<List<int>>? sub;
    try {
      try {
        final mtu = await _device.requestMtu(_kAndroidMtu);
        bleLog('Bridge BLE: MTU=${mtu}B');
      } catch (e) {
        bleLog('Bridge BLE: requestMtu failed: $e');
      }
      if (session != _session) return;
      final chars = await _device.discoverServices();
      if (session != _session) return;
      final (:tx, :rx) = _findCharacteristics(chars);

      _buffer.clear();
      // Listen before enabling notifications so nothing is lost.
      sub = tx.notifications.listen(
        _onNotification,
        onError: (Object e) => bleLog('Bridge BLE: notify error: $e'),
      );
      await tx.setNotify(true);
      if (session != _session) {
        unawaited(sub.cancel());
        return;
      }

      final previous = _notifySub;
      _notifySub = sub;
      _rx = rx;
      unawaited(previous?.cancel());
      _everConnected = true;
      _linkUp = true;
      bleLog('Bridge BLE: connected. MTU=${_device.mtu}B');
      _setState(BridgeLinkState.connected);
    } catch (e) {
      unawaited(sub?.cancel());
      rethrow;
    }
  }

  void _onNotification(List<int> value) {
    for (final line in _buffer.add(value)) {
      if (!_lines.isClosed) _lines.add(line);
    }
  }

  @override
  Future<void> send(String message) {
    final next = _sendChain.then((_) => _write(message));
    // The chain must survive a failed write.
    _sendChain = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _write(String message) async {
    final rx = _rx;
    if (_state != BridgeLinkState.connected || rx == null) {
      throw const BridgeLinkException('Bridge not connected');
    }
    final bytes = utf8.encode('$message\n');
    final withoutResponse = !rx.properties.write;
    for (final chunk in chunkForWrite(bytes, _device.maxWritePayload)) {
      try {
        await rx.write(chunk, withoutResponse: withoutResponse);
      } on BleException catch (e) {
        throw BridgeLinkException('Bridge write failed: ${e.message}');
      } on TimeoutException {
        throw const BridgeLinkException('Bridge write failed: timeout');
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _session++;
    _first = null;
    _linkUp = false;
    _wake();
    await _closeLink();
    _setState(BridgeLinkState.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    unawaited(_lines.close());
    unawaited(_states.close());
  }

  /// A failed first connect: nothing connected, so just reset.
  void _giveUp(int session) {
    if (session != _session) return;
    _setState(BridgeLinkState.disconnected);
  }

  Future<void> _giveUpAndClose(int session) async {
    if (session != _session) return;
    _session++;
    _first = null;
    _linkUp = false;
    _wake();
    await _closeLink();
    _setState(BridgeLinkState.disconnected);
  }

  void _dropNotifications() {
    final sub = _notifySub;
    _notifySub = null;
    _rx = null;
    unawaited(sub?.cancel());
  }

  Future<void> _closeLink() async {
    final conn = _connectionSub;
    _connectionSub = null;
    unawaited(conn?.cancel());
    _dropNotifications();
    // Also cancels a connect still in progress and an autoConnect request.
    await _device.disconnect();
  }

  void _setState(BridgeLinkState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  @override
  String toString() => 'CentralBridgeLink($_remoteId)';
}

({BleCharacteristic tx, BleCharacteristic rx}) _findCharacteristics(
  List<BleCharacteristic> chars,
) {
  final tx = findCharacteristic(chars, kNusServiceUuid, kNusTxUuid);
  final rx = findCharacteristic(chars, kNusServiceUuid, kNusRxUuid);
  if (tx == null || rx == null) throw _kNotABridge;
  if (!tx.properties.canNotify || !rx.properties.canWrite) throw _kNotABridge;
  return (tx: tx, rx: rx);
}

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

/// A bridge found by [scanForBridges].
class FoundBridge {
  const FoundBridge({required this.id, required this.name});

  /// The BLE remote id, used to reconnect.
  final String id;

  /// `Anchorline Bridge XXXX`.
  final String name;
}

BleDeviceScan? _scanRun;

/// Scans for devices that advertise the NUS service AND whose name starts
/// with [kBridgeNamePrefix]. The stream emits the bridges found so far,
/// sorted by name, each time the list changes, and closes when the scan
/// ends. It emits a [BridgeLinkException] first when Bluetooth is off or
/// the scan can't start. A new scan ends the previous one.
Stream<List<FoundBridge>> scanForBridges({
  Duration timeout = const Duration(seconds: 10),
  BleCentral? central,
}) {
  _scanRun?.end();
  final run = BleDeviceScan(
    central: central ?? defaultBleCentral(),
    withServices: const [kNusServiceUuid],
    timeout: timeout,
    adapterTimeout: kBridgeBluetoothOnTimeout,
    match: bridgeNameOf,
    error: BridgeLinkException.new,
  );
  _scanRun = run;
  return run.stream.map(
    (found) => [for (final d in found) FoundBridge(id: d.id, name: d.name)],
  );
}

/// The name to list [r] under when it is a bridge, or null.
/// The scan itself only reports devices that advertise the NUS service.
@visibleForTesting
String? bridgeNameOf(BleScanResult r) =>
    r.name.startsWith(kBridgeNamePrefix) ? r.name : null;

Future<void> stopBridgeScan({BleCentral? central}) async {
  _scanRun?.end();
  _scanRun = null;
  await (central ?? defaultBleCentral()).stopScan();
}
