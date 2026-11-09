/// The Bluetooth LE central the SOLO bridge and the label printer share.
///
/// Pure Dart, no Flutter imports. Two implementations sit behind it:
///
///  * `FbpBleCentral` (`fbp_ble_central.dart`) on Android, iOS, macOS and
///    Linux, over `flutter_blue_plus` 1.x.
///  * `WindowsBleCentral` (`windows_ble_central.dart`) on Windows, over the
///    in-app WinRT channel in `windows/runner/ble_central_channel.cpp`.
///    `flutter_blue_plus` 1.x has no Windows support, and 2.x is not open
///    source, so the app carries its own small Windows central.
///
/// `defaultBleCentral()` in `ble_central_default.dart` picks one.
///
/// The Shearwater dive-computer import does not use this seam; it still
/// talks to `flutter_blue_plus` directly.
library;

import 'dart:async';
import 'dart:math' as math;

/// What the Bluetooth adapter is doing.
enum BleAdapterState {
  /// Not known yet (macOS and iOS start here until the user answers the
  /// Bluetooth prompt).
  unknown,

  /// There is no Bluetooth LE adapter, or the app may not use it.
  unavailable,

  /// The adapter is switched off.
  off,

  on,
}

/// A BLE failure. [message] is a short English description for logs and,
/// where nothing better fits, for the user. [code] is one of the
/// `kBle*` codes below, or a platform code passed through.
class BleException implements Exception {
  const BleException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BleException($code): $message';
}

/// Codes a [BleException] can carry. The Windows channel uses the same
/// strings as its PlatformException codes.
const String kBleErrorUnavailable = 'unavailable';
const String kBleErrorBluetoothOff = 'bluetoothOff';
const String kBleErrorNotFound = 'notFound';
const String kBleErrorUnreachable = 'unreachable';
const String kBleErrorNotConnected = 'notConnected';
const String kBleErrorGatt = 'gatt';
const String kBleErrorWriteFailed = 'writeFailed';
const String kBleErrorTimeout = 'timeout';
const String kBleErrorScanFailed = 'scanFailed';
const String kBleErrorBadArgs = 'badArgs';
const String kBleErrorUnknown = 'unknown';

/// One advertisement, or the platform's latest view of a device.
class BleScanResult {
  const BleScanResult({
    required this.id,
    required this.name,
    this.rssi = 0,
    this.serviceUuids = const [],
  });

  /// The id [BleCentral.peripheral] takes. A remote id from
  /// `flutter_blue_plus` (a MAC address on Android and Linux, a UUID on
  /// Apple platforms) or, on Windows, the Bluetooth address as 12 hex
  /// digits.
  final String id;

  /// The advertised name, trimmed, or '' when the device gave none.
  final String name;

  final int rssi;

  /// Advertised service UUIDs, lower case, 128-bit form.
  final List<String> serviceUuids;

  bool advertises(String serviceUuid) =>
      serviceUuids.contains(normalizeBleUuid(serviceUuid));
}

/// What a characteristic supports.
class BleCharacteristicProperties {
  const BleCharacteristicProperties({
    this.read = false,
    this.write = false,
    this.writeWithoutResponse = false,
    this.notify = false,
    this.indicate = false,
  });

  final bool read;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;

  bool get canWrite => write || writeWithoutResponse;
  bool get canNotify => notify || indicate;
}

/// A characteristic found by [BlePeripheral.discoverServices].
abstract class BleCharacteristic {
  /// Lower case, 128-bit form.
  String get serviceUuid;

  /// Lower case, 128-bit form.
  String get uuid;

  BleCharacteristicProperties get properties;

  /// Value notifications (or indications). Listen before [setNotify] so
  /// nothing is lost. The stream stays open across reconnections.
  Stream<List<int>> get notifications;

  /// Turns notifications (or indications, when the characteristic only
  /// indicates) on or off.
  Future<void> setNotify(bool enable);

  /// Writes [value] in one ATT write. Callers chunk to
  /// [BlePeripheral.maxWritePayload]. Throws a [BleException], or a
  /// [TimeoutException] when [timeout] passes.
  Future<void> write(
    List<int> value, {
    required bool withoutResponse,
    Duration timeout = const Duration(seconds: 15),
  });
}

/// A device reached by id.
abstract class BlePeripheral {
  String get id;

  /// The connection state: true when connected. Each listener first gets
  /// the current state, then every change; false comes on any disconnect,
  /// including one asked for.
  Stream<bool> get connectionChanges;

  bool get isConnected;

