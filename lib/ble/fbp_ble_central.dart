/// [BleCentral] over `flutter_blue_plus` 1.x: Android, iOS, macOS and
/// Linux (BlueZ over D-Bus).
///
/// A thin adapter with no logic of its own beyond translating types and
/// errors: what the bridge link and the printer did with
/// `flutter_blue_plus` before the seam, they now do through this, so
/// behaviour on Android, iOS and macOS is unchanged. Checked on the bench,
/// not in unit tests.
///
/// Linux differs in two ways, both from `flutter_blue_plus_linux`:
///
///  * `autoConnect` is not honoured (a drop is retried once, then never),
///    so [supportsAutoConnect] is false there and callers reconnect
///    themselves.
///  * BlueZ only connects to a device it has seen. A device last seen
///    minutes ago is forgotten, so [FbpBlePeripheral.connect] first scans
///    briefly until the device shows up.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_central.dart';
import 'ble_log.dart';

bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// How long `disconnect()` waits for the link to report closed, in seconds.
/// Shorter than the `flutter_blue_plus` default of 35 s, so a stuck stack
/// can't hold anyone up.
const int _kDisconnectTimeoutSeconds = 5;

class FbpBleCentral implements BleCentral {
  FbpBleCentral();

  @override
  bool get supportsAutoConnect => !_isLinux;

  @override
  BleAdapterState get adapterStateNow =>
      _adapterState(FlutterBluePlus.adapterStateNow);

  @override
  Stream<BleAdapterState> get adapterStates =>
      FlutterBluePlus.adapterState.map(_adapterState);

  @override
  Stream<BleScanResult> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    StreamSubscription<List<ScanResult>>? results;
    StreamSubscription<bool>? scanning;
    var closed = false;
    var cancelled = false;
    late final StreamController<BleScanResult> out;

    void close() {
      if (closed) return;
      closed = true;
      unawaited(results?.cancel());
      unawaited(scanning?.cancel());
      // After a cancel nobody listens: nothing to close.
      if (!cancelled) unawaited(out.close());
    }

    Future<void> start() async {
      // Subscribe before the scan so no advertisement is missed.
      // scanResults first re-emits the previous scan's list, which may
      // hold devices no longer in range: skip it.
      results = FlutterBluePlus.scanResults.skip(1).listen(
        (list) {
          if (closed) return;
          for (final r in list) {
            out.add(_scanResult(r));
          }
        },
        onError: (Object e) {
          bleLog('BLE: scan failed: $e');
          if (closed) return;
          out.addError(const BleException(kBleErrorScanFailed, 'Scan failed'));
          close();
        },
      );
      try {
        await FlutterBluePlus.startScan(
          withServices: [for (final s in withServices) Guid(s)],
          timeout: timeout,
        );
      } catch (e) {
        bleLog('BLE: startScan failed: $e');
        if (closed) return;
        out.addError(const BleException(kBleErrorScanFailed, 'Scan failed'));
        close();
        return;
      }
      if (closed) return;
      // isScanning re-emits true first; the scan is over at the next false.
      scanning = FlutterBluePlus.isScanning.where((s) => !s).listen((_) {
        close();
      });
    }

    out = StreamController<BleScanResult>(
      onListen: () => unawaited(start()),
      onCancel: () {
        final wasClosed = closed;
        cancelled = true;
        close();
        if (!wasClosed) unawaited(stopScan());
      },
    );
    return out.stream;
  }

  @override
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      bleLog('BLE: stopScan failed: $e');
    }
  }

  @override
  BlePeripheral peripheral(String id) =>
      FbpBlePeripheral(BluetoothDevice.fromId(id), this);

  @override
  BlePeripheral? classicSerialPeripheral(
    String id, {
    required String serviceUuid,
    required String writeUuid,
    required String notifyUuid,
  }) =>
      null;
}

class FbpBlePeripheral extends BlePeripheral {
  FbpBlePeripheral(this._device, this._central);

  final BluetoothDevice _device;
  final FbpBleCentral _central;

  @override
  String get id => _device.remoteId.str;

  @override
  Stream<bool> get connectionChanges => _device.connectionState
      .map((s) => s == BluetoothConnectionState.connected);

