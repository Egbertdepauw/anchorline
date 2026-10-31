/// Android USB OTG transport for the Divesoft SOLO (#109).
///
/// The SOLO is a native USB CDC-ACM serial device. On Android it is read
/// through a small in-app platform channel
/// (`android/app/src/main/kotlin/.../UsbSerialChannel.kt`) on top of
/// `android.hardware.usb`, with no third-party plugin. This file lists the
/// attached devices, picks the analyzer ([selectAnalyzerDevice]), asks for
/// USB permission, opens it at 115200 8N1 with DTR raised and turns the
/// byte stream into lines ([SerialLineBuffer]).
///
/// The platform side sits behind [UsbSerialPlatform] so the session logic
/// can be tested with a fake; [MethodChannelUsbSerialPlatform] is the real
/// one.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'analyzer_transport.dart';
import 'serial_line_buffer.dart';
import 'usb_device_selection.dart';

/// Baud rate of the SOLO's USB serial output (8N1, no flow control).
const int kSoloBaudRate = 115200;

/// Something the native USB side reports while a session is open.
sealed class UsbSerialEvent {
  const UsbSerialEvent();
}

/// A chunk of received bytes.
class UsbSerialData extends UsbSerialEvent {
  const UsbSerialData(this.bytes);
  final Uint8List bytes;
}

/// A USB device was unplugged.
class UsbSerialDetached extends UsbSerialEvent {
  const UsbSerialDetached(this.deviceName);
  final String? deviceName;
}

/// The native USB serial operations the transport needs.
abstract class UsbSerialPlatform {
  Future<List<UsbDeviceInfo>> listDevices();

  /// Shows Android's USB permission dialog. Resolves to whether access
  /// was granted.
  Future<bool> requestPermission(String deviceName);

  /// Opens [deviceName] at [baudRate] 8N1 and raises DTR. Throws a
  /// [PlatformException] on failure.
  Future<void> open(String deviceName, {required int baudRate});

  Future<void> close();

  /// Received data and detach notifications. Listen before [open].
  Stream<UsbSerialEvent> get events;
}

/// [UsbSerialPlatform] backed by `UsbSerialChannel.kt`.
class MethodChannelUsbSerialPlatform implements UsbSerialPlatform {
  const MethodChannelUsbSerialPlatform();

  static const _methods = MethodChannel('nl.despaankamer.ccrlogger/usb_serial');
  static const _events =
      EventChannel('nl.despaankamer.ccrlogger/usb_serial/events');

  @override
  Future<List<UsbDeviceInfo>> listDevices() async {
    final raw = await _methods.invokeListMethod<Object?>('listDevices');
    return [
      for (final m in raw ?? const [])
        UsbDeviceInfo.fromMap(m as Map<Object?, Object?>),
    ];
  }

  @override
  Future<bool> requestPermission(String deviceName) async =>
      await _methods.invokeMethod<bool>(
          'requestPermission', {'deviceName': deviceName}) ??
      false;

  @override
  Future<void> open(String deviceName, {required int baudRate}) =>
      _methods.invokeMethod<void>(
          'open', {'deviceName': deviceName, 'baudRate': baudRate});

  @override
  Future<void> close() => _methods.invokeMethod<void>('close');

  @override
  Stream<UsbSerialEvent> get events =>
      _events.receiveBroadcastStream().map((e) {
        if (e is Uint8List) return UsbSerialData(e);
        if (e is Map && e['event'] == 'detached') {
          return UsbSerialDetached(e['deviceName'] as String?);
        }
        // Unknown event: an empty chunk is harmless.
        return UsbSerialData(Uint8List(0));
      });
}

class AndroidUsbTransport implements AnalyzerTransport {
  AndroidUsbTransport({
    UsbSerialPlatform platform = const MethodChannelUsbSerialPlatform(),
    this.baudRate = kSoloBaudRate,
  }) : _platform = platform;

  final UsbSerialPlatform _platform;
  final int baudRate;

