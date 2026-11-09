/// [BleCentral] on Windows, over the in-app WinRT channel
/// (`windows/runner/ble_central_channel.cpp`).
///
/// `flutter_blue_plus` 1.x has no Windows support and 2.x is not open
/// source, so the Windows runner carries a small BLE central of its own
/// (`Windows.Devices.Bluetooth`), the same in-app-channel style as the
/// Android USB serial channel (`UsbSerialChannel.kt`).
///
/// Method channel [kWindowsBleMethodChannel]:
///
/// | method        | arguments                                   | result |
/// |---------------|---------------------------------------------|--------|
/// | `adapterState`| –                                           | `'on'`, `'off'`, `'unavailable'` or `'unknown'` |
/// | `startScan`   | –                                           | – |
/// | `stopScan`    | –                                           | – |
/// | `connect`     | `id`                                        | `{mtu}` |
/// | `discover`    | `id`                                        | `[{service, characteristic, properties}]` |
/// | `setNotify`   | `id, service, characteristic, enable`       | – |
/// | `write`       | `id, service, characteristic, value, withoutResponse` | – |
/// | `disconnect`  | `id`                                        | – |
///
/// `id` is the Bluetooth address as 12 hex digits. `properties` is a bit
/// set: 1 read, 2 write, 4 write without response, 8 notify, 16 indicate.
/// Failures are PlatformExceptions whose codes are the `kBleError*` codes.
///
/// Event channel [kWindowsBleEventChannel]: maps with an `event` key, see
/// [decodeWindowsBleEvent].
///
/// Windows reconnects nothing by itself here, so [supportsAutoConnect] is
/// false and the bridge link reconnects in Dart.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_central.dart';

const String kWindowsBleMethodChannel = 'nl.despaankamer.ccrlogger/ble';
const String kWindowsBleEventChannel = 'nl.despaankamer.ccrlogger/ble/events';

/// The default ATT MTU, until the session reports a larger one.
const int _kDefaultMtu = 23;

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Something the Windows channel reports.
sealed class WindowsBleEvent {
  const WindowsBleEvent();
}

/// An advertisement or scan response.
class WindowsBleAdvertisement extends WindowsBleEvent {
  const WindowsBleAdvertisement(this.result);
  final BleScanResult result;
}

/// The watcher stopped: at [WindowsBleCentral.stopScan], or by itself with
/// [error] (say the radio went off).
class WindowsBleScanStopped extends WindowsBleEvent {
  const WindowsBleScanStopped(this.error);
  final String? error;
}

/// The device [id] connected or dropped.
class WindowsBleConnection extends WindowsBleEvent {
  const WindowsBleConnection(this.id, {required this.connected});
  final String id;
  final bool connected;
}

/// A notification or indication.
class WindowsBleNotification extends WindowsBleEvent {
  const WindowsBleNotification(
    this.id,
    this.serviceUuid,
    this.characteristicUuid,
    this.value,
  );
  final String id;
  final String serviceUuid;
  final String characteristicUuid;
  final Uint8List value;
}

/// The session's MaxPduSize (the ATT MTU) changed.
class WindowsBleMtu extends WindowsBleEvent {
  const WindowsBleMtu(this.id, this.mtu);
  final String id;
  final int mtu;
}

/// The radio was switched on or off.
class WindowsBleAdapter extends WindowsBleEvent {
  const WindowsBleAdapter(this.state);
  final BleAdapterState state;
}