  @override
  bool get isConnected => _device.isConnected;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 10),
    bool autoConnect = false,
  }) async {
    final auto = autoConnect && _central.supportsAutoConnect;
    try {
      if (_isLinux) await _seeOnLinux(timeout);
      // mtu: null: flutter_blue_plus would otherwise ask for 512 inside
      // connect(), where a refusal fails the connect, and an MTU request
      // is incompatible with autoConnect anyway. Android asks for its MTU
      // through requestMtu.
      await _device.connect(timeout: timeout, mtu: null, autoConnect: auto);
    } catch (e) {
      throw _translate(e, kBleErrorUnreachable);
    }
  }

  /// BlueZ connects only to a device in its cache, and drops a device it
  /// hasn't seen for a while. Scan until [id] shows up, for at most
  /// [timeout]; if it never does, connect anyway and let BlueZ say no.
  Future<void> _seeOnLinux(Duration timeout) async {
    if (_device.isConnected) return;
    final seen = Completer<void>();
    final sub = _central.scan(timeout: timeout).listen(
      (r) {
        if (r.id == id && !seen.isCompleted) seen.complete();
      },
      onError: (Object _) {
        if (!seen.isCompleted) seen.complete();
      },
      onDone: () {
        if (!seen.isCompleted) seen.complete();
      },
    );
    try {
      await seen.future.timeout(timeout, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    if (!_isAndroid) return _device.mtuNow;
    try {
      return await _device.requestMtu(mtu);
    } catch (e) {
      throw _translate(e, kBleErrorGatt);
    }
  }

  @override
  int get mtu => _device.mtuNow;

  @override
  Future<List<BleCharacteristic>> discoverServices() async {
    final List<BluetoothService> services;
    try {
      services = await _device.discoverServices();
    } catch (e) {
      throw _translate(e, kBleErrorGatt);
    }
    return [
      for (final s in services)
        for (final c in s.characteristics) _FbpCharacteristic(c),
    ];
  }

  @override
  Future<void> disconnect() async {
    try {
      // queue: false skips the flutter_blue_plus operation queue, so this
      // also cancels a connect still in progress and removes an
      // autoConnect request.
      await _device.disconnect(
        queue: false,
        timeout: _kDisconnectTimeoutSeconds,
      );
    } catch (e) {
      bleLog('BLE: disconnect failed: $e');
    }
  }
}

class _FbpCharacteristic implements BleCharacteristic {
  _FbpCharacteristic(this._c)
      : properties = BleCharacteristicProperties(
          read: _c.properties.read,
          write: _c.properties.write,
          writeWithoutResponse: _c.properties.writeWithoutResponse,
          notify: _c.properties.notify,
          indicate: _c.properties.indicate,
        );

  final BluetoothCharacteristic _c;

  @override
  final BleCharacteristicProperties properties;

  @override
  String get serviceUuid => _c.serviceUuid.str128.toLowerCase();

  @override
  String get uuid => _c.characteristicUuid.str128.toLowerCase();

  @override
  Stream<List<int>> get notifications => _c.onValueReceived;

  @override
  Future<void> setNotify(bool enable) async {
    try {
      await _c.setNotifyValue(enable);
    } catch (e) {
      throw _translate(e, kBleErrorGatt);
    }
  }

  @override
  Future<void> write(
    List<int> value, {
    required bool withoutResponse,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      await _c.write(
        value,
        withoutResponse: withoutResponse,
        timeout: timeout.inSeconds,
      );
    } catch (e) {
      throw _translate(e, kBleErrorWriteFailed);
    }
  }
}

/// A `flutter_blue_plus` timeout becomes a [TimeoutException]; any other
/// platform failure a [BleException] with [code].
Object _translate(Object e, String code) {
  if (e is BleException || e is TimeoutException) return e;
  if (e is FlutterBluePlusException) {
    if (e.platform == ErrorPlatform.fbp &&
        e.code == FbpErrorCode.timeout.index) {
      return TimeoutException(e.description ?? 'timeout');
    }
    return BleException(code, e.description ?? e.toString());
  }
  if (e is PlatformException) {
    return BleException(code, e.message ?? e.code);
  }
  // flutter_blue_plus_linux throws a StateError for a device BlueZ
  // doesn't know.
  if (e is StateError) return BleException(kBleErrorNotFound, e.message);
  return BleException(code, e.toString());
}

BleScanResult _scanResult(ScanResult r) => BleScanResult(
      id: r.device.remoteId.str,
      name: _nameOf(r),
      rssi: r.rssi,
      serviceUuids: [
        for (final g in r.advertisementData.serviceUuids)
          g.str128.toLowerCase(),
      ],
    );

/// The advertised name, falling back to the name the platform keeps for
/// the device (`device.advName` holds the last name the device
/// advertised, for packets that carry none), or ''.
String _nameOf(ScanResult r) {
  for (final name in [
    r.advertisementData.advName,
    r.device.advName,
    r.device.platformName,
  ]) {
    if (name.trim().isNotEmpty) return name.trim();
  }
  return '';
}

BleAdapterState _adapterState(BluetoothAdapterState s) => switch (s) {
      BluetoothAdapterState.on => BleAdapterState.on,
      // A denied Bluetooth permission reads as off, which is what the
      // app has always told the user then.
      BluetoothAdapterState.off ||
      BluetoothAdapterState.turningOff ||
      BluetoothAdapterState.turningOn ||
      BluetoothAdapterState.unauthorized =>
        BleAdapterState.off,
      BluetoothAdapterState.unavailable => BleAdapterState.unavailable,
      BluetoothAdapterState.unknown => BleAdapterState.unknown,
    };
