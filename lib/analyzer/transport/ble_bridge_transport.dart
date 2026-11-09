/// The SOLO bridge as an [AnalyzerTransport].
///
/// Sits on a [BridgeLink], speaks the bridge protocol (see
/// `bridge_protocol.dart`) and hands the SOLO's own lines to the analyzer
/// controller, exactly like a USB transport does. The bridge's status
/// ([lastHello], [lastStatus]) and every message except `L` are exposed for
/// the connection strip and, later, the OK record handler.
///
/// Per connection of the link the transport sends `TIME`, `CFG`, `LIVE ON`
/// in that order and waits for the bridge's `HELLO`. A link that drops after
/// that goes back to `connecting` and repeats the steps when it returns.
///
/// Pure Dart.
library;

import 'dart:async';

import 'dart:developer' show log;

import '../bridge/bridge_link.dart';
import '../bridge/bridge_protocol.dart';
import 'analyzer_transport.dart';

class BleBridgeTransport implements AnalyzerTransport {
  BleBridgeTransport({
    required BridgeLink link,
    required bool Function() recording,
    required bool Function() vbusOn,
    DateTime Function()? now,
    Duration helloTimeout = const Duration(seconds: 5),
  }) : _link = link,
       _recording = recording,
       _vbusOn = vbusOn,
       _now = now ?? DateTime.now,
       _helloTimeout = helloTimeout;

  final BridgeLink _link;
  final bool Function() _recording;
  final bool Function() _vbusOn;
  final DateTime Function() _now;
  final Duration _helloTimeout;

  final _lines = StreamController<String>.broadcast();
  final _messages = StreamController<BridgeMessage>.broadcast();
  final _statusChanges =
      StreamController<AnalyzerConnectionStatus>.broadcast();
  final _bridgeChanges = StreamController<void>.broadcast();

  StreamSubscription<String>? _linesSub;
  StreamSubscription<BridgeLinkState>? _statesSub;
  Timer? _helloTimer;

  AnalyzerConnectionStatus _status = AnalyzerConnectionStatus.disconnected;
  String? _errorMessage;
  BridgeHello? _lastHello;
  BridgeStatus? _lastStatus;

  /// Completes when [connect] has its answer: connected or error.
  Completer<void>? _connectDone;

  /// The handshake of the current link connection has started.
  bool _handshakeStarted = false;

  bool _disposed = false;

  @override
  String get name => 'Bridge';

  @override
  Stream<String> get lines => _lines.stream;

  @override
  AnalyzerConnectionStatus get status => _status;

  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _statusChanges.stream;

  @override
  String? get errorMessage => _errorMessage;

  /// Every parsed line except `L`, including ones that did not parse
  /// ([BridgeUnknown]). Broadcast.
  Stream<BridgeMessage> get messages => _messages.stream;

  /// Whether the 5 V switch is on, as the bridge was last told.
  bool get vbusOn => _vbusOn();

  BridgeHello? get lastHello => _lastHello;

  /// The latest `ST`; also set from `HELLO`.
  BridgeStatus? get lastStatus => _lastStatus;

  /// Fires when [lastHello] or [lastStatus] changed.
  Stream<void> get bridgeChanges => _bridgeChanges.stream;

  @override
  Future<void> connect() async {
    if (_disposed || _status != AnalyzerConnectionStatus.disconnected) return;
    _errorMessage = null;
    _setStatus(AnalyzerConnectionStatus.connecting);
    final done = _connectDone = Completer<void>();
    _linesSub = _link.lines.listen(_onLine);
    _statesSub = _link.states.listen(_onLinkState);
    try {
      await _link.connect();
    } on BridgeLinkException catch (e) {
      _fail(e.message, closeLink: false);
      return;
    } catch (e) {
      log('connect failed: $e', name: 'Bridge');
      _fail('Could not connect to the bridge.', closeLink: false);
      return;
    }
    // The state event may have been delivered already; make sure the
    // handshake runs once either way.
    if (_status == AnalyzerConnectionStatus.connecting &&
        _link.state == BridgeLinkState.connected) {
      _startHandshake();
    }
    await done.future;
  }

  void _onLinkState(BridgeLinkState s) {
    switch (s) {
      case BridgeLinkState.connected:
        _startHandshake();
      case BridgeLinkState.connecting || BridgeLinkState.disconnected:
        _handshakeStarted = false;
        _helloTimer?.cancel();
        _helloTimer = null;
        if (_status == AnalyzerConnectionStatus.connected) {
          // A drop: the link reconnects by itself.
          _setStatus(AnalyzerConnectionStatus.connecting);
        }
    }
  }

