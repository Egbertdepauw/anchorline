/// The live state for the bridge screen (issue #113, spec §3 `STATE`).
///
/// The bridge has no gas logic: what its screen says about the live reading
/// (SETTLING, STABLE, SENSOR ERROR, AIR, and the mix) is what the app sends
/// it. [BridgeStateReporter] sends `STATE <code> [<mix>]` on every change and
/// again at least every [kStateHeartbeat], which doubles as the heartbeat:
/// a bridge that hears no `STATE` for 10 s shows PHONE NOT RESPONDING.
///
/// Pure Dart.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../analysis/gas_naming.dart';
import '../protocol/analyzer_reading.dart';
import '../stability.dart';
import 'bridge_protocol.dart';
import 'record_to_analysis.dart' show isRoomAir;

/// The longest the bridge goes without a `STATE` while a reading is known.
const Duration kStateHeartbeat = Duration(seconds: 3);

/// The bridge screen's state for reading [r] at stability [s].
///
/// Null with no reading. A sensor error when O2 is missing, not a number or
/// zero or less, or He is not a number. Air (no mix) when [isRoomAir]. Else
/// stable or settling, with the mix name ([gasMixName]); a detector that was
/// just reset has no state yet and counts as settling.
({BridgeLiveState state, String? mix})? liveStateFor(
  AnalyzerReading? r,
  ReadingStability s,
) {
  if (r == null) return null;
  final o2 = r.o2;
  final heRaw = r.he ?? 0.0;
  if (o2 == null ||
      !o2.isFinite ||
      o2 <= 0 ||
      !heRaw.isFinite ||
      s == ReadingStability.sensorError) {
    return (state: BridgeLiveState.sensorError, mix: null);
  }
  final he = math.max(heRaw, 0.0);
  if (isRoomAir(o2, he)) return (state: BridgeLiveState.air, mix: null);
  return (
    state: s == ReadingStability.stable
        ? BridgeLiveState.stable
        : BridgeLiveState.settling,
    mix: gasMixName(o2, he),
  );
}

/// Sends the live state to the bridge; see the library comment.
class BridgeStateReporter {
  BridgeStateReporter({
    required Future<void> Function(String message) send,
    Duration? heartbeat,
  }) : _send = send,
       _heartbeat = heartbeat ?? kStateHeartbeat;

  final Future<void> Function(String message) _send;
  final Duration _heartbeat;

  bool _running = false;

  /// The message last sent; null before the first since [start], or when
  /// there is no reading.
  String? _last;
  Timer? _timer;

  /// Starts sending. The first [update] after it sends, also when the state
  /// is the one sent before a [stop].
  void start() {
    _running = true;
  }

  /// Stops sending and forgets the state.
  void stop() {
    _running = false;
    _last = null;
    _timer?.cancel();
    _timer = null;
  }

  /// The controller's reading and stability now. Sends when the state
  /// changed; a repeat waits for the heartbeat. No reading sends nothing and
  /// stops the heartbeat until there is one.
  void update(AnalyzerReading? r, ReadingStability s) {
    if (!_running) return;
    final live = liveStateFor(r, s);
    if (live == null) {
      _last = null;
      _timer?.cancel();
      _timer = null;
      return;
    }
    final message = formatState(live.state, mix: live.mix);
    if (message == _last) return;
    _last = message;
    _sendNow();
  }

  /// Sends [_last] and arms the heartbeat for the next send.
  void _sendNow() {
    final message = _last;
    if (!_running || message == null) return;
    _timer?.cancel();
    _timer = Timer(_heartbeat, _sendNow);
    try {
      unawaited(_send(message).catchError((Object _) {}));
    } catch (_) {
      // A send that throws at once is as good as one that failed later: the
      // next heartbeat tries again.
    }
  }
}