/// Decodes one event-channel message, or returns null for anything it
/// doesn't know (a newer runner, say).
WindowsBleEvent? decodeWindowsBleEvent(Object? raw) {
  if (raw is! Map) return null;
  String? str(String key) => raw[key] is String ? raw[key] as String : null;
  final id = str('id');
  switch (raw['event']) {
    case 'scan':
      if (id == null) return null;
      final services = raw['services'];
      return WindowsBleAdvertisement(
        BleScanResult(
          id: id,
          name: (str('name') ?? '').trim(),
          rssi: raw['rssi'] is int ? raw['rssi'] as int : 0,
          serviceUuids: [
            if (services is List)
              for (final s in services)
                if (s is String) normalizeBleUuid(s),
          ],
        ),
      );
    case 'scanStopped':
      return WindowsBleScanStopped(str('error'));
    case 'connection':
      if (id == null) return null;
      return WindowsBleConnection(id, connected: raw['connected'] == true);
    case 'notify':
      final service = str('service');
      final characteristic = str('characteristic');
      final value = raw['value'];
      if (id == null || service == null || characteristic == null) {
        return null;
      }
      return WindowsBleNotification(
        id,
        normalizeBleUuid(service),
        normalizeBleUuid(characteristic),
        value is Uint8List
            ? value
            : Uint8List.fromList([
                if (value is List)
                  for (final b in value)
                    if (b is int) b,
              ]),
      );
    case 'mtu':
      final mtu = raw['mtu'];
      if (id == null || mtu is! int) return null;
      return WindowsBleMtu(id, mtu);
    case 'adapter':
      return WindowsBleAdapter(decodeWindowsAdapterState(str('state')));
  }
  return null;
}

BleAdapterState decodeWindowsAdapterState(String? s) => switch (s) {
      'on' => BleAdapterState.on,
      'off' => BleAdapterState.off,
      'unavailable' => BleAdapterState.unavailable,
      _ => BleAdapterState.unknown,
    };

/// Windows reports an advertisement and its scan response as separate
/// events: the bridge puts its service UUID in one and its name in the
/// other. This merges them per device and applies the service filter.
class WindowsScanMerger {
  WindowsScanMerger(List<String> withServices)
      : _filter = {for (final s in withServices) normalizeBleUuid(s)};

  final Set<String> _filter;
  final Map<String, BleScanResult> _seen = {};

  /// The device as seen so far, or null while it doesn't pass the filter.
  BleScanResult? add(BleScanResult r) {
    final old = _seen[r.id];
    final merged = BleScanResult(
      id: r.id,
      name: r.name.isNotEmpty ? r.name : (old?.name ?? ''),
      rssi: r.rssi,
      serviceUuids: {...?old?.serviceUuids, ...r.serviceUuids}.toList(),
    );
    _seen[r.id] = merged;
    if (_filter.isNotEmpty && !merged.serviceUuids.any(_filter.contains)) {
      return null;
    }
    return merged;
  }
}

BleException _bleError(PlatformException e) =>
    BleException(e.code, e.message ?? e.code);

// ---------------------------------------------------------------------------
// Central
// ---------------------------------------------------------------------------

class WindowsBleCentral implements BleCentral {
  WindowsBleCentral({
    MethodChannel methods = const MethodChannel(kWindowsBleMethodChannel),
    EventChannel events = const EventChannel(kWindowsBleEventChannel),
  })  : _methods = methods,
        _eventChannel = events;

  final MethodChannel _methods;
  final EventChannel _eventChannel;

  StreamSubscription<Object?>? _eventsSub;
  BleAdapterState _adapter = BleAdapterState.unknown;
  final _adapterCtl = StreamController<BleAdapterState>.broadcast();
  final Map<String, WindowsBlePeripheral> _peripherals = {};

  _WindowsScan? _scan;

  @override
  bool get supportsAutoConnect => false;

  @override
  BleAdapterState get adapterStateNow => _adapter;

  /// Each listener gets the state the channel reports next (asked for at
  /// once), then every change.
  @override
  Stream<BleAdapterState> get adapterStates {
    _ensureEvents();
    unawaited(_refreshAdapter());
    return _adapterCtl.stream;
  }

  Future<void> _refreshAdapter() async {
    BleAdapterState state;
    try {
      state = decodeWindowsAdapterState(
        await _methods.invokeMethod<String>('adapterState'),
      );
    } on PlatformException catch (e) {
      debugPrint('BLE (Windows): adapterState failed: ${e.message}');
      state = BleAdapterState.unavailable;
    } on MissingPluginException {
      state = BleAdapterState.unavailable;
    }
    _setAdapter(state, force: true);
  }

  void _setAdapter(BleAdapterState s, {bool force = false}) {
    if (s == _adapter && !force) return;
    _adapter = s;
    if (!_adapterCtl.isClosed) _adapterCtl.add(s);
  }

