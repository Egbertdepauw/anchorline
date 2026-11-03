/// A cylinder fill pressure as the diver types it (gas analysis log).
///
/// Shared by the edit sheet and the analyzer's save card, so a typo is
/// judged the same way in both: neither saves a mistyped pressure as "no
/// pressure" without saying so.
library;

/// The typed fill pressure in bar. Blank is valid and means none ([bar] null);
/// the decimal separator is `,` or `.`, as in the cylinder screen. Anything
/// that is not a finite number of at least 0 (`21o`, `-5`, `abc`) is not valid:
/// [valid] is false and [bar] is null.
({bool valid, double? bar}) parseFillPressure(String s) {
  final t = s.trim();
  if (t.isEmpty) return (valid: true, bar: null);
  final v = double.tryParse(t.replaceAll(',', '.'));
  if (v == null || !v.isFinite || v < 0) return (valid: false, bar: null);
  return (valid: true, bar: v);
}