  /// A link connection is up: wait for `HELLO` and send the three opening
  /// messages in order.
  void _startHandshake() {
    if (_disposed || _handshakeStarted) return;
    if (_status != AnalyzerConnectionStatus.connecting) return;
    _handshakeStarted = true;
    _helloTimer?.cancel();
    _helloTimer = Timer(_helloTimeout, () {
      if (_status == AnalyzerConnectionStatus.connecting) {
        _fail('The bridge did not answer.');
      }
    });
    unawaited(_sendOpening());
  }

  Future<void> _sendOpening() async {
    try {
      await _link.send(formatTime(_now()));
      await _link.send(
        formatConfig(recording: _recording(), vbusOn: _vbusOn()),
      );
      await _link.send(formatLive(true));
    } catch (e) {
      // A dead link shows up as a state change or the HELLO timeout.
      log('opening messages failed: $e', name: 'Bridge');
    }
  }

  void _onLine(String line) {
    final m = parseBridgeMessage(line);
    switch (m) {
      case BridgeLiveLine():
        if (!_lines.isClosed) _lines.add(m.line);
        return;
      case BridgeHello():
        _onHello(m);
      case BridgeStatus():
        _lastStatus = m;
        _notifyBridge();
      default:
        break;
    }
    if (!_messages.isClosed) _messages.add(m);
  }

  void _onHello(BridgeHello h) {
    if (h.proto != kBridgeProtocolVersion) {
      _fail(
        'Bridge firmware speaks protocol ${h.proto}. '
        'Update the app or the bridge.',
      );
      return;
    }
    _lastHello = h;
    _lastStatus = BridgeStatus(
      soloAttached: h.soloAttached,
      dataFlowing: false,
      pending: h.pending,
      batteryMv: h.batteryMv,
      upMs: h.upMs,
    );
    _notifyBridge();
    _helloTimer?.cancel();
    _helloTimer = null;
    if (_status == AnalyzerConnectionStatus.connecting) {
      _setStatus(AnalyzerConnectionStatus.connected);
    }
  }

  /// Ends in `error`: records [message], stops the timer and closes the link.
  void _fail(String message, {bool closeLink = true}) {
    if (_status == AnalyzerConnectionStatus.error) return;
    _helloTimer?.cancel();
    _helloTimer = null;
    _errorMessage = message;
    _setStatus(AnalyzerConnectionStatus.error);
    if (closeLink) unawaited(_link.disconnect());
  }

  /// Sends [message] to the bridge. A no-op unless the link is connected.
  Future<void> send(String message) async {
    if (_link.state != BridgeLinkState.connected) return;
    try {
      await _link.send(message);
    } catch (e) {
      log('send failed: $e', name: 'Bridge');
    }
  }

  /// Tells the bridge the current Log on OK and 5 V settings.
  Future<void> sendConfig() =>
      send(formatConfig(recording: _recording(), vbusOn: _vbusOn()));

  @override
  Future<void> disconnect() async {
    if (_status == AnalyzerConnectionStatus.disconnected) return;
    _helloTimer?.cancel();
    _helloTimer = null;
    if (_status == AnalyzerConnectionStatus.connected) {
      await send(formatLive(false));
    }
    await _link.disconnect();
    await _linesSub?.cancel();
    await _statesSub?.cancel();
    _linesSub = null;
    _statesSub = null;
    _handshakeStarted = false;
    _lastHello = null;
    _lastStatus = null;
    _notifyBridge();
    _setStatus(AnalyzerConnectionStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _link.dispose();
    // Not awaited: a broadcast controller's done future only completes once
    // the done event is delivered.
    unawaited(_lines.close());
    unawaited(_messages.close());
    unawaited(_statusChanges.close());
    unawaited(_bridgeChanges.close());
  }

  void _setStatus(AnalyzerConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statusChanges.isClosed) _statusChanges.add(s);
    if (s == AnalyzerConnectionStatus.connected ||
        s == AnalyzerConnectionStatus.error ||
        s == AnalyzerConnectionStatus.disconnected) {
      final done = _connectDone;
      if (done != null && !done.isCompleted) done.complete();
    }
  }

  void _notifyBridge() {
    if (!_bridgeChanges.isClosed) _bridgeChanges.add(null);
  }
}