  void _ensureEvents() {
    _eventsSub ??= _eventChannel.receiveBroadcastStream().listen(
      (raw) {
        final e = decodeWindowsBleEvent(raw);
        if (e != null) _onEvent(e);
      },
      onError: (Object e) => debugPrint('BLE (Windows): event error: $e'),
    );
  }

  void _onEvent(WindowsBleEvent e) {
    switch (e) {
      case WindowsBleAdvertisement(:final result):
        _scan?.onResult(result);
      case WindowsBleScanStopped(:final error):
        _scan?.onStopped(error);
      case WindowsBleConnection(:final id, :final connected):
        _peripherals[id.toUpperCase()]?._setConnected(connected);
      case WindowsBleNotification():
        _peripherals[e.id.toUpperCase()]?._onNotification(e);
      case WindowsBleMtu(:final id, :final mtu):
        _peripherals[id.toUpperCase()]?._mtu = mtu;
      case WindowsBleAdapter(:final state):
        _setAdapter(state);
    }
  }

  @override
  Stream<BleScanResult> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    _ensureEvents();
    _scan?.close();
    final run = _WindowsScan(this, WindowsScanMerger(withServices), timeout);
    _scan = run;
    return run.stream;
  }

  @override
  Future<void> stopScan() async {
    _scan?.close();
    _scan = null;
    await _stopNativeScan();
  }

  Future<void> _stopNativeScan() async {
    try {
      await _methods.invokeMethod<void>('stopScan');
    } catch (e) {
      debugPrint('BLE (Windows): stopScan failed: $e');
    }
  }

  @override
  BlePeripheral peripheral(String id) {
    _ensureEvents();
    return _peripherals.putIfAbsent(
      id.toUpperCase(),
      () => WindowsBlePeripheral._(this, id.toUpperCase()),
    );
  }
}

/// One scan: started on listen, ended by its timer, by the watcher
/// stopping, by a newer scan or by cancelling the subscription.
class _WindowsScan {
  _WindowsScan(this._central, this._merger, Duration timeout) {
    _out = StreamController<BleScanResult>(
      onListen: () {
        _timer = Timer(timeout, () {
          close();
          unawaited(_central._stopNativeScan());
        });
        unawaited(_start());
      },
      onCancel: () {
        final wasClosed = _closed;
        _cancelled = true;
        close();
        if (!wasClosed) unawaited(_central._stopNativeScan());
      },
    );
  }

  final WindowsBleCentral _central;
  final WindowsScanMerger _merger;
  late final StreamController<BleScanResult> _out;
  Timer? _timer;
  bool _closed = false;
  bool _cancelled = false;

  Stream<BleScanResult> get stream => _out.stream;

  Future<void> _start() async {
    try {
      await _central._methods.invokeMethod<void>('startScan');
    } on PlatformException catch (e) {
      debugPrint('BLE (Windows): startScan failed: ${e.code} ${e.message}');
      _fail(_bleError(e));
    } on MissingPluginException {
      _fail(const BleException(kBleErrorUnavailable, 'No BLE channel'));
    }
  }

  void onResult(BleScanResult r) {
    if (_closed) return;
    final merged = _merger.add(r);
    if (merged != null) _out.add(merged);
  }

  void onStopped(String? error) {
    if (_closed) return;
    if (error != null) {
      _fail(BleException(kBleErrorScanFailed, error));
    } else {
      close();
    }
  }

  void _fail(BleException e) {
    if (_closed) return;
    _out.addError(e);
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    if (identical(_central._scan, this)) _central._scan = null;
    // After a cancel nobody listens: nothing to close.
    if (!_cancelled) unawaited(_out.close());
  }
}

// ---------------------------------------------------------------------------
// Peripheral
// ---------------------------------------------------------------------------

class WindowsBlePeripheral extends BlePeripheral {
  WindowsBlePeripheral._(this._central, this.id);

  final WindowsBleCentral _central;

  @override
  final String id;

  bool _connected = false;
  int _mtu = _kDefaultMtu;
  final _changes = StreamController<bool>.broadcast();

  /// Notification streams by `service|characteristic`, kept across
  /// reconnections.
  final Map<String, StreamController<List<int>>> _notify = {};

  MethodChannel get _methods => _central._methods;

