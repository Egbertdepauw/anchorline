/// Dive events (bookmark, gas switch, setpoint change, warnings).
///
/// Lives under `data/models` so the stored-event codec and the parser's
/// data types share one definition. `parsed_dive.dart` re-exports it.
library;

/// Dive event (bookmark, compass heading, gas switch, ...).
class DiveEvent {
  final int timeMs;
  final DiveEventType type;

  /// The engine's own event number (0 when not known).
  final int rawType;
  final int? bearing;
  final int? value;

  DiveEvent({
    required this.timeMs,
    required this.type,
    this.rawType = 0,
    this.bearing,
    this.value,
  });
}

/// Event kinds. [wire] is the code stored in the events blob; it never
/// changes once assigned, whatever the declaration order.
enum DiveEventType {
  other(0),
  bookmark(1),
  gasSwitch(2),
  setpointChange(3),
  decoWarning(4),
  ceilingViolation(5),
  ascentWarning(6);

  final int wire;

  const DiveEventType(this.wire);

  /// Maps a stored code back to a type; unknown codes become [other].
  static DiveEventType fromWire(int wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return other;
  }
}
