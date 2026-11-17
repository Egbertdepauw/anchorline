/// The Bluetooth link a libdivecomputer download uses, over the app's
/// [BleCentral] seam (`lib/ble/`).
///
/// It connects, picks the GATT service the way [LibdcBleProfile] describes,
/// turns on notifications and exposes the result as a [LibdcBleLink]: a
/// byte stream in, chunked writes out. Hardware (HW) computers behind a
/// Telit or u-blox serial bridge also get credit-based flow control.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';

import '../../ble/ble_central.dart';
import '../../ble/ble_log.dart';
import 'libdc_ble_profile.dart';

/// The ATT MTU asked for. Only Android lets the app ask.
const int _kMtu = 517;

const Duration _kConnectTimeout = Duration(seconds: 15);
const Duration _kCloseTimeout = Duration(seconds: 3);

/// How long discovering services or turning on notifications may take, so a
/// platform call that hangs (Windows) can't hang the connect.
const Duration _kStepTimeout = Duration(seconds: 15);

/// Credits granted at connect, and when the device runs low.
const int _kInitialCredits = 254;
const int _kCreditLowWater = 32;
const int _kCreditRefill = 222;

const String _kTelitService = '0000fefb-0000-1000-8000-00805f9b34fb';
const String _kTelitWrite = '00000001-0000-1000-8000-008025000000';
const String _kTelitData = '00000002-0000-1000-8000-008025000000';
const String _kTelitCreditOut = '00000003-0000-1000-8000-008025000000';
const String _kTelitCreditIn = '00000004-0000-1000-8000-008025000000';

const String _kUbloxService = '2456e1b9-26e2-8f83-e744-f34f01e9d701';
const String _kUbloxData = '2456e1b9-26e2-8f83-e744-f34f01e9d703';
const String _kUbloxCredit = '2456e1b9-26e2-8f83-e744-f34f01e9d704';

/// The characteristics chosen for a link.
class _Gatt {
  _Gatt({
    required this.data,
    required this.write,
    this.creditOut,
    this.creditIn,
  });

  /// Where the device's bytes come in.
  final BleCharacteristic data;

  /// Where bytes to the device go.
  final BleCharacteristic write;

  /// Telit/u-blox only: where credits go out (written with response).
  final BleCharacteristic? creditOut;

  /// Telit/u-blox only: where the device's credit indications come in.
  final BleCharacteristic? creditIn;
}

class BleCentralLibdcLink implements LibdcBleLink {
  BleCentralLibdcLink._(
    this._device,
    this.advertisedName,
    this._gatt,
    this.gattSummary,
  );

  final BlePeripheral _device;
  final _Gatt _gatt;

  @override
  final String advertisedName;

  /// One line per service and characteristic, with its properties, for the
  /// recording.
  final List<String> gattSummary;

  final _data = StreamController<Uint8List>();
  final _disconnected = Completer<void>();
  final List<StreamSubscription<Object?>> _subs = [];

  /// Credits the device still holds, when flow control is on.
  int? _credits;

  Future<void> _writeChain = Future<void>.value();
  Future<void> _creditChain = Future<void>.value();
  Future<void>? _closing;

  /// Connects to [deviceId], chooses the GATT, turns on notifications and
  /// sets up credits when the profile asks for them.
  ///
  /// [pairOnNotifyFailure] says that a failure to turn on notifications
  /// means the device needs pairing in the app (Windows): the link then
  /// calls [BlePeripheral.pair] once and retries once.
  static Future<BleCentralLibdcLink> connect(
    BleCentral central,
    String deviceId, {
    required String advertisedName,
    required LibdcBleProfile profile,
    bool? pairOnNotifyFailure,
  }) async {
    final pair = pairOnNotifyFailure ?? Platform.isWindows;
    final device = central.peripheral(deviceId);
    BleCentralLibdcLink? link;
    try {
      await device.connect(timeout: _kConnectTimeout);
      try {
        await device.requestMtu(_kMtu);
      } on Object {
        // A larger MTU is an optimisation; carry on with what we have.
      }
      final chars = await device.discoverServices().timeout(_kStepTimeout);
      final gatt = _chooseGatt(chars, profile);
      if (gatt == null) {
        throw const BleException(
          kBleErrorGatt,
          'No usable serial service on the device',
        );
      }
      link = BleCentralLibdcLink._(
        device,
        advertisedName,
        gatt,
        _summarise(chars),
      );
      await link._start(pair);
      return link;
    } on Object {
      // One disconnect (close() does it), the whole cleanup bounded.
      try {
        await (link?.close() ?? device.disconnect()).timeout(_kCloseTimeout);
      } on Object {
        // Cleanup never masks the real failure.
      }
      rethrow;
    }
  }

  Future<void> _start(bool pairOnNotifyFailure) async {
    // Listen to the connection first, so a drop during setup is seen.
    _subs.add(
      _device.connectionChanges.listen((up) {
        if (!up && !_disconnected.isCompleted) _disconnected.complete();
      }),
    );

    final creditIn = _gatt.creditIn;
    if (creditIn != null) {
      // The device's own credits aren't needed to pace our (small) writes,
      // but its indications must be on and consumed.
      _subs.add(creditIn.notifications.listen((_) {}));
    }
    // Listen before setNotify, so no packet is lost.
    _subs.add(_gatt.data.notifications.listen(_onData));

    await _enableNotify(_gatt.data, pairOnNotifyFailure);
    if (creditIn != null) {
      await _enableNotify(creditIn, pairOnNotifyFailure);
    }
    if (_gatt.creditOut != null) {
      _credits = _kInitialCredits;
      await _gatt.creditOut!.write([_kInitialCredits], withoutResponse: false);
    }
  }