  @override
  Stream<bool> get connectionChanges => Stream<bool>.multi((listener) {
        listener.add(_connected);
        final sub = _changes.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = sub.cancel;
      });

  @override
  bool get isConnected => _connected;

  void _setConnected(bool up) {
    if (up == _connected) return;
    _connected = up;
    if (!up) _mtu = _kDefaultMtu;
    if (!_changes.isClosed) _changes.add(up);
  }

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 10),
    bool autoConnect = false,
  }) async {
    try {
      final r = await _methods
          .invokeMapMethod<String, Object?>('connect', {'id': id})
          .timeout(timeout);
      final mtu = r?['mtu'];
      if (mtu is int && mtu > 0) _mtu = mtu;
      _setConnected(true);
    } on TimeoutException {
      // Cancels the attempt still running on the native side.
      await disconnect();
      rethrow;
    } on PlatformException catch (e) {
      throw _bleError(e);
    } on MissingPluginException {
      throw const BleException(kBleErrorUnavailable, 'No BLE channel');
    }
  }

  /// Windows negotiates the MTU itself; this reports what it settled on.
  @override
  Future<int> requestMtu(int mtu) async => _mtu;

  @override
  int get mtu => _mtu;

  @override
  Future<List<BleCharacteristic>> discoverServices() async {
    final List<Object?>? raw;
    try {
      raw = await _methods.invokeListMethod<Object?>('discover', {'id': id});
    } on PlatformException catch (e) {
      throw _bleError(e);
    }
    return [
      for (final m in raw ?? const <Object?>[])
        if (m is Map &&
            m['service'] is String &&
            m['characteristic'] is String)
          WindowsBleCharacteristic._(
            this,
            normalizeBleUuid(m['service'] as String),
            normalizeBleUuid(m['characteristic'] as String),
            decodeWindowsProperties(
              m['properties'] is int ? m['properties'] as int : 0,
            ),
          ),
    ];
  }

  StreamController<List<int>> _notifyFor(String service, String char) =>
      _notify.putIfAbsent(
        '$service|$char',
        StreamController<List<int>>.broadcast,
      );

  void _onNotification(WindowsBleNotification e) {
    final c = _notify['${e.serviceUuid}|${e.characteristicUuid}'];
    if (c != null && !c.isClosed) c.add(e.value);
  }

  @override
  Future<void> disconnect() async {
    try {
      await _methods.invokeMethod<void>('disconnect', {'id': id});
    } catch (e) {
      debugPrint('BLE (Windows): disconnect failed: $e');
    }
    _setConnected(false);
  }
}

/// Decodes the channel's property bit set.
BleCharacteristicProperties decodeWindowsProperties(int bits) =>
    BleCharacteristicProperties(
      read: bits & 1 != 0,
      write: bits & 2 != 0,
      writeWithoutResponse: bits & 4 != 0,
      notify: bits & 8 != 0,
      indicate: bits & 16 != 0,
    );

class WindowsBleCharacteristic implements BleCharacteristic {
  WindowsBleCharacteristic._(
    this._peripheral,
    this.serviceUuid,
    this.uuid,
    this.properties,
  );

  final WindowsBlePeripheral _peripheral;

  @override
  final String serviceUuid;

  @override
  final String uuid;

  @override
  final BleCharacteristicProperties properties;

  Map<String, Object?> get _args => {
        'id': _peripheral.id,
        'service': serviceUuid,
        'characteristic': uuid,
      };

  @override
  Stream<List<int>> get notifications =>
      _peripheral._notifyFor(serviceUuid, uuid).stream;

  @override
  Future<void> setNotify(bool enable) async {
    try {
      await _peripheral._methods.invokeMethod<void>(
        'setNotify',
        {..._args, 'enable': enable},
      );
    } on PlatformException catch (e) {
      throw _bleError(e);
    }
  }

  @override
  Future<void> write(
    List<int> value, {
    required bool withoutResponse,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      await _peripheral._methods.invokeMethod<void>('write', {
        ..._args,
        'value': Uint8List.fromList(value),
        'withoutResponse': withoutResponse,
      }).timeout(timeout);
    } on PlatformException catch (e) {
      throw _bleError(e);
    }
  }
}
