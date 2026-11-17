import 'dart:async';

import '../../../_helpers/fake_ble_central.dart';
import 'package:ccrlogger/ble/ble_central.dart';

/// Properties of a characteristic that notifies.
const BleCharacteristicProperties kNotifyProps = BleCharacteristicProperties(
  notify: true,
);

/// Properties of a characteristic that indicates.
const BleCharacteristicProperties kIndicateProps = BleCharacteristicProperties(
  indicate: true,
);

/// Properties of a characteristic written without response.
const BleCharacteristicProperties kWriteNoRspProps =
    BleCharacteristicProperties(writeWithoutResponse: true);

/// Properties of a characteristic written with response only.
const BleCharacteristicProperties kWriteProps = BleCharacteristicProperties(
  write: true,
);

/// Notify and write, as the u-blox FIFO has them.
const BleCharacteristicProperties kNotifyWriteProps =
    BleCharacteristicProperties(notify: true, write: true);

/// A [FakeBlePeripheral] that records the order of calls and can hang its
/// disconnect.
class RecordingPeripheral extends FakeBlePeripheral {
  RecordingPeripheral(super.id, super.central);

  /// 'connect', 'requestMtu', 'discoverServices', 'setNotify', 'pair', ...
  final List<String> calls = [];
  final List<int> mtuRequests = [];

  /// When true, [disconnect] never completes.
  bool hangOnDisconnect = false;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 10),
    bool autoConnect = false,
  }) {
    calls.add('connect');
    return super.connect(timeout: timeout, autoConnect: autoConnect);
  }

  @override
  Future<int> requestMtu(int mtu) {
    calls.add('requestMtu');
    mtuRequests.add(mtu);
    return super.requestMtu(mtu);
  }

  @override
  Future<List<BleCharacteristic>> discoverServices() {
    calls.add('discoverServices');
    return super.discoverServices();
  }

  @override
  Future<bool> pair() {
    calls.add('pair');
    return super.pair();
  }

  @override
  Future<void> disconnect() {
    calls.add('disconnect');
    if (hangOnDisconnect) return Completer<void>().future;
    return super.disconnect();
  }
}

/// A fake GATT table: a [FakeBlePeripheral] on a [FakeBleCentral], with
/// characteristics added service by service. Task 15's stand-in computers
/// reuse it.
class FakeGatt {
  FakeGatt({String id = 'AA:BB:CC:DD:EE:FF', int mtu = 23})
    : central = FakeBleCentral() {
    peripheral = RecordingPeripheral(id, central)..mtu = mtu;
    central.peripherals[id] = peripheral;
  }

  final FakeBleCentral central;
  late final RecordingPeripheral peripheral;

  /// Adds one characteristic and returns it.
  FakeBleCharacteristic add(
    String service,
    String uuid,
    BleCharacteristicProperties properties,
  ) {
    final c = FakeBleCharacteristic(service, uuid, properties: properties);
    c.onSetNotify = () => peripheral.calls.add('setNotify');
    peripheral.characteristics = [...peripheral.characteristics, c];
    return c;
  }

  /// The characteristic [uuid] of [service], which must exist.
  FakeBleCharacteristic operator [](String uuidPair) {
    final parts = uuidPair.split('/');
    return peripheral.characteristics.firstWhere(
          (c) =>
              c.serviceUuid == normalizeBleUuid(parts[0]) &&
              c.uuid == normalizeBleUuid(parts[1]),
        )
        as FakeBleCharacteristic;
  }
}

/// A plain serial-style service: one notify and one write characteristic.
void addSerialService(
  FakeGatt gatt,
  String service, {
  String notifyUuid = '0001',
  String writeUuid = '0002',
  BleCharacteristicProperties writeProps = kWriteNoRspProps,
}) {
  gatt.add(service, notifyUuid, kNotifyProps);
  gatt.add(service, writeUuid, writeProps);
}
