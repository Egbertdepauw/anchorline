/// Real BLE I/O implementation using flutter_blue_plus.
///
/// Bridges the abstract [BleIo] interface to a real BLE device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'protocol.dart';

/// Shearwater BLE service and characteristic UUIDs.
///
/// Shearwater uses a custom BLE service with write and notify characteristics.
const String shearwaterServiceUuid = 'fe25c237-0ece-443c-b0aa-e02033e7029d';
const String shearwaterWriteCharUuid = '27b7570b-359e-45a3-91bb-cf7e70049bd2';
const String shearwaterNotifyCharUuid = '27b7570b-359e-45a3-91bb-cf7e70049bd2';

/// Real BLE I/O backed by a connected [BluetoothDevice].
///
/// Call [connect] to discover services and characteristics, then use
/// [writeBytes] and [readFrames] for the protocol layer.
class FlutterBluePlusBleIo implements BleIo {
  final BluetoothDevice device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;

  // Explicit frame queue. The notify subscription is the only producer and
  // is set up once at connect; readFrames is the only consumer. Using a
  // queue (instead of a Stream) avoids two pitfalls: single-subscription
  // streams can't be re-listened to after a cancel, and broadcast streams
  // drop events delivered while no listener is attached — and the Petrel
  // can start responding before our last withoutResponse write returns,
  // which is exactly when there is no listener.
  final _frames = <Uint8List>[];
  Completer<void>? _frameSignal;

  FlutterBluePlusBleIo(this.device);

  /// Discover services, find Shearwater characteristics, enable notifications.
  Future<void> connect() async {
    await device.connect(timeout: const Duration(seconds: 10));
    final services = await device.discoverServices();

    BluetoothService? swService;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          shearwaterServiceUuid.toLowerCase()) {
        swService = s;
        break;
      }
    }
    if (swService == null) {
      throw ProtocolException('Shearwater BLE service not found');
    }

    for (final c in swService.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid == shearwaterWriteCharUuid.toLowerCase()) {
        _writeChar = c;
      }
      if (uuid == shearwaterNotifyCharUuid.toLowerCase()) {
        _notifyChar = c;
      }
    }
    if (_writeChar == null || _notifyChar == null) {
      throw ProtocolException('Shearwater BLE characteristics not found');
    }

    await _notifyChar!.setNotifyValue(true);
    int? rssi;
    try {
      rssi = await device.readRssi();
    } catch (_) {
      // readRssi can fail on iOS if not connected long enough; ignore.
    }
    debugPrint('BLE connected. MTU=${device.mtuNow}B, '
        'RSSI=${rssi ?? 'n/a'} dBm, '
        'platform=${defaultTargetPlatform.name}');
    _notifySub = _notifyChar!.onValueReceived.listen((data) {
      _frames.add(Uint8List.fromList(data));
      final waiter = _frameSignal;
      if (waiter != null && !waiter.isCompleted) {
        _frameSignal = null;
        waiter.complete();
      }
    });
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    final waiter = _frameSignal;
    _frameSignal = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Disconnected'));
    }
    await device.disconnect();
  }

  @override
  Future<void> writeBytes(Uint8List data) async {
    if (_writeChar == null) {
      throw StateError('Not connected');
    }
    await _writeChar!.write(data.toList(), withoutResponse: true);
  }

  @override
  Future<List<Uint8List>> readFrames() async {
    if (_notifyChar == null) {
      throw StateError('Not connected');
    }

    final out = <Uint8List>[];
    while (true) {
      while (_frames.isEmpty) {
        _frameSignal = Completer<void>();
        await _frameSignal!.future;
      }
      final frame = _frames.removeAt(0);
      out.add(frame);
      if (frame.isNotEmpty && frame.last == 0xC0) break;
    }
    return out;
  }
}
