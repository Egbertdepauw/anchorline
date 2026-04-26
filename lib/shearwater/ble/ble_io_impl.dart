/// Real BLE I/O implementation using flutter_blue_plus.
///
/// Bridges the abstract [BleIo] interface to a real BLE device.
library;

import 'dart:async';
import 'dart:typed_data';

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
  final _frameController = StreamController<Uint8List>();

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

    // Enable notifications.
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.onValueReceived.listen((data) {
      _frameController.add(Uint8List.fromList(data));
    });
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _frameController.close();
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

    final frames = <Uint8List>[];
    // Read frames until we get a complete SLIP packet (ending with 0xC0).
    await for (final frame in _frameController.stream) {
      frames.add(frame);
      // Check if this frame ends with 0xC0 (SLIP END).
      if (frame.isNotEmpty && frame.last == 0xC0) {
        break;
      }
    }
    return frames;
  }
}
