/// The single mix-naming scheme for the whole app.
///
/// Pure Dart, no Flutter imports. Every UI label for a breathing gas goes
/// through [gasMixName] (whole percentages) or, for the gas analyzer
/// readout only, [gasMixNameDecimal]. Inputs are PERCENTAGES (0–100).
///
/// Classification, in this order:
///
/// | Rule                                   | Label            |
/// |----------------------------------------|------------------|
/// | O2 ≥ 99.5                              | `O2`             |
/// | He = 0 and 20.5 ≤ O2 ≤ 21.5            | `Air`            |
/// | He > 0 and O2 + He ≥ 99                | `Hx{o2}/{he}`    |
/// | He > 0 otherwise                       | `Tx{o2}/{he}`    |
/// | He = 0 and O2 > 21.5                   | `EAN{o2}`        |
/// | He = 0 and O2 < 20.5                   | `Hypoxic {o2}`   |
library;

/// Lower edge of the Air band (O2 %, inclusive).
const double kAirO2MinPercent = 20.5;

/// Upper edge of the Air band (O2 %, inclusive).
const double kAirO2MaxPercent = 21.5;

/// O2 % at or above which a mix is called pure oxygen.
const double kOxygenMinPercent = 99.5;

/// O2 + He % at or above which a helium mix is heliox rather than trimix.
const double kHelioxMinO2HePercent = 99.0;

/// Diver-facing name for a mix, with percentages rounded to whole numbers
/// (half away from zero, Dart's `round()`): `Air`, `O2`, `EAN32`,
/// `Tx21/35`, `Hx10/90`, `Hypoxic 18`.
///
/// The mix is classified AFTER rounding, so the label always agrees with
/// the numbers shown: 20.6/0 → 21 → `Air`, 99.6/0 → 100 → `O2`,
/// 21.3/34.2 → `Tx21/34`.
String gasMixName(num o2Percent, num hePercent) {
  final o2 = _nonNegative(o2Percent).round();
  final he = _nonNegative(hePercent).round();
  return _name(
    o2: o2.toDouble(),
    he: he.toDouble(),
    heIsZero: he == 0,
    o2Text: '$o2',
    heText: '$he',
  );
}

/// Diver-facing name for an analysed mix with [decimals] decimal places
/// (default one), for the gas analyzer readout: `Tx21.4/34.2`, `EAN32.4`,
/// `Hx10.1/89.6`, `Hypoxic 18.2`. Air and O2 are classified from the raw
/// values with the same bands as [gasMixName] and shown without numbers.
///
/// He counts as zero when it displays as zero at [decimals] places, so a
/// 0.02 % He sensor wobble on an air fill still reads `Air`, never
/// `Tx20.9/0.0`. Negative sensor noise is clamped to 0.
String gasMixNameDecimal(double o2Percent, double hePercent,
    {int decimals = 1}) {
  final o2 = _nonNegative(o2Percent).toDouble();
  final he = _nonNegative(hePercent).toDouble();
  final heText = he.toStringAsFixed(decimals);
  return _name(
    o2: o2,
    he: he,
    heIsZero: double.parse(heText) == 0,
    o2Text: o2.toStringAsFixed(decimals),
    heText: heText,
  );
}

String _name({
  required double o2,
  required double he,
  required bool heIsZero,
  required String o2Text,
  required String heText,
}) {
  if (o2 >= kOxygenMinPercent) return 'O2';
  if (!heIsZero) {
    if (o2 + he >= kHelioxMinO2HePercent) return 'Hx$o2Text/$heText';
    return 'Tx$o2Text/$heText';
  }
  if (o2 >= kAirO2MinPercent && o2 <= kAirO2MaxPercent) return 'Air';
  if (o2 > kAirO2MaxPercent) return 'EAN$o2Text';
  return 'Hypoxic $o2Text';
}

num _nonNegative(num v) => v < 0 ? 0 : v;
