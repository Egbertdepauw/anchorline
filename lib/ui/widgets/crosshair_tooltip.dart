import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../util/tank_labels.dart';
import 'profile_chart.dart' show cellTraceLabelForSlot;

class CrosshairTooltip extends StatelessWidget {
  final SampleSet samples;
  final int sampleIndex;
  final Set<TraceType> visibleTraces;
  final double chartX;
  final double chartWidth;
  final Map<int, OxygenCell>? cellsBySlot;
  final List<DiveTank>? tanks;
  final Map<int, Cylinder>? mappedCylinders;
  final List<DiveGasMix>? gasMixes;

  const CrosshairTooltip({
    super.key,
    required this.samples,
    required this.sampleIndex,
    required this.visibleTraces,
    required this.chartX,
    required this.chartWidth,
    this.cellsBySlot,
    this.tanks,
    this.mappedCylinders,
    this.gasMixes,
  });

  String _cellLabelOrFallback(int slot, String fallback) {
    if (cellsBySlot == null || cellsBySlot!.isEmpty) return fallback;
    return cellTraceLabelForSlot(cellsBySlot, slot);
  }

  static String _gasMixLabel(DiveGasMix mix) {
    if (mix.heliumPercent > 0) {
      return '${mix.oxygenPercent}/${mix.heliumPercent}';
    }
    if (mix.oxygenPercent == 21) return 'Air';
    if (mix.oxygenPercent == 100) return 'O₂';
    return 'EAN${mix.oxygenPercent}';
  }

  /// Instantaneous vertical-speed at [i], computed from the previous
  /// sample. Returns "—" for the very first sample, "0 m/min" when
  /// effectively flat, otherwise an arrow-prefixed rate.
  String _verticalRateAt(int i) {
    if (i == 0) return '—';
    final delta = samples.depthMeters[i] - samples.depthMeters[i - 1];
    final rate = delta * 60000.0 / samples.sampleIntervalMs;
    if (rate.round() == 0) return '0 m/min';
    if (rate > 0) return '↓ ${rate.round()} m/min';
    return '↑ ${(-rate).round()} m/min';
  }

  @override
  Widget build(BuildContext context) {
    final i = sampleIndex.clamp(0, samples.sampleCount - 1);
    final timeMs = (i + 1) * samples.sampleIntervalMs;
    final minutes = timeMs ~/ 60000;
    final seconds = (timeMs % 60000) ~/ 1000;

    final rows = <_Row>[
      _Row('Time', '$minutes:${seconds.toString().padLeft(2, '0')}'),
      _Row('Depth', '${samples.depthMeters[i].toStringAsFixed(1)}m'),
      _Row('Rate', _verticalRateAt(i)),
    ];
    if (visibleTraces.contains(TraceType.ppo2)) {
      rows.add(_Row('PPO2', '${samples.ppo2Bar[i].toStringAsFixed(2)} bar'));
    }
    if (visibleTraces.contains(TraceType.setpoint)) {
      rows.add(_Row('SP', '${samples.setpointBar[i].toStringAsFixed(2)} bar'));
    }
    if (visibleTraces.contains(TraceType.cells)) {
      rows.add(_Row(
          _cellLabelOrFallback(1, 'C1'), samples.cellMv0[i].toStringAsFixed(2)));
      rows.add(_Row(
          _cellLabelOrFallback(2, 'C2'), samples.cellMv1[i].toStringAsFixed(2)));
      rows.add(_Row(
          _cellLabelOrFallback(3, 'C3'), samples.cellMv2[i].toStringAsFixed(2)));
    }
    rows.add(_Row('Temp', '${samples.temperatureCelsius[i].toStringAsFixed(1)}°C'));

    if (visibleTraces.contains(TraceType.gasChanges) &&
        gasMixes != null &&
        gasMixes!.isNotEmpty &&
        i < samples.gasMixIndex.length) {
      final idx = samples.gasMixIndex[i];
      if (idx < gasMixes!.length) {
        final mix = gasMixes![idx];
        final label = _gasMixLabel(mix);
        final tag = mix.isDiluent ? 'Dil' : 'OC';
        rows.add(_Row('Gas', '$label  ($tag)'));
      }
    }

    if (tanks != null &&
        tanks!.isNotEmpty &&
        samples.tankPressuresBar.isNotEmpty) {
      final tankRows = <_Row>[];
      final n = tanks!.length < samples.tankPressuresBar.length
          ? tanks!.length
          : samples.tankPressuresBar.length;
      for (var t = 0; t < n; t++) {
        final ch = samples.tankPressuresBar[t];
        if (i >= ch.length) continue;
        final p = ch[i];
        if (p == 0) continue;
        tankRows.add(
            _Row(labelForTank(tanks![t], mappedCylinders), '${p.round()} bar'));
      }
      rows.addAll(tankRows);
    }

    final onRightSide = chartX > chartWidth / 2;

    return Align(
      alignment:
          onRightSide ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xE0152238),
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 40, maxWidth: 110),
                      child: Text(row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF778899), fontSize: 10))),
                  const SizedBox(width: 6),
                  Text(row.value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ]),
              )
          ],
        ),
      ),
    );
  }
}

class _Row {
  final String label, value;
  _Row(this.label, this.value);
}
