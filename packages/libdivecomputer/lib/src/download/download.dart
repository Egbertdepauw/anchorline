import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import '../bindings.g.dart' as c;
import '../descriptors.dart';
import '../envelope.dart';
import '../parse/status.dart';
import '../recording/recording.dart';
import 'ble_link.dart';
import 'download_isolate.dart';
import 'events.dart';
import 'native_link.dart';

/// How a download reaches the computer.
///
/// Phase 3 (cable and classic Bluetooth) adds a serial connection, opened
/// with `dc_serial_open` inside the download isolate; nothing else in
/// [LibdcDownload] changes.
sealed class LibdcConnection {
  const LibdcConnection();
}

/// Over Bluetooth LE, through the app's [LibdcBleLink].
final class LibdcBleConnection extends LibdcConnection {
  const LibdcBleConnection(
    this.link, {
    this.writeTimeout = const Duration(milliseconds: c.AL_LINK_WRITE_TIMEOUT),
  });

  final LibdcBleLink link;

  /// How long one write or characteristic request may take before
  /// libdivecomputer is told it timed out. Negative: no limit.
  final Duration writeTimeout;
}

/// One download from a dive computer, run by libdivecomputer on an isolate
/// of its own.
///
/// The main isolate owns the C layer's link: it serves the link's requests
/// one at a time, in order (a write or a characteristic request goes to the
/// [LibdcBleLink], and only then is it completed and the next one taken),
/// pushes every notification, and reports a dropped connection. The
/// download isolate gets only the link's address, makes its own
/// libdivecomputer context and descriptor, and posts [events]. The link is
/// freed only after that isolate has exited, and after every source that
/// could still call into it (the notifications, the disconnect, a request
/// still in flight) has been cut off.
class LibdcDownload {
  LibdcDownload._(this._descriptor, this._advertisedName) {
    _controller = StreamController(onCancel: _onListenerGone);
  }

  /// Downloads over [connection]. Dives whose fingerprint libdivecomputer
  /// finds in [knownFingerprints] (by serial number) and every dive after
  /// them are not downloaded. With [record], the recording holds every
  /// read and write, and the log is at INFO.
  static LibdcDownload start({
    required LibdcDescriptor descriptor,
    required LibdcConnection connection,
    Map<int, Uint8List> knownFingerprints = const {},
    bool record = false,
  }) {
    switch (connection) {
      case LibdcBleConnection():
        final download = LibdcDownload._(
          descriptor,
          connection.link.advertisedName,
        );
        download._startBle(connection, knownFingerprints, record);
        return download;
    }
  }

  /// Downloads from [recording] instead of a computer: the C layer serves
  /// its reads in order and checks every write against it.
  static LibdcDownload replay({
    required LibdcDescriptor descriptor,
    required LibdcRecording recording,
    Map<int, Uint8List> knownFingerprints = const {},
  }) => _replay(descriptor, recording, knownFingerprints, false);

  static LibdcDownload _replay(
    LibdcDescriptor descriptor,
    LibdcRecording recording,
    Map<int, Uint8List> knownFingerprints,
    bool legacyParser,
  ) {
    final name = recording.advertisedName;
    final download = LibdcDownload._(descriptor, name);
    final native = NativeLink.replay(name, recording.toReplayEvents());
    if (native == null) {
      download._finishEarly(
        LibdcStatus.invalidArgs,
        'the recording cannot be replayed.',
      );
    } else {
      download._native = native;
      download._legacyParser = legacyParser;
      unawaited(download._run(knownFingerprints, record: false));
    }
    return download;
  }

  final LibdcDescriptor _descriptor;
  final String? _advertisedName;
  late final StreamController<LibdcDownloadEvent> _controller;

  NativeLink? _native;
  var _legacyParser = false;
  NativeCallable<c.al_request_fnFunction>? _listener;
  LibdcBleLink? _link;
  Duration _writeTimeout = Duration.zero;
  StreamSubscription<Uint8List>? _notifications;
  var _watchingDisconnect = false;
  final _timers = <Timer>{};
  final _envelopes = <LibdcEnvelope>[];
  var _signals = 0;
  var _pumping = false;
  var _finished = false;

  /// Single subscription. [LibdcFinished] is the last event and always
  /// comes. Cancelling the subscription cancels the download.
  Stream<LibdcDownloadEvent> get events => _controller.stream;

  /// Stops the download: libdivecomputer's waiting read or write returns
  /// at once, and the download ends with [LibdcStatus.cancelled] unless it
  /// was already finishing. Harmless at any time.
  void cancel() => _native?.cancel();

  void _onListenerGone() {
    if (!_finished) cancel();
  }

  List<String> get _header => recordingHeader(
    vendor: _descriptor.vendor,
    product: _descriptor.product,
    family: _descriptor.family,
    model: _descriptor.model,
    advertisedName: _advertisedName,
  );

  void _startBle(
    LibdcBleConnection connection,
    Map<int, Uint8List> knownFingerprints,
    bool record,
  ) {
    final listener = NativeCallable<c.al_request_fnFunction>.listener(
      _onRequest,
    );
    final native = NativeLink.live(
      connection.link.advertisedName,
      listener.nativeFunction,
    );
    if (native == null) {
      listener.close();
      _finishEarly(LibdcStatus.noMemory, 'the link could not be made.');
      return;
    }
    _listener = listener;
    _native = native;
    _link = connection.link;
    _writeTimeout = connection.writeTimeout;
    native.setWriteTimeout(
      connection.writeTimeout.isNegative
          ? -1
          : connection.writeTimeout.inMilliseconds,
    );
    native.setRecording(record);
    _notifications = connection.link.notifications.listen(
      native.push,
      // A stream error is not a dropped connection; `disconnected` says so.
      onError: (Object _) {},
    );
    _watchingDisconnect = true;
    connection.link.disconnected.then(
      (_) => _onDisconnected(),
      onError: (Object _) => _onDisconnected(),
    );
    unawaited(_run(knownFingerprints, record: record));
  }

