import 'dart:async';

import 'package:ccrlogger/analyzer/bridge/bridge_link.dart';

/// A [BridgeLink] the test drives by hand: it records what was sent and
/// lets the test push lines and link states.
class FakeBridgeLink implements BridgeLink {
  FakeBridgeLink({this.connectError, this.lineBeforeConnected});

  /// When set, [connect] pushes this line before the `connected` state, as
  /// a real bridge does: it sends `HELLO` the moment notifications are on,
  /// before the link layer reports the connection.
  String? lineBeforeConnected;

  /// When set, [connect] throws it and the link stays disconnected.
  BridgeLinkException? connectError;

  /// Every message passed to [send], without the newline.
  final List<String> sent = [];

  int connectCalls = 0;
  int disconnectCalls = 0;
  bool disposed = false;

  final _lines = StreamController<String>.broadcast();
  final _states = StreamController<BridgeLinkState>.broadcast();
  BridgeLinkState _state = BridgeLinkState.disconnected;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<BridgeLinkState> get states => _states.stream;

  @override
  BridgeLinkState get state => _state;

  /// Pushes one received line.
  void pushLine(String line) => _lines.add(line);

  /// Pushes a link state change, as a drop or a reconnect would.
  void pushState(BridgeLinkState s) {
    _state = s;
    _states.add(s);
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    final error = connectError;
    if (error != null) throw error;
    pushState(BridgeLinkState.connecting);
    final early = lineBeforeConnected;
    if (early != null) pushLine(early);
    pushState(BridgeLinkState.connected);
  }

  @override
  Future<void> send(String message) async {
    sent.add(message);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (_state != BridgeLinkState.disconnected) {
      pushState(BridgeLinkState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _lines.close();
    await _states.close();
  }
}