  /// Connects once. Throws a [BleException] (or a [TimeoutException]) when
  /// the device can't be reached within [timeout].
  ///
  /// With [autoConnect], where [BleCentral.supportsAutoConnect] is true,
  /// this returns as soon as the request is made and the platform
  /// reconnects by itself after every drop until [disconnect]; listen to
  /// [connectionChanges] for the connection.
  Future<void> connect({
    Duration timeout = const Duration(seconds: 10),
    bool autoConnect = false,
  });

  /// Asks for a larger ATT MTU where the platform lets the app ask
  /// (Android). Elsewhere a no-op. Returns the MTU now in use.
  Future<int> requestMtu(int mtu);

  /// The ATT MTU in use (23 until something larger is negotiated).
  int get mtu;

  /// The largest payload one write may carry: [mtu] minus the 3-byte ATT
  /// header, and never below 20.
  int get maxWritePayload => math.max(20, mtu - 3);

  /// Discovers every service and returns their characteristics.
  Future<List<BleCharacteristic>> discoverServices();

  /// Closes the link, stops an [autoConnect] and cancels a connect in
  /// progress. Never throws.
  Future<void> disconnect();
}

/// The phone's or computer's BLE central role.
abstract class BleCentral {
  /// Whether [BlePeripheral.connect] honours `autoConnect`. Where it
  /// doesn't (Windows, Linux), callers that want a lasting link reconnect
  /// themselves.
  bool get supportsAutoConnect;

  BleAdapterState get adapterStateNow;

  /// Every adapter state change. Broadcast.
  Stream<BleAdapterState> get adapterStates;

  /// Scans until [timeout] or [stopScan]. Each event is a device seen (the
  /// same device may come many times). With [withServices], only devices
  /// advertising one of them are reported. The stream ends with the scan.
  /// It fails with a [BleException] when the scan can't start.
  Stream<BleScanResult> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> stopScan();

  /// The device with [id], as returned in [BleScanResult.id].
  BlePeripheral peripheral(String id);
}

/// Waits up to [timeout] for [central]'s adapter to be on and returns the
/// state it ended in: [BleAdapterState.on], or what it was when the wait
/// ran out.
///
/// On macOS and iOS the adapter starts as `unknown` and only reaches `on`
/// once the OS has initialised it and the user has answered the Bluetooth
/// prompt, so the current state alone isn't enough. Cancels its
/// subscription and timer on every exit.
Future<BleAdapterState> waitForAdapterOn(
  BleCentral central,
  Duration timeout,
) async {
  var last = central.adapterStateNow;
  if (last == BleAdapterState.on) return last;
  final done = Completer<BleAdapterState>();
  void settle() {
    if (!done.isCompleted) done.complete(last);
  }

  final timer = Timer(timeout, settle);
  final sub = central.adapterStates.listen(
    (state) {
      last = state;
      if (state == BleAdapterState.on) settle();
    },
    onError: (Object _) => settle(),
  );
  try {
    return await done.future;
  } finally {
    timer.cancel();
    // Not awaited: a platform stream's cancel can wait on a pending call.
    unawaited(sub.cancel());
  }
}

/// The user-facing reason a BLE operation can't start in [state], or null
/// when the adapter is on.
String? bleAdapterProblem(BleAdapterState state) => switch (state) {
  BleAdapterState.on => null,
  BleAdapterState.unavailable => 'Bluetooth LE is not available',
  BleAdapterState.off || BleAdapterState.unknown => 'Bluetooth is off',
};

/// Splits [bytes] into writes of at most [payload] bytes each.
List<List<int>> chunkForWrite(List<int> bytes, int payload) {
  final size = math.max(1, payload);
  return [
    for (var i = 0; i < bytes.length; i += size)
      bytes.sublist(i, math.min(i + size, bytes.length)),
  ];
}

/// The first characteristic [uuid] of service [serviceUuid] in [chars], or
/// null. UUIDs compare case-insensitively.
BleCharacteristic? findCharacteristic(
  List<BleCharacteristic> chars,
  String serviceUuid,
  String uuid,
) {
  final s = normalizeBleUuid(serviceUuid);
  final c = normalizeBleUuid(uuid);
  for (final ch in chars) {
    if (ch.serviceUuid == s && ch.uuid == c) return ch;
  }
  return null;
}

/// The Bluetooth base UUID's tail, after the 32-bit prefix.
const String _kBaseUuidTail = '-0000-1000-8000-00805f9b34fb';

/// [uuid] in lower-case 128-bit form: a 16-bit (`ff00`) or 32-bit short
/// UUID is expanded on the Bluetooth base UUID.
String normalizeBleUuid(String uuid) {
  final u = uuid.trim().toLowerCase();
  if (u.length == 4) return '0000$u$_kBaseUuidTail';
  if (u.length == 8) return '$u$_kBaseUuidTail';
  return u;
}
