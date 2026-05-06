import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';
import 'profile_chart.dart' show cellTraceLabelForSlot;

class CrosshairTooltip extends StatelessWidget {
  final SampleSet samples;
  final int sampleIndex;
  final Set<TraceType> visibleTraces;
  final double chartX;
  final double chartWidth;
  final Map<int, OxygenCell>? cellsBySlot;

  const CrosshairTooltip({
    super.key,
    required this.samples,
    required this.sampleIndex,
    required this.visibleTraces,
    required this.chartX,
    required this.chartWidth,
    this.cellsBySlot,
  });

  String _cellLabelOrFallback(int slot, String fallback) {
    if (cellsBySlot == null || cellsBySlot!.isEmpty) return fallback;
    return cellTraceLabelForSlot(cellsBySlot, slot);
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
