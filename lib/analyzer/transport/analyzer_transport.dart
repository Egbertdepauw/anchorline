/// Transport boundary for gas analyzers.
///
/// Every transport (desktop USB serial, Android USB OTG, BLE bridge, the
/// demo simulator) only produces text lines. The line parser, stability
/// detection and UI never know which transport fed them. This mirrors the
/// `shearwater/parser` vs `shearwater/ble` split.
///
/// Pure Dart: no Flutter imports, so transports can be driven from tests
/// and CLI tools alike.
library;

/// Connection state of an [AnalyzerTransport].
enum AnalyzerConnectionStatus {
  /// Not connected (initial state, after [AnalyzerTransport.disconnect], or
  /// after the device went away cleanly).
  disconnected,

  /// [AnalyzerTransport.connect] is in progress.
  connecting,

  /// The link is open. Lines may or may not be arriving: an analyzer with
  /// "Send data to USB" off is connected but silent.
  connected,

  /// The link failed (could not open, unplugged mid-session, ...). See
  /// [AnalyzerTransport.errorMessage].
  error,
}

/// A source of analyzer text lines.
///
/// Implementations split the raw byte stream on `\r?\n` and emit each
/// line without its terminator. A transport instance is single-use per
/// session: callers [connect], listen to [lines], [disconnect], and finally
/// [dispose] it.
abstract class AnalyzerTransport {
  /// Short human-readable name for the transport picker ("Demo", "USB").
  String get name;

  /// One event per received line, terminator stripped. Broadcast stream.
  Stream<String> get lines;

  /// The current connection state.
  AnalyzerConnectionStatus get status;

  /// Emits every change of [status]. Broadcast stream.
  Stream<AnalyzerConnectionStatus> get statusChanges;

  /// A diver-facing explanation when [status] is
  /// [AnalyzerConnectionStatus.error], otherwise null.
  String? get errorMessage;

  /// Opens the link. Completes once [status] is connected or error.
  Future<void> connect();

  /// Closes the link. Safe to call when already disconnected.
  Future<void> disconnect();

  /// Releases resources and closes the streams. The instance must not be
  /// used afterwards.
  Future<void> dispose();
}
