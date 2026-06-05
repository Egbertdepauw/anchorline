import 'package:flutter/material.dart';
import '../../analysis/deco/replay_result.dart';
import '../../data/db/database.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import 'trace_segmented_bar.dart' show TraceType;
import '../theme/gf_color.dart';
import '../util/tank_labels.dart';
import 'profile_chart.dart' show cellTraceLabelForSlot;

/// Readout panel shown at the profile crosshair.
///
/// Two layouts, chosen by available width:
/// - **Wide** (desktop / tablet / phone-landscape): the roomy vertical
///   label:value list.
/// - **Narrow** (phone portrait): a compact two-tier readout — a prominent
///   depth/time/rate header over dense paired chips — so it never swamps the
///   short mobile chart. Compact chips are gated on the visible traces, so the
///   readout mirrors exactly what you've toggled on.
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
  final DecoReplayResult? decoReplay;

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
    this.decoReplay,
  });

  /// Below this chart width we switch to the compact two-tier readout.
  static const double _compactBelow = 520;
  static const Color _labelColor = Color(0xFF778899);
  static const Color _subColor = Color(0xFF9FB0C0);
  static const Color _boxColor = Color(0xE0152238);

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
  /// sample. Returns "—" for the very first sample or a non-finite rate
  /// (merged-dive surface gaps carry NaN depth), "0 m/min" when
  /// effectively flat, otherwise an arrow-prefixed rate.
  String _verticalRateAt(int i) {
    if (i == 0) return '—';
    final delta = samples.depthMeters[i] - samples.depthMeters[i - 1];
    final rate = delta * 60000.0 / samples.sampleIntervalMs;
    // NaN/Infinity .round() throws "Infinity or NaN toInt" — guard first.
    if (!rate.isFinite) return '—';
    if (rate.round() == 0) return '0 m/min';
    if (rate > 0) return '↓ ${rate.round()} m/min';
    return '↑ ${(-rate).round()} m/min';
  }

  /// Deco/TTS/NDL durations are whole-minute values from the DC, stored as
  /// seconds. Render them in minutes.
  static String _fmtMinutes(int seconds) => '${(seconds / 60).round()} min';

  String _timeAt(int i) {
    final timeMs = (i + 1) * samples.sampleIntervalMs;
    final minutes = timeMs ~/ 60000;
    final seconds = (timeMs % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final i = sampleIndex.clamp(0, samples.sampleCount - 1);
    final onRightSide = chartX > chartWidth / 2;
    final child = chartWidth < _compactBelow ? _buildCompact(i) : _buildList(i);
    return Align(
      alignment: onRightSide ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }

  // ── Wide layout: vertical label:value list ────────────────────────────
  Widget _buildList(int i) {
    final rows = <_Row>[
      _Row('Time', _timeAt(i)),
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
    rows.add(
        _Row('Temp', '${samples.temperatureCelsius[i].toStringAsFixed(1)}°C'));

    // ── Decompression group ───────────────────────────────────────────
    final inDeco = i < samples.decoStopDepthMeters.length &&
        samples.decoStopDepthMeters[i] > 0;
    final decoTimeAt =
        i < samples.decoTimeSeconds.length ? samples.decoTimeSeconds[i] : 0;
    final ttsAt = i < samples.ttsSeconds.length ? samples.ttsSeconds[i] : 0;
    final replay = decoReplay;
    final decoRows = <_Row>[];
    if (inDeco) {
      decoRows.add(_Row(
          'Stop', '${samples.decoStopDepthMeters[i].toStringAsFixed(1)}m'));
      decoRows.add(_Row('Stop time', _fmtMinutes(decoTimeAt)));
    } else if (decoTimeAt > 0) {
      decoRows.add(_Row('NDL', _fmtMinutes(decoTimeAt)));
    }
    if (ttsAt > 0) {
      decoRows.add(_Row('TTS', _fmtMinutes(ttsAt)));
    }
    if (replay != null) {
      if (i < replay.ceilingMeters.length && replay.ceilingMeters[i] > 0) {
        decoRows.add(_Row(
            'Ceiling', '${replay.ceilingMeters[i].toStringAsFixed(1)}m'));
      }
      if (i < replay.gf99Series.length && replay.gf99Series[i].isFinite) {
        final gf = replay.gf99Series[i];
        decoRows.add(_Row('GF99', '${gf.round()}%',
            valueColor: gfBandColor(gf, gfHigh: (replay.gfHigh ?? 85).toDouble())));
      }
    }
    if (decoRows.isNotEmpty) {
      rows.add(_Row.divider());
      rows.addAll(decoRows);
    }

    if (visibleTraces.contains(TraceType.gasChanges) &&
        gasMixes != null &&
        gasMixes!.isNotEmpty &&
        i < samples.gasMixIndex.length) {
      final idx = samples.gasMixIndex[i];
      if (idx < gasMixes!.length) {
        final mix = gasMixes![idx];
        final tag = mix.isDiluent ? 'Dil' : 'OC';
        rows.add(_Row('Gas', '${_gasMixLabel(mix)}  ($tag)'));
      }
    }

    if (tanks != null &&
        tanks!.isNotEmpty &&
        samples.tankPressuresBar.isNotEmpty) {
      final n = tanks!.length < samples.tankPressuresBar.length
          ? tanks!.length
          : samples.tankPressuresBar.length;
      for (var t = 0; t < n; t++) {
        final ch = samples.tankPressuresBar[t];
        if (i >= ch.length) continue;
        final p = ch[i];
        if (p == 0 || !p.isFinite) continue;
        rows.add(
            _Row(labelForTank(tanks![t], mappedCylinders), '${p.round()} bar'));
      }
    }

    return IntrinsicWidth(
      child: Container(
        key: const ValueKey('crosshairTooltipBox'),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: _boxColor, borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              if (row.isDivider)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: _labelColor.withValues(alpha: 0.25),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 40, maxWidth: 110),
                        child: Text(row.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _labelColor, fontSize: 10))),
                    const SizedBox(width: 6),
                    Text(row.value,
                        style: TextStyle(
                            color: row.valueColor ?? Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                )
          ],
        ),
      ),
    );
  }

  // ── Narrow layout: compact two-tier readout ───────────────────────────
  Widget _buildCompact(int i) {
    final chips = _compactChips(i);
    // Bounded so the chip Wrap reflows (typically 2 per row) and the box stays
    // short. Scales gently with the chart but never spans it.
    final maxW = (chartWidth * 0.62).clamp(170.0, 250.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        key: const ValueKey('crosshairTooltipBoxCompact'),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: _boxColor, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _compactHeader(i),
            if (chips.isNotEmpty) ...[
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 7),
                color: _labelColor.withValues(alpha: 0.25),
              ),
              Wrap(spacing: 12, runSpacing: 5, children: chips),
            ],
          ],
        ),
      ),
    );
  }

  /// Tier 1: prominent depth, with time + vertical rate stacked beside it.
  Widget _compactHeader(int i) {
    final depthFinite = samples.depthMeters[i].isFinite;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
              text: depthFinite
                  ? samples.depthMeters[i].toStringAsFixed(1)
                  : '—',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (depthFinite)
            const TextSpan(
                text: ' m',
                style: TextStyle(
                    color: _subColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
        ])),
        const SizedBox(width: 12),
        // Flexible + non-wrapping text so a long rate string can never
        // overflow the box on a very narrow chart (it clips/ellipsizes).
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_timeAt(i),
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text(_verticalRateAt(i),
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                      color: _subColor, fontSize: 10, height: 1.25)),
            ],
          ),
        ),
      ],
    );
  }

  /// One compact chip: dim label + bright value, sharing a baseline.
  Widget _chip(String label, String value, {Color? valueColor}) {
    return Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label ',
          style: const TextStyle(color: _labelColor, fontSize: 9, height: 1.1)),
      TextSpan(
          text: value,
          style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]));
  }

  /// Tier 2 chips, each gated on its trace so the readout mirrors the visible
  /// traces. NaN/Infinity guarded everywhere a value is rounded.
  List<Widget> _compactChips(int i) {
    final chips = <Widget>[];
    if (visibleTraces.contains(TraceType.ppo2)) {
      chips.add(_chip('PPO2', samples.ppo2Bar[i].toStringAsFixed(2)));
    }
    if (visibleTraces.contains(TraceType.setpoint)) {
      chips.add(_chip('SP', samples.setpointBar[i].toStringAsFixed(2)));
    }
    if (visibleTraces.contains(TraceType.cells)) {
      chips.add(_chip(
          _cellLabelOrFallback(1, 'C1'), samples.cellMv0[i].toStringAsFixed(2)));
      chips.add(_chip(
          _cellLabelOrFallback(2, 'C2'), samples.cellMv1[i].toStringAsFixed(2)));
      chips.add(_chip(
          _cellLabelOrFallback(3, 'C3'), samples.cellMv2[i].toStringAsFixed(2)));
    }
    if (visibleTraces.contains(TraceType.waterTemp)) {
      chips.add(
          _chip('Temp', '${samples.temperatureCelsius[i].toStringAsFixed(1)}°'));
    }
    if (visibleTraces.contains(TraceType.deco)) {
      final inDeco = i < samples.decoStopDepthMeters.length &&
          samples.decoStopDepthMeters[i] > 0;
      final decoTimeAt =
          i < samples.decoTimeSeconds.length ? samples.decoTimeSeconds[i] : 0;
      final ttsAt = i < samples.ttsSeconds.length ? samples.ttsSeconds[i] : 0;
      if (inDeco) {
        chips.add(_chip('Stop',
            '${samples.decoStopDepthMeters[i].toStringAsFixed(1)} m · ${(decoTimeAt / 60).round()} min'));
      } else if (decoTimeAt > 0) {
        chips.add(_chip('NDL', '${(decoTimeAt / 60).round()} min'));
      }
      if (ttsAt > 0) {
        chips.add(_chip('TTS', '${(ttsAt / 60).round()} min'));
      }
    }
    final replay = decoReplay;
    if (replay != null) {
      if (visibleTraces.contains(TraceType.ceiling) &&
          i < replay.ceilingMeters.length &&
          replay.ceilingMeters[i] > 0) {
        chips.add(_chip('Ceil', '${replay.ceilingMeters[i].toStringAsFixed(1)} m'));
      }
      if (visibleTraces.contains(TraceType.gf99) &&
          i < replay.gf99Series.length &&
          replay.gf99Series[i].isFinite) {
        final gf = replay.gf99Series[i];
        chips.add(_chip('GF99', '${gf.round()}%',
            valueColor: gfBandColor(gf, gfHigh: (replay.gfHigh ?? 85).toDouble())));
      }
    }
    if (visibleTraces.contains(TraceType.gasChanges) &&
        gasMixes != null &&
        gasMixes!.isNotEmpty &&
        i < samples.gasMixIndex.length) {
      final idx = samples.gasMixIndex[i];
      if (idx < gasMixes!.length) {
        chips.add(_chip('Gas', _gasMixLabel(gasMixes![idx])));
      }
    }
    if (visibleTraces.contains(TraceType.tanks) &&
        tanks != null &&
        tanks!.isNotEmpty &&
        samples.tankPressuresBar.isNotEmpty) {
      final n = tanks!.length < samples.tankPressuresBar.length
          ? tanks!.length
          : samples.tankPressuresBar.length;
      for (var t = 0; t < n; t++) {
        final ch = samples.tankPressuresBar[t];
        if (i >= ch.length) continue;
        final p = ch[i];
        if (p == 0 || !p.isFinite) continue;
        chips.add(_chip(labelForTank(tanks![t], mappedCylinders), '${p.round()}'));
      }
    }
    return chips;
  }
}

class _Row {
  final String label, value;
  final Color? valueColor;
  final bool isDivider;
  _Row(this.label, this.value, {this.valueColor}) : isDivider = false;
  _Row.divider()
      : label = '',
        value = '',
        valueColor = null,
        isDivider = true;
}
