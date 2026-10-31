/// USB serial transport for the gas analyzer on macOS, Windows and Linux.
///
/// The Divesoft SOLO is a native USB CDC-ACM device: 115200 baud, 8N1, no
/// flow control, DTR raised, one text line per second while "Send data to
/// USB" is on. The port is opened with [NativeSerialPort] (dart:ffi, no
/// plugin) on a background isolate that loops on short blocking reads and
/// posts the raw chunks back; this isolate splits them into lines with
/// [SerialLineBuffer].
///
/// Unplugging the analyzer ends the session with
/// [AnalyzerConnectionStatus.error] and a diver-facing [errorMessage].
///
/// Pure Dart (no Flutter imports). Only constructed on desktop; see
/// `defaultAnalyzerTransportOptions` in the analyzer screen.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'analyzer_transport.dart';
import 'native_serial_port.dart';
import 'serial_line_buffer.dart';
import 'serial_port_selection.dart';

/// Candidate analyzer ports on this machine, likely-analyzer ports first.
List<String> listDesktopSerialPorts() =>
    rankSerialPorts(listNativeSerialPorts());

class DesktopSerialTransport implements AnalyzerTransport {
  DesktopSerialTransport({required this.portPath});

  /// `/dev/cu.usbmodem101`, `/dev/ttyACM0`, `COM3`, ...
  final String portPath;

  /// How long [disconnect] waits for the reader isolate to close the port
  /// before killing it. A read blocks for at most [kSerialReadTimeoutMs].
  static const Duration _stopTimeout = Duration(seconds: 2);

  final StreamController<String> _lines = StreamController.broadcast();
  final StreamController<AnalyzerConnectionStatus> _status =
      StreamController.broadcast();
  final SerialLineBuffer _splitter = SerialLineBuffer();

  AnalyzerConnectionStatus _current = AnalyzerConnectionStatus.disconnected;
  String? _error;

  // Per-session state.
  ReceivePort? _inbox;
  Isolate? _isolate;
  Pointer<Uint8>? _stopFlag;
  Completer<void>? _exited;

  @override
  String get name => 'USB';

  @override
  Stream<String> get lines => _lines.stream;

  @override
  AnalyzerConnectionStatus get status => _current;

  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _status.stream;

  @override
  String? get errorMessage => _error;

  @override
  Future<void> connect() async {
    if (_isolate != null) return;
    _error = null;
    _splitter.clear();
    _setStatus(AnalyzerConnectionStatus.connecting);

    final inbox = ReceivePort();
    // A one-byte flag in native memory: the reader isolate is busy in
    // blocking reads and never services its event loop, so it polls this
    // between reads instead of receiving a message.
    final stop = calloc<Uint8>();
    final opened = Completer<void>();
    final exited = Completer<void>();
    _inbox = inbox;
    _stopFlag = stop;
    _exited = exited;
    inbox.listen((message) => _onMessage(message, opened, exited));

    try {
      _isolate = await Isolate.spawn(
        _readerMain,
        [inbox.sendPort, portPath, stop.address],
        onExit: inbox.sendPort,
        debugName: 'analyzer-serial',
      );
    } catch (e) {
      _endSession(freeFlag: true);
      _fail('Could not start the serial reader: $e');
      return;
    }
    await opened.future;
  }

  void _onMessage(
      Object? message, Completer<void> opened, Completer<void> exited) {
    if (message is Uint8List) {
      for (final line in _splitter.add(message)) {
        if (!_lines.isClosed) _lines.add(line);
      }
      return;
    }
    if (message is List && message.isNotEmpty) {
      switch (message[0]) {
        case 'opened':
          _setStatus(AnalyzerConnectionStatus.connected);
          if (!opened.isCompleted) opened.complete();
        case 'failed':
          final detail = message.length > 1 ? '${message[1]}' : '';
          if (_current == AnalyzerConnectionStatus.connected) {
            _fail('The analyzer was disconnected. $detail Check the USB '
                'cable and connect again.');
          } else {
            _fail('Could not open the analyzer port. $detail');
          }
          if (!opened.isCompleted) opened.complete();
      }
      return;
    }
    if (message == null) {
      // onExit: the reader isolate is gone (normally or not).
      if (!exited.isCompleted) exited.complete();
      if (!opened.isCompleted) {
        _fail('The serial reader stopped unexpectedly.');
        opened.complete();
      }
      // Only this session's state; a disconnect() may already have
      // started a new one.
      if (identical(_exited, exited)) {
        _endSession(freeFlag: true);
        if (_current == AnalyzerConnectionStatus.connected) {
          _setStatus(AnalyzerConnectionStatus.disconnected);
        }
      }
    }
  }

  @override
  Future<void> disconnect() async {
    final stop = _stopFlag;
    final exited = _exited;
    if (stop != null && exited != null) {
      stop.value = 1;
      var clean = true;
      try {
        await exited.future.timeout(_stopTimeout);
      } on TimeoutException {
        clean = false;
        _isolate?.kill(priority: Isolate.immediate);
      }
      // After a kill the isolate may still be inside a read and touch the
      // flag later, so it is leaked (one byte) rather than freed.
      _endSession(freeFlag: clean);
    }
    if (_current != AnalyzerConnectionStatus.disconnected &&
        _current != AnalyzerConnectionStatus.error) {
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

  void _endSession({required bool freeFlag}) {
    _inbox?.close();
    _inbox = null;
    _isolate = null;
    final stop = _stopFlag;
    _stopFlag = null;
    if (stop != null && freeFlag) calloc.free(stop);
    _exited = null;
  }

  void _fail(String message) {
    _error = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    _setStatus(AnalyzerConnectionStatus.error);
  }

  void _setStatus(AnalyzerConnectionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }
}

/// Reader isolate entry point: `[SendPort out, String path, int stopFlag]`.
///
/// Posts `['opened']` once the port is configured, then every non-empty
/// chunk as a [Uint8List], and `['failed', message]` if opening or reading
/// fails. Returns (closing the port) when the stop flag becomes non-zero.
void _readerMain(List<Object?> args) {
  final out = args[0] as SendPort;
  final path = args[1] as String;
  final stop = Pointer<Uint8>.fromAddress(args[2] as int);

  final NativeSerialPort port;
  try {
    port = NativeSerialPort.open(path);
  } catch (e) {
    out.send(['failed', '$e']);
    return;
  }
  out.send(['opened']);
  try {
    while (stop.value == 0) {
      final chunk = port.read();
      if (chunk.isNotEmpty) out.send(chunk);
    }
  } catch (e) {
    out.send(['failed', '$e']);
  } finally {
    port.close();
  }
}