  void _onDisconnected() {
    if (_watchingDisconnect) _native?.disconnected();
  }

  // -------------------------------------------------------------------------
  // Requests. The listener only says "something may be waiting"; what is
  // waiting, and its kind, come from taking it. One at a time, in order:
  // the next is taken only after this one is completed or abandoned.

  void _onRequest(int link, int kind) {
    _signals++;
    if (!_pumping) unawaited(_pump());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (_signals > 0) {
        _signals--;
        final native = _native;
        if (native == null || native.isFreed) {
          _signals = 0;
          break;
        }
        final request = native.take();
        if (request == null) continue;
        await _serve(native, request);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _serve(NativeLink native, LinkRequest request) async {
    final link = _link!;
    Future<(int, Uint8List?)> perform() async {
      try {
        switch (request.kind) {
          case c.AL_REQ_WRITE:
            await link.write(request.data);
            return (c.dc_status_t.DC_STATUS_SUCCESS, null);
          case c.AL_REQ_CHAR_READ:
            final value = await link.readCharacteristic(request.uuid);
            return (c.dc_status_t.DC_STATUS_SUCCESS, value);
          case c.AL_REQ_CHAR_WRITE:
            await link.writeCharacteristic(request.uuid, request.data);
            return (c.dc_status_t.DC_STATUS_SUCCESS, null);
          default:
            return (c.dc_status_t.DC_STATUS_UNSUPPORTED, null);
        }
      } catch (_) {
        return (c.dc_status_t.DC_STATUS_IO, null);
      }
    }

    // The C layer gives up on a request after the write timeout, counted
    // from before it announced it, so by then nobody waits for an answer.
    // Stop waiting too, so that a link call that never returns doesn't
    // hold up the requests after it.
    final abandon = Completer<(int, Uint8List?)?>();
    Timer? timer;
    if (!_writeTimeout.isNegative) {
      timer = Timer(_writeTimeout, () {
        if (!abandon.isCompleted) abandon.complete(null);
      });
      _timers.add(timer);
    }
    final outcome = await Future.any<(int, Uint8List?)?>([
      perform(),
      abandon.future,
    ]);
    if (timer != null) {
      timer.cancel();
      _timers.remove(timer);
    }
    if (outcome == null) return;
    // Refused by NativeLink when the download is over and the link freed.
    native.complete(request.id, outcome.$1, outcome.$2);
  }

  // -------------------------------------------------------------------------
  // The isolate, and the end.

  Future<void> _run(
    Map<int, Uint8List> knownFingerprints, {
    required bool record,
  }) async {
    final native = _native!;
    final port = ReceivePort('libdc download');
    LibdcFinished? finished;
    Object? failure;
    try {
      await Isolate.spawn(
        downloadIsolateMain,
        DownloadArgs(
          linkAddress: native.address,
          vendor: _descriptor.vendor,
          product: _descriptor.product,
          family: _descriptor.family,
          model: _descriptor.model,
          advertisedName: _advertisedName,
          knownFingerprints: Map.of(knownFingerprints),
          record: record,
          port: port.sendPort,
          debugLegacyParser: _legacyParser,
        ),
        onError: port.sendPort,
        onExit: port.sendPort, // sends null, after everything else
        debugName: 'libdc download',
      );
      await for (final message in port) {
        if (message == null) break; // the isolate has exited
        if (message is LibdcFinished) {
          finished = message;
        } else if (message is LibdcDownloadEvent) {
          if (message is LibdcDiveDownloaded) _envelopes.add(message.envelope);
          _controller.add(message);
        } else if (message is List && message.isNotEmpty) {
          failure = message.first; // an uncaught error in the isolate
        }
      }
    } catch (error) {
      failure = error;
    } finally {
      port.close();
    }
    _release();
    _finish(
      finished ??
          LibdcFinished(
            status: LibdcStatus.io,
            recording: LibdcRecording(
              header: _header,
              log: ['ANCHORLINE: the download isolate stopped: $failure'],
              envelopes: _envelopes,
            ),
          ),
    );
  }

  /// Cuts off everything that could still call into the link, then frees
  /// it. Runs once the download isolate has exited, so no iostream of the
  /// link is open and the C layer calls nothing any more.
  void _release() {
    _notifications?.cancel();
    _notifications = null;
    _watchingDisconnect = false;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    // A request still in flight on the link finishes into a NativeLink that
    // refuses it.
    _native?.free();
    _listener?.close();
    _listener = null;
  }

  void _finish(LibdcFinished finished) {
    _finished = true;
    _controller.add(finished);
    unawaited(_controller.close());
  }

  void _finishEarly(LibdcStatus status, String why) => _finish(
    LibdcFinished(
      status: status,
      recording: LibdcRecording(header: _header, log: ['ANCHORLINE: $why']),
    ),
  );
}

/// The download's handle on its C link, for tests.
NativeLink? debugNativeLinkOf(LibdcDownload download) => download._native;

/// Test-only: [LibdcDownload.replay] that also parses every dive with
/// `dc_parser_new(device)`, reported as
/// [LibdcDiveDownloaded.debugLegacyConverted]. Not exported from the package.
LibdcDownload debugReplayWithLegacyParser({
  required LibdcDescriptor descriptor,
  required LibdcRecording recording,
}) => LibdcDownload._replay(descriptor, recording, const {}, true);
