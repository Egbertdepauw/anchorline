/// The `flutter_blue_plus` side of the SOLO bridge link: [FbpBridgeLink]
/// and the bridge scan.
///
/// A thin BLE layer, like `lib/label_printer/phomemo/ble/`: it connects,
/// subscribes to the Nordic UART TX characteristic, turns notifications
/// into lines with a `SerialLineBuffer` and writes messages to RX in
/// MTU-sized chunks. It holds no protocol logic and has no unit tests; it
/// is checked on the bench (plan Task 7). The reassembly it relies on is
/// tested through `SerialLineBuffer`.
///
/// One of the two files under `lib/analyzer/` that may import Flutter.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../label_printer/phomemo/ble/phomemo_ble_printer.dart'
    show kBluetoothOnTimeout, waitForBluetoothOn;
import '../transport/serial_line_buffer.dart';
import 'bridge_link.dart';

/// MTU asked for on Android. iOS and macOS negotiate it themselves.
const int _kAndroidMtu = 247;

/// The smallest payload a write may be cut to (default MTU 23 minus 3).
const int _kMinChunk = 20;

const int _kDisconnectTimeoutSeconds = 5;

const BridgeLinkException _kNotFound = BridgeLinkException(
  'Bridge not found. Is it switched on?',
);
const BridgeLinkException _kBluetoothOff = BridgeLinkException(
  'Bluetooth is off',
);

/// A bridge reached over BLE by its remote id.
///
/// [connect] connects with `autoConnect`, so after the first connection the
/// operating system reconnects by itself when the bridge comes back in
/// range; each reconnection re-discovers the service and re-subscribes, then
/// reports [BridgeLinkState.connected] again.
class FbpBridgeLink implements BridgeLink {
  FbpBridgeLink({required String remoteId})
    : _device = BluetoothDevice.fromId(remoteId);

  final BluetoothDevice _device;

  final _lines = StreamController<String>.broadcast();
  final _states = StreamController<BridgeLinkState>.broadcast();
  final _buffer = SerialLineBuffer();

  BridgeLinkState _state = BridgeLinkState.disconnected;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothCharacteristic? _rx;

  /// Completes when the first connection is fully set up, or fails.
  Completer<void>? _first;

  /// Bumped by [connect] and [disconnect]; stale setups see it and stop.
  int _session = 0;
  bool _everConnected = false;
  bool _disposed = false;

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

    if (!await waitForBluetoothOn(kBluetoothOnTimeout)) {
      _giveUp(session);
      throw _kBluetoothOff;
    }
    if (session != _session) throw _kNotFound;