  final StreamController<String> _lines = StreamController.broadcast();
  final StreamController<AnalyzerConnectionStatus> _status =
      StreamController.broadcast();
  final SerialLineBuffer _buffer = SerialLineBuffer();

  AnalyzerConnectionStatus _current = AnalyzerConnectionStatus.disconnected;
  String? _error;
  StreamSubscription<UsbSerialEvent>? _eventsSub;

  /// The device of the open session, null when not connected.
  UsbDeviceInfo? _device;

  /// The device of the current session, or null.
  UsbDeviceInfo? get device => _device;

  @override
  String get name => 'USB';

  @override
  Stream<String> get lines => _lines.stream;

  @override
  AnalyzerConnectionStatus get status => _current;

  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _status.stream;

  @override
  String? get errorMessage =>
      _current == AnalyzerConnectionStatus.error ? _error : null;

  @override
  Future<void> connect() async {
    if (_current == AnalyzerConnectionStatus.connected ||
        _current == AnalyzerConnectionStatus.connecting) {
      return;
    }
    _error = null;
    _buffer.clear();
    _setStatus(AnalyzerConnectionStatus.connecting);
    try {
      final device = selectAnalyzerDevice(await _platform.listDevices());
      if (device == null) {
        return _fail('No USB analyzer found. Connect the analyzer to the '
            'phone with a USB-C OTG cable and turn it on.');
      }
      final granted = device.hasPermission ||
          await _platform.requestPermission(device.deviceName);
      if (!granted) {
        return _fail('USB access was denied. Unplug the analyzer, plug it '
            'back in and allow Anchorline to use it.');
      }
      _eventsSub = _platform.events.listen(_onEvent, onError: (Object e) {
        _fail('USB read error: ${_describe(e)}');
      });
      await _platform.open(device.deviceName, baudRate: baudRate);
      if (_current != AnalyzerConnectionStatus.connecting) {
        // Disconnected or failed while opening: don't leave it open.
        unawaited(_platform.close().catchError((_) {}));
        return;
      }
      _device = device;
      _setStatus(AnalyzerConnectionStatus.connected);
    } catch (e) {
      await _fail('Could not open the USB analyzer: ${_describe(e)}');
    }
  }

  @override
  Future<void> disconnect() async {
    _dropEvents();
    final wasOpen = _device != null;
    _device = null;
    if (wasOpen) {
      try {
        await _platform.close();
      } catch (_) {
        // Already gone (unplugged): nothing left to close.
      }
    }
    if (_current != AnalyzerConnectionStatus.disconnected) {
      _setStatus(AnalyzerConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    // Not awaited: a broadcast controller's done future only completes
    // once the done event is delivered, which callers need not wait for.
    unawaited(_lines.close());
    unawaited(_status.close());
  }

  void _onEvent(UsbSerialEvent event) {
    switch (event) {
      case UsbSerialData(:final bytes):
        if (_current != AnalyzerConnectionStatus.connected) return;
        for (final line in _buffer.add(bytes)) {
          if (!_lines.isClosed) _lines.add(line);
        }
      case UsbSerialDetached(:final deviceName):
        final open = _device;
        if (open == null) return;
        // A null name can't be matched; treat it as ours to be safe.
        if (deviceName != null && deviceName != open.deviceName) return;
        unawaited(_fail('The analyzer was unplugged.'));
    }
  }

  /// Ends the session in [AnalyzerConnectionStatus.error] with [message].
  Future<void> _fail(String message) async {
    _dropEvents();
    final wasOpen = _device != null;
    _device = null;
    _error = message;
    _setStatus(AnalyzerConnectionStatus.error);
    if (wasOpen) {
      try {
        await _platform.close();
      } catch (_) {
        // Best effort.
      }
    }
  }

  void _dropEvents() {
    // Not awaited: inside widget tests a broadcast subscription's cancel
    // future may never complete, and nothing here depends on it.
    unawaited(_eventsSub?.cancel());
    _eventsSub = null;
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : e.toString();

  void _setStatus(AnalyzerConnectionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }
}
