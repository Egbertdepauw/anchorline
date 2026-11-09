import 'dart:async';

import 'package:ccrlogger/ble/ble_central.dart';

/// A [BleCentral] the test drives by hand: it hands out [FakeBlePeripheral]s,
/// records scans and lets the test push advertisements and adapter states.
class FakeBleCentral implements BleCentral {
  FakeBleCentral({
    this.supportsAutoConnect = false,
    BleAdapterState adapter = BleAdapterState.on,
  }) : _adapter = adapter;

  @override
  bool supportsAutoConnect;

  BleAdapterState _adapter;
  final _adapterCtl = StreamController<BleAdapterState>.broadcast();

  /// The service filter of every [scan], in order.
  final List<List<String>> scans = [];
  int stopScanCalls = 0;

  /// When set, the next [scan] fails with it.
  Object? scanError;

  StreamController<BleScanResult>? _scan;

  final Map<String, FakeBlePeripheral> peripherals = {};

  @override
  BleAdapterState get adapterStateNow => _adapter;

  @override
  Stream<BleAdapterState> get adapterStates => _adapterCtl.stream;

  void setAdapter(BleAdapterState s) {
    _adapter = s;
    _adapterCtl.add(s);
  }

  @override
  Stream<BleScanResult> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    scans.add(withServices);
    final c = _scan = StreamController<BleScanResult>();
    final error = scanError;
    if (error != null) {
      scanError = null;
      c.addError(error);
      c.close();
    }
    return c.stream;
  }

  /// Delivers [r] to the running scan.
  void advertise(BleScanResult r) => _scan?.add(r);

  /// Ends the running scan, as the platform does at its timeout.
  Future<void> endScan() async => _scan?.close();

  @override
  Future<void> stopScan() async => stopScanCalls++;

  @override
  FakeBlePeripheral peripheral(String id) =>
      peripherals.putIfAbsent(id, () => FakeBlePeripheral(id, this));
}

class FakeBlePeripheral extends BlePeripheral {
  FakeBlePeripheral(this.id, this._central);

  @override
  final String id;

  final FakeBleCentral _central;

  /// Whether [connect] succeeds.
  bool reachable = true;

  /// What [discoverServices] returns.
  List<BleCharacteristic> characteristics = [];

  @override
  int mtu = 23;

  int connectCalls = 0;
  int autoConnectCalls = 0;
  int disconnectCalls = 0;
  int discoverCalls = 0;
  int pairCalls = 0;

  /// What [pair] returns.
  bool pairResult = false;

  bool _connected = false;
  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionChanges => Stream<bool>.multi((l) {
        l.add(_connected);
        final sub = _changes.stream.listen(l.add);
        l.onCancel = sub.cancel;
      });

  @override
  bool get isConnected => _connected;

  void _set(bool up) {
    if (_connected == up) return;
    _connected = up;
    _changes.add(up);
  }

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 10),
    bool autoConnect = false,
  }) async {
    if (autoConnect && _central.supportsAutoConnect) {
      autoConnectCalls++;
      // The platform connects later, when the device is in range.
      if (reachable) scheduleMicrotask(() => _set(true));
      return;
    }
    connectCalls++;
    if (!reachable) {
      throw const BleException(kBleErrorUnreachable, 'unreachable');
    }
    _set(true);
  }

  /// The device went out of range.
  void drop() => _set(false);

  /// With autoConnect: the platform brought the link back.
  void autoReconnect() => _set(true);

  @override
  Future<int> requestMtu(int mtu) async => this.mtu;

  @override
  Future<List<BleCharacteristic>> discoverServices() async {
    discoverCalls++;
    if (!_connected) {
      throw const BleException(kBleErrorNotConnected, 'not connected');
    }
    return characteristics;
  }

  @override
  Future<bool> pair() async {
    pairCalls++;
    return pairResult;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _set(false);
  }
}

class FakeBleCharacteristic implements BleCharacteristic {
  FakeBleCharacteristic(
    String serviceUuid,
    String uuid, {
    this.properties = const BleCharacteristicProperties(),
  })  : serviceUuid = normalizeBleUuid(serviceUuid),
        uuid = normalizeBleUuid(uuid);

  @override
  final String serviceUuid;

  @override
  final String uuid;

  @override
  final BleCharacteristicProperties properties;

  /// Every write, in order, with its mode.
  final List<({List<int> value, bool withoutResponse})> writes = [];
  final List<bool> notifyCalls = [];

  /// When set, [write] throws it.
  Object? writeError;

  /// When set, [setNotify] throws it.
  Object? notifyError;

  final _notifications = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  /// Delivers one notification.
  void notify(List<int> value) => _notifications.add(value);

  @override
  Future<void> setNotify(bool enable) async {
    notifyCalls.add(enable);
    final error = notifyError;
    if (error != null) throw error;
  }

  @override
  Future<void> write(
    List<int> value, {
    required bool withoutResponse,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final error = writeError;
    if (error != null) throw error;
    writes.add((value: List.of(value), withoutResponse: withoutResponse));
  }
}
