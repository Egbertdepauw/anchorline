import 'package:subsurface_core/subsurface_core.dart';

import '../parse/parsed_dive.dart';
import 'resample.dart';

/// libdivecomputer's `parser_sample_event_t` numbers that Anchorline names.
const int _evDecostop = 1;
const int _evAscent = 3;
const int _evCeiling = 4;
const int _evViolation = 7;
const int _evBookmark = 8;
const int _evDeepstop = 14;
const int _evCeilingSafetystop = 15;

/// A setpoint change smaller than this is noise.
const double _setpointStepBar = 0.05;

DiveEventType eventTypeFor(int rawType) => switch (rawType) {
  _evBookmark => DiveEventType.bookmark,
  _evCeiling || _evCeilingSafetystop => DiveEventType.ceilingViolation,
  _evAscent => DiveEventType.ascentWarning,
  _evDecostop || _evDeepstop || _evViolation => DiveEventType.decoWarning,
  _ => DiveEventType.other,
};

/// Events for the stored events blob, at the exact times of the rows that
/// carried them, in row order. [gasIndex] translates a row's gas mix index
/// as in `resample`; the switch value is the translated index.
///
/// The baselines for "change" are the first values the dive reports, so a dive
/// that opens on a setpoint or a gas gets no event for it; only later
/// differences do.
List<DiveEvent> buildEvents(
  List<LibdcSampleRow> rows, {
  int? Function(int index)? gasIndex,
}) {
  final sorted = rowsInTimeOrder(rows);
  final events = <DiveEvent>[];
  int? gas;
  double? setpoint;
  for (final r in sorted) {
    final g = r.gasMix;
    if (g != null) {
      final mapped = gasIndex == null ? g : gasIndex(g);
      if (mapped != null && gas == null) {
        gas = mapped;
      } else if (mapped != null && mapped != gas) {
        gas = mapped;
        events.add(
          DiveEvent(
            timeMs: r.timeMs,
            type: DiveEventType.gasSwitch,
            value: mapped,
          ),
        );
      }
    }
    final sp = r.setpoint;
    if (sp != null) {
      if (setpoint != null &&
          (sp - setpoint).abs() >= _setpointStepBar - 1e-9) {
        events.add(
          DiveEvent(
            timeMs: r.timeMs,
            type: DiveEventType.setpointChange,
            value: (sp * 100).round(),
          ),
        );
      }
      setpoint = sp;
    }
    for (final e in r.events) {
      final fits = e.value >= 0 && e.value <= 0x7fffffff;
      events.add(
        DiveEvent(
          timeMs: r.timeMs,
          type: eventTypeFor(e.type),
          rawType: e.type,
          value: fits ? e.value : null,
        ),
      );
    }
  }
  return events;
}