    final first = _first = Completer<void>();
    _connectionSub = _device.connectionState.listen(
      (s) => _onConnectionState(s, session),
    );
    try {
      // mtu: null, because autoConnect and an MTU request are incompatible
      // in flutter_blue_plus; Android asks for 247 in _setup. With
      // autoConnect this returns once the request is made, not when the
      // bridge answers, so the wait below carries the timeout.
      await _device.connect(autoConnect: true, mtu: null);
      await first.future.timeout(kBridgeFirstConnectTimeout);
    } on TimeoutException {
      await _giveUpAndClose(session);
      throw _kNotFound;
    } on BridgeLinkException {
      await _giveUpAndClose(session);
      rethrow;
    } catch (e) {
      debugPrint('Bridge BLE: connect failed: $e');
      await _giveUpAndClose(session);
      throw _kNotFound;
    }
  }

  void _onConnectionState(BluetoothConnectionState s, int session) {
    if (session != _session) return;
    if (s == BluetoothConnectionState.connected) {
      unawaited(_setup(session));
    } else if (_everConnected) {
      // autoConnect brings the link back by itself.
      _dropNotifications();
      _setState(BridgeLinkState.connecting);
    }
  }

  /// Runs on every connection, the first and each reconnection.
  Future<void> _setup(int session) async {
    StreamSubscription<List<int>>? sub;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final mtu = await _device.requestMtu(_kAndroidMtu);
          debugPrint('Bridge BLE: negotiated MTU=${mtu}B');
        } catch (e) {
          debugPrint('Bridge BLE: requestMtu failed: $e');
        }
        if (session != _session) return;
      }
      final services = await _device.discoverServices();
      if (session != _session) return;
      final (:tx, :rx) = _findCharacteristics(services);

      _buffer.clear();
      // Listen before enabling notifications so nothing is lost.
      sub = tx.onValueReceived.listen(
        _onNotification,
        onError: (Object e) => debugPrint('Bridge BLE: notify error: $e'),
      );
      await tx.setNotifyValue(true);
      if (session != _session) {
        unawaited(sub.cancel());
        return;
      }

      final previous = _notifySub;
      _notifySub = sub;
      _rx = rx;
      unawaited(previous?.cancel());
      _everConnected = true;
      debugPrint('Bridge BLE: connected. MTU=${_device.mtuNow}B');
      _setState(BridgeLinkState.connected);
      final first = _first;
      if (first != null && !first.isCompleted) first.complete();
    } catch (e) {
      unawaited(sub?.cancel());
      if (session != _session) return;
      debugPrint('Bridge BLE: setup failed: $e');
      final first = _first;
      if (first != null && !first.isCompleted) {
        // Only the first connection reports to the caller; a later failure
        // leaves the link connecting and the transport's HELLO timeout
        // speaks.
        first.completeError(
          e is BridgeLinkException
              ? e
              : const BridgeLinkException('Not an Anchorline bridge'),
        );
      }
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
    final chunk = max(_kMinChunk, _device.mtuNow - 3);
    final withoutResponse = !rx.properties.write;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = min(i + chunk, bytes.length);
      try {
        await rx.write(
          bytes.sublist(i, end),
          withoutResponse: withoutResponse,
        );
      } on FlutterBluePlusException catch (e) {
        throw BridgeLinkException('Bridge write failed: ${e.description}');
      } on PlatformException catch (e) {
        throw BridgeLinkException('Bridge write failed: ${e.message}');
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _session++;
    _first = null;
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
    try {
      // queue: false also cancels a connect still in progress and removes
      // the autoConnect request.
      await _device.disconnect(
        queue: false,
        timeout: _kDisconnectTimeoutSeconds,
      );
    } catch (e) {
      debugPrint('Bridge BLE: disconnect failed: $e');
    }
  }

  void _setState(BridgeLinkState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}

({BluetoothCharacteristic tx, BluetoothCharacteristic rx})
_findCharacteristics(List<BluetoothService> services) {
  final serviceUuid = Guid(kNusServiceUuid);
  BluetoothService? service;
  for (final s in services) {
    if (s.uuid == serviceUuid) {
      service = s;
      break;
    }
  }
  const notABridge = BridgeLinkException('Not an Anchorline bridge');
  if (service == null) throw notABridge;
  BluetoothCharacteristic? tx;
  BluetoothCharacteristic? rx;
  for (final c in service.characteristics) {
    if (c.uuid == Guid(kNusTxUuid)) tx = c;
    if (c.uuid == Guid(kNusRxUuid)) rx = c;
  }
  if (tx == null || rx == null) throw notABridge;
  if (!(tx.properties.notify || tx.properties.indicate) ||
      !(rx.properties.write || rx.properties.writeWithoutResponse)) {
    throw notABridge;
  }
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

_BridgeScanRun? _scanRun;

/// Scans for devices that advertise the NUS service AND whose name starts
/// with [kBridgeNamePrefix]. The stream emits the bridges found so far,
/// sorted by name, each time the list changes, and closes when the scan
/// ends. It emits a [BridgeLinkException] first when Bluetooth is off or
/// the scan can't start. A new scan ends the previous one.
Stream<List<FoundBridge>> scanForBridges({
  Duration timeout = const Duration(seconds: 10),
}) {
  _scanRun?.end();
  final run = _BridgeScanRun(timeout);
  _scanRun = run;
  return run.stream;
}

Future<void> stopBridgeScan() async {
  _scanRun?.end();
  _scanRun = null;
  try {
    await FlutterBluePlus.stopScan();
  } catch (e) {
    debugPrint('Bridge BLE: stopScan failed: $e');
  }
}

class _BridgeScanRun {
  _BridgeScanRun(this._timeout) {
    _out = StreamController<List<FoundBridge>>(
      onListen: () => unawaited(_start()),
      onCancel: end,
    );
  }

  final Duration _timeout;
  late final StreamController<List<FoundBridge>> _out;
  final Map<String, FoundBridge> _found = {};
  StreamSubscription<List<ScanResult>>? _results;
  Timer? _timer;
  bool _ended = false;

  Stream<List<FoundBridge>> get stream => _out.stream;

  Future<void> _start() async {
    if (_ended) return;
    if (!await waitForBluetoothOn(kBluetoothOnTimeout)) {
      _fail(_kBluetoothOff);
      return;
    }
    if (_ended) return;
    // Subscribe before the scan so no advertisement is missed. scanResults
    // first re-emits the previous scan's list: skip it.
    _results = FlutterBluePlus.scanResults
        .skip(1)
        .listen(
          _onResults,
          onError: (Object e) {
            debugPrint('Bridge BLE: scan failed: $e');
            _fail(const BridgeLinkException('Bluetooth scan failed'));
          },
        );
    _timer = Timer(_timeout, end);
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(kNusServiceUuid)],
        timeout: _timeout,
      );
    } catch (e) {
      debugPrint('Bridge BLE: startScan failed: $e');
      _fail(const BridgeLinkException('Bluetooth scan failed'));
    }
  }

  void _onResults(List<ScanResult> results) {
    if (_ended) return;
    var changed = false;
    for (final r in results) {
      final name = _nameOf(r);
      if (name == null || !name.startsWith(kBridgeNamePrefix)) continue;
      final id = r.device.remoteId.str;
      if (_found[id]?.name == name) continue;
      _found[id] = FoundBridge(id: id, name: name);
      changed = true;
    }
    if (changed) {
      final list = _found.values.toList()
        ..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });
      _out.add(list);
    }
  }

  void _fail(BridgeLinkException e) {
    if (_ended) return;
    _out.addError(e);
    end();
  }

  void end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_results?.cancel());
    _results = null;
    unawaited(_out.close());
  }
}

String? _nameOf(ScanResult r) {
  for (final name in [
    r.advertisementData.advName,
    r.device.advName,
    r.device.platformName,
  ]) {
    if (name.trim().isNotEmpty) return name.trim();
  }
  return null;
}