  Future<void> _enableNotify(BleCharacteristic c, bool pairOnFailure) async {
    try {
      await c.setNotify(true).timeout(_kStepTimeout);
    } on Object {
      if (!pairOnFailure) rethrow;
      await _device.pair();
      await c.setNotify(true).timeout(_kStepTimeout);
    }
  }

  void _onData(List<int> value) {
    if (_closing != null) return;
    _data.add(Uint8List.fromList(value));
    final credits = _credits;
    if (credits == null) return;
    // Credits are counted on data packets only. The credits the device
    // grants us are deliberately not tracked, as in Subsurface: libdc's
    // OSTC writes are 20-byte request/response packets, so pacing writes
    // isn't needed for downloads.
    var left = credits - 1;
    if (left <= _kCreditLowWater) {
      left += _kCreditRefill;
      final out = _gatt.creditOut!;
      _creditChain = _creditChain.then(
        (_) => out.write([_kCreditRefill], withoutResponse: false).catchError((
          Object _,
        ) {
          // Take the grant back, so the next data packet tries again.
          if (_credits != null) _credits = _credits! - _kCreditRefill;
          bleLog('libdc: credit grant failed, will retry on the next packet');
        }),
      );
    }
    _credits = left;
  }

  @override
  Stream<Uint8List> get notifications => _data.stream;

  @override
  Future<void> get disconnected => _disconnected.future;

  @override
  Future<void> write(Uint8List bytes) {
    final result = _writeChain.then((_) async {
      final withoutResponse = _gatt.write.properties.writeWithoutResponse;
      for (final chunk in chunkForWrite(bytes, _device.maxWritePayload)) {
        await _gatt.write.write(chunk, withoutResponse: withoutResponse);
      }
    });
    // A failed write must not poison the writes after it.
    _writeChain = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<Uint8List> readCharacteristic(String uuid) async =>
      throw UnsupportedError('Reading a characteristic is not supported yet');

  @override
  Future<void> writeCharacteristic(String uuid, Uint8List bytes) async =>
      throw UnsupportedError('Writing a characteristic is not supported yet');

  /// Closes the link. Takes at most 3 seconds; calling it again returns
  /// the same future.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    try {
      await _device.disconnect().timeout(_kCloseTimeout);
    } on Object {
      // Closing never throws.
    }
    if (!_disconnected.isCompleted) _disconnected.complete();
    // Not awaited: with no listener, a controller's close() never completes.
    unawaited(_data.close());
  }
}

bool _isStandard(String service) =>
    service.endsWith('-0000-1000-8000-00805f9b34fb');

_Gatt? _chooseGatt(List<BleCharacteristic> chars, LibdcBleProfile profile) {
  // Group by service, in discovery order.
  final services = <String, List<BleCharacteristic>>{};
  for (final c in chars) {
    (services[c.serviceUuid] ??= []).add(c);
  }
  final known = [
    for (final s in profile.preferredServices) normalizeBleUuid(s),
  ];

  _Gatt? tryService(String service) {
    final cs = services[service]!;
    if (profile.flowControl == LibdcFlowControl.telitCredits &&
        (service == _kTelitService || service == _kUbloxService)) {
      // An incomplete credit layout is never used without credits: the
      // device would not send.
      return _creditGatt(service, cs);
    }
    BleCharacteristic? data;
    BleCharacteristic? write;
    for (final c in cs) {
      if (data == null &&
          c.properties.canNotify &&
          !profile.ignoreForRead.contains(c.uuid)) {
        data = c;
      }
    }
    for (final c in cs) {
      // The first writable one in discovery order; a control characteristic
      // must not win over it.
      if (write == null &&
          c.properties.canWrite &&
          !profile.ignoreForWrite.contains(c.uuid)) {
        write = c;
      }
    }
    if (data == null || write == null) return null;
    return _Gatt(data: data, write: write);
  }

  for (final service in known) {
    if (services.containsKey(service)) {
      final g = tryService(service);
      if (g != null) return g;
    }
  }
  final upgrade = {for (final s in kLibdcUpgradeServices) normalizeBleUuid(s)};
  for (final service in services.keys) {
    if (known.contains(service) ||
        upgrade.contains(service) ||
        _isStandard(service)) {
      continue;
    }
    final g = tryService(service);
    if (g != null) return g;
  }
  return null;
}

/// The Telit or u-blox characteristics of [service], when it is one of
/// those and all of them are there.
_Gatt? _creditGatt(String service, List<BleCharacteristic> cs) {
  BleCharacteristic? find(String uuid) {
    for (final c in cs) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  if (service == _kTelitService) {
    final data = find(_kTelitData);
    final write = find(_kTelitWrite);
    final out = find(_kTelitCreditOut);
    final inn = find(_kTelitCreditIn);
    if (data == null || write == null || out == null || inn == null) {
      return null;
    }
    return _Gatt(data: data, write: write, creditOut: out, creditIn: inn);
  }
  if (service == _kUbloxService) {
    final data = find(_kUbloxData);
    final credit = find(_kUbloxCredit);
    if (data == null || credit == null) return null;
    return _Gatt(data: data, write: data, creditOut: credit, creditIn: credit);
  }
  return null;
}

List<String> _summarise(List<BleCharacteristic> chars) {
  final lines = <String>[];
  String? last;
  for (final c in chars) {
    if (c.serviceUuid != last) {
      last = c.serviceUuid;
      lines.add('service ${c.serviceUuid}');
    }
    final p = c.properties;
    final flags = [
      if (p.read) 'read',
      if (p.write) 'write',
      if (p.writeWithoutResponse) 'writeWithoutResponse',
      if (p.notify) 'notify',
      if (p.indicate) 'indicate',
    ];
    lines.add('  characteristic ${c.uuid} ${flags.join(' ')}'.trimRight());
  }
  return lines;
}
