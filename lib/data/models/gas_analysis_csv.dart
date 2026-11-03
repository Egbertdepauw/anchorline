/// CSV export of the cylinder analysis log (issue #111).
///
/// Pure Dart. Columns match the analyzer prototype
/// (`docs/prototypes/solo-live.html`):
/// time, cylinder, diver, mix, o2, he, mod_1_1, mod_1_4, mod_1_6,
/// pressure_bar, temp_c, stable, then desired_mix (the desired mix name,
/// empty when none was set), gas_role (`bailout` or `diluent`),
/// analysed_for (who the gas is for, empty when not set) and needs_signoff
/// (`true` while the entry waits for sign-off in the log).
///
/// The three MOD columns are always at ppO2 1.1 / 1.4 / 1.6, whatever MOD
/// set the diver had configured, so exports from different settings line
/// up. Mix is the whole-number name, like everywhere outside the live
/// readout. Every field is quoted (RFC 4180, `"` doubled).
library;

import 'gas_analysis.dart';

const gasAnalysisCsvHeader = <String>[
  'time',
  'cylinder',
  'diver',
  'mix',
  'o2',
  'he',
  'mod_1_1',
  'mod_1_4',
  'mod_1_6',
  'pressure_bar',
  'temp_c',
  'stable',
  'desired_mix',
  'gas_role',
  'analysed_for',
  'needs_signoff',
];

/// ppO2 limits (bar) of the mod_1_1 / mod_1_4 / mod_1_6 columns.
const gasAnalysisCsvModPpo2s = <double>[1.1, 1.4, 1.6];

/// Builds the CSV text for [analyses] in the given order. Times are
/// ISO-8601 in UTC so the file reads the same in any time zone.
String gasAnalysesToCsv(List<GasAnalysis> analyses) {
  String fixed1(double? v) =>
      v == null || !v.isFinite ? '' : v.toStringAsFixed(1);
  String mod(GasAnalysis a, double ppo2) {
    final m = a.modAt(ppo2);
    return m.isFinite && m > 0 ? m.toStringAsFixed(1) : '';
  }

  final rows = <List<String>>[
    gasAnalysisCsvHeader,
    for (final a in analyses)
      [
        a.analysedAt.toUtc().toIso8601String(),
        a.cylinderDisplay ?? '',
        a.analysedBy ?? '',
        a.mixName,
        fixed1(a.o2Percent),
        fixed1(a.hePercent),
        for (final p in gasAnalysisCsvModPpo2s) mod(a, p),
        fixed1(a.fillPressureBar),
        fixed1(a.tempC),
        a.stable ? 'true' : 'false',
        a.desiredMix?.name ?? '',
        a.gasRole.dbValue,
        a.analysedFor ?? '',
        a.needsSignoff ? 'true' : 'false',
      ],
  ];
  return '${rows.map((r) => r.map(_quote).join(',')).join('\n')}\n';
}

String _quote(String v) => '"${v.replaceAll('"', '""')}"';
