/// Recognises an OK press on a Divesoft SOLO from its USB line stream
/// (issue #113, Log on OK).
///
/// Pressing OK suspends the SOLO's measurement, and its USB output then stops
/// completely until OK is pressed again. So an OK press is a silence in a
/// stream that had been flowing: the last line before it is the reading the
/// SOLO's display froze on. This is the Dart twin of the ESP32 bridge's
/// firmware rule, with the same named thresholds (spec section 1 and 4c,
/// `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md`).
///
/// The rule, evaluated on every [HoldDetector.tick]:
///
///  * A hold needs a line seen, and at least [HoldDetector.silence] since the
///    last one.
///  * It fires once per silence: [HoldDetector.tick] returns it the first
///    time and nothing more until a line arrives again (the resume).
///  * The flow before it must have lasted long enough, counted from the
///    first line after construction or [HoldDetector.detached], or from the
///    first line after the last hold: [HoldDetector.firstMinFlow] for the
///    first hold since attach (this also skips the stale burst a SOLO
///    sends when it attaches), [HoldDetector.nextMinFlow] for later ones (a
///    stray resume-and-suspend must not make a second record within
///    seconds).
///  * A silence that does not fire does not move the start of the flow, so a
///    dip shorter than [HoldDetector.silence] (a quick double OK) never
///    resets arming.
///  * Leaving the transport ([HoldDetector.detached]) cancels a pending
///    hold and resets everything. Switching the SOLO off shows up as a USB
///    detach within 0.6 s, before the silence is long enough.
///
/// Pure Dart: no Flutter, no I/O, no timers. It reacts only to the calls and
/// the times it is given, so the caller decides what "now" is and a test can
/// replay a capture.
library;

import 'dart:collection';

import 'bridge/bridge_protocol.dart';
import 'protocol/solo_line_parser.dart';

/// Silence, while attached, that makes a hold.
const Duration kHoldSilence = Duration(seconds: 2);

/// Flow needed before the first hold after the SOLO attaches.
const Duration kFirstHoldMinFlow = Duration(seconds: 5);

/// Flow needed since the last resume before any later hold.
const Duration kNextHoldMinFlow = Duration(seconds: 3);

/// How much of the lines before a hold goes into [DetectedHold.window].
const Duration kHoldWindow = Duration(seconds: 30);

/// One detected OK press.
class DetectedHold {
  const DetectedHold({
    required this.heldAt,
    required this.heldLine,
    required this.window,
  });

  /// The elapsed time, on the caller's clock, of the held (last) line.
  final Duration heldAt;

  /// The held line, as it was given to [HoldDetector.addLine].
  final String heldLine;

  /// The data lines within [kHoldWindow] up to and including the held line,
  /// oldest first. Offsets are milliseconds relative to [heldAt], so zero or
  /// negative, and the last one is zero.
  final List<BridgeWindowLine> window;
}

/// Finds OK presses in a stream of SOLO lines. See the library comment for
/// the rule.
class HoldDetector {
  HoldDetector({
    this.silence = kHoldSilence,
    this.firstMinFlow = kFirstHoldMinFlow,
    this.nextMinFlow = kNextHoldMinFlow,
    this.window = kHoldWindow,
  });

  final Duration silence;
  final Duration firstMinFlow;
  final Duration nextMinFlow;
  final Duration window;

  /// The data lines of the last [window], oldest first.
  final Queue<({Duration at, String line})> _lines = Queue();

  /// When the current flow began; null until the first line after
  /// construction or [detached].
  Duration? _flowStart;

  /// How many holds fired since the last [detached].
  int _holds = 0;

  /// A hold fired for the silence that is still going on. The next data line
  /// is its resume.
  bool _holdFired = false;

  Duration? get _lastLineAt => _lines.isEmpty ? null : _lines.last.at;

  /// Feeds one line from the SOLO, arriving at [elapsed]. Lines that carry
  /// no reading (banners, blanks, garbage) are not flow and are ignored
  /// altogether.
  void addLine(Duration elapsed, String line) {
    if (parseSoloLine(line) == null) return;
    if (_flowStart == null || _holdFired) {
      // The first line since attach, or the resume after a hold.
      _flowStart = elapsed;
      _holdFired = false;
    }
    _lines.add((at: elapsed, line: line));
    while (elapsed - _lines.first.at > window) {
      _lines.removeFirst();
    }
  }

  /// Asks, at [elapsed], whether an OK press has happened. Returns the hold
  /// the first time the rule is met during a silence, null otherwise. Call
  /// it as often as is convenient while the transport is attached; the
  /// silence is measured from the last line, not from the last tick.
  DetectedHold? tick(Duration elapsed) {
    final lastLineAt = _lastLineAt;
    final flowStart = _flowStart;
    if (lastLineAt == null || flowStart == null || _holdFired) return null;
    if (elapsed - lastLineAt < silence) return null;
    final minFlow = _holds == 0 ? firstMinFlow : nextMinFlow;
    if (lastLineAt - flowStart < minFlow) return null;

    _holdFired = true;
    _holds++;
    return DetectedHold(
      heldAt: lastLineAt,
      heldLine: _lines.last.line,
      window: List.unmodifiable([
        for (final l in _lines)
          BridgeWindowLine((l.at - lastLineAt).inMilliseconds, l.line),
      ]),
    );
  }

  /// The transport is gone (cable pulled, SOLO switched off, session closed):
  /// forget the lines, the arming and the hold count, and with them any hold
  /// that was waiting for its silence to be long enough.
  void detached() {
    _lines.clear();
    _flowStart = null;
    _holds = 0;
    _holdFired = false;
  }
}
