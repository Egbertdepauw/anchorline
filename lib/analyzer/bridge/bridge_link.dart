/// The Bluetooth link to the SOLO bridge, as the transport sees it.
///
/// Pure Dart. The real implementation is `CentralBridgeLink` in
/// `bridge_link_ble.dart`; tests use a fake. The link moves whole text lines:
/// it splits the Nordic UART stream into lines on the way in and chunks to
/// the MTU on the way out. Protocol meaning lives in `bridge_protocol.dart`
/// and `BleBridgeTransport`.
library;

/// Nordic UART service.
const String kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// RX characteristic: the app writes to it.
const String kNusRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// TX characteristic: the bridge notifies on it.
const String kNusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// A bridge advertises as `Anchorline Bridge XXXX`.
const String kBridgeNamePrefix = 'Anchorline Bridge';

/// How long the first connection waits for the bridge to show up.
const Duration kBridgeFirstConnectTimeout = Duration(seconds: 15);

enum BridgeLinkState { disconnected, connecting, connected }

/// A failure the diver can be told about; [message] is fit to show.
class BridgeLinkException implements Exception {
  const BridgeLinkException(this.message);

  final String message;

  @override
  String toString() => 'BridgeLinkException: $message';
}

abstract class BridgeLink {
  /// Reassembled lines, terminator stripped. Broadcast.
  Stream<String> get lines;

  /// Every change of [state]. Broadcast.
  Stream<BridgeLinkState> get states;

  BridgeLinkState get state;

  /// First connection. Throws
  /// `BridgeLinkException('Bridge not found. Is it switched on?')` after
  /// [kBridgeFirstConnectTimeout]. After a first connection, drops
  /// reconnect by themselves (connecting -> connected) until [disconnect].
  Future<void> connect();

  /// Sends [message] followed by `\n`.
  Future<void> send(String message);

  /// Closes the link and stops reconnecting. Safe at any time.
  Future<void> disconnect();

  /// Releases everything. The instance must not be used afterwards.
  Future<void> dispose();
}
