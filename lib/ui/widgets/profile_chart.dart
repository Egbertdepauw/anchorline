/// Multi-trace dive profile chart.
///
/// Renders depth, PPO2, setpoint, deco ceiling, O2 cells, and an
/// optional crosshair scrubber on a [CustomPaint] canvas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../analysis/gas_density.dart';
import '../../analysis/end.dart';
import '../../analysis/deco/replay_result.dart';
import '../../data/db/database.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import 'trace_segmented_bar.dart' show TraceType;
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../util/tank_labels.dart';

/// Builds a polyline [Path] over the first [n] samples of [data], starting a
/// fresh subpath after any NaN sample. A NaN coordinate makes Skia reject the
/// ENTIRE path (drawing nothing), so without this a merged-dive surface gap
/// (NaN) would erase the whole trace — PPO2, setpoint, temperature, cells.
/// Breaking at NaN also gives the right visual: the trace stops over the
/// surface and resumes on the next dive segment.
Path buildBrokenTracePath(
  Float32List data,
  int n,
  double Function(int) xOf,
  double Function(double) yOf,
) {
  final path = Path();
  var penDown = false;
  for (var i = 0; i < n; i++) {
    final v = data[i];
    if (v.isNaN) {
      penDown = false;
      continue;
    }
    final x = xOf(i);
    final y = yOf(v);
    if (penDown) {
      path.lineTo(x, y);
    } else {
      path.moveTo(x, y);
      penDown = true;
    }
  }
  return path;
}

// ── Layout constants ────────────────────────────────────────────

const double _leftPad = 40.0;
const double _rightPad = 44.0;
const double _topPad = 8.0;
const double _bottomPad = 24.0;

// ── Trace colours ───────────────────────────────────────────────
//
// Themed trace colours (depth, PPO2, setpoint, cells, grid) come from the
// active `ThemePalette`, passed into the painter.

const Color _decoColor = SafetyColors.warning;
const Color _crosshairColor = Color(0x80FFFFFF);
const Color _gasChangeColor = SafetyColors.info;
const Color _bailoutColor = SafetyColors.danger;
// Water temperature trace — must match the swatch in
// `trace_segmented_bar.dart` so the dot in the legend agrees with the
// trace on the chart.
const Color _waterTempColor = Color(0xFF4DD0E1);

// Tank-trace palette per tank slot. Picked to be distinct from the
// existing depth/cell/setpoint colours.
const List<Color> _tankColors = [
  Color(0xFF80DEEA), // cyan-ish
  Color(0xFFFFAB91), // peach
  Color(0xFFCE93D8), // lilac
  Color(0xFFB0BEC5), // blue grey
  Color(0xFFA5D6A7), // pale green
  Color(0xFFFFE082), // pale amber
];

/// Implicit y-axis range for tank traces, in bar.
const double _tankBarMax = 300.0;

// ── Speed gradient (Subsurface anchor speeds, smooth interpolation) ──
//
// Subsurface uses 5 discrete velocity buckets (STABLE/SLOW/MODERATE/FAST/
// CRAZY) with asymmetric thresholds (ascent flagged earlier than descent
// because DCS risk is on the way up). We use the same anchor speeds, but
// interpolate Color.lerp between consecutive anchors so the trace reads
// as a continuous gradient rather than five sharp colour bands.
//
// Speed convention: signed m/min. Negative = ascent (depth decreasing),
// positive = descent (depth increasing). STABLE keeps the existing depth
// blue so a calm dive looks the way it always has.
const Color _vSpeedSlowColor = Color(0xFFA8D957);        // lime
const Color _vSpeedModerateColor = Color(0xFFE5C73F);    // amber
const Color _vSpeedFastColor = Color(0xFFEC8A3D);        // orange
const Color _vSpeedCrazyColor = Color(0xFFE65656);       // red

// Anchor table sorted by speed ascending. _colorForRate finds the bracket
// containing the segment's signed rate and lerps between the two anchors.
// [stable] is the theme's depth-trace colour, so a calm dive looks like a
// plain depth trace.
List<({double speed, Color color})> _vSpeedAnchorsFor(Color stable) => [
      (speed: -30.0, color: _vSpeedCrazyColor),
      (speed: -18.2, color: _vSpeedCrazyColor),
      (speed: -9.1, color: _vSpeedFastColor),
      (speed: -4.6, color: _vSpeedModerateColor),
      (speed: -1.5, color: _vSpeedSlowColor),
      (speed: 0.0, color: stable),
      (speed: 1.5, color: _vSpeedSlowColor),
      (speed: 9.1, color: _vSpeedModerateColor),
      (speed: 18.2, color: _vSpeedFastColor),
      (speed: 30.4, color: _vSpeedCrazyColor),
      (speed: 60.0, color: _vSpeedCrazyColor),
    ];

const double _ppo2Max = 2.0;

// ── Density + END band colours ───────────────────────────────────
const Color _bandGreen = Color(0xFF4ADE80);
const Color _bandOrange = Color(0xFFF59E0B);
const Color _bandRed = Color(0xFFDC2626);

Color _colorForDensityBand(DensityBand b) => switch (b) {
      DensityBand.green => _bandGreen,
      DensityBand.orange => _bandOrange,
      DensityBand.red => _bandRed,
    };

Color _colorForEndBand(EndBand b) => switch (b) {
      EndBand.green => _bandGreen,
      EndBand.orange => _bandOrange,
      EndBand.red => _bandRed,
    };

/// Implicit max g/L for the density y-axis scale. Sized to fit air at
/// ~60 m (≈8.6 g/L) — the colour thresholds (5.2 orange / 5.7 red) are
/// absolute values, so they map to sensible y-positions on this scale.
const double _densityGLMax = 10.0;

/// Depth (m) below which a sample counts as "in the water". Density and
/// END traces only render while this holds — once the diver surfaces, the
/// values collapse to surface values and the trace just runs into post-dive
/// logging time.
const double _surfaceDepthM = 1.0;

/// Petrel default per-cell calibration factor when none is available.
/// Multiplying raw mV by this value yields PPO2 in bar.
const double _defaultCellCal = 0.021;

// ── Widget ──────────────────────────────────────────────────────

/// A [StatelessWidget] that renders a multi-trace dive profile chart.
class ProfileChart extends StatelessWidget {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;

  /// Viewport range as fractions of the total sample count (0.0–1.0).
  /// (0.0, 1.0) = full dive; (0.3, 0.6) = middle 30%. Driven by the
  /// zoom gesture handler in the parent (dive_detail_screen).
  final double viewStart;
  final double viewEnd;

  /// Per-cell calibration factors (length 3 expected). Used to convert
  /// raw mV to PPO2 (bar) for the cell traces. Falls back to a Petrel
  /// default when null/empty or any factor is non-positive.
  final List<double>? cellCalibration;

  /// Slot-keyed (1-indexed) map of physical cells active at the dive's
  /// start time. Used by [_legend] to label the cell traces.
  final Map<int, OxygenCell>? cellsBySlot;

  /// Retained for API compatibility; the chart no longer paints this
  /// overlay (the speed-gradient subsumes it).
  final int? maxDescentEndIndex;

  /// Retained for API compatibility; see [maxDescentEndIndex].
  final int? maxAscentEndIndex;

  /// When true, the depth trace is drawn as per-segment line pieces
  /// coloured by local vertical speed. When false, the trace is drawn
  /// as a single solid stroke in the theme's depth-trace colour with no overlay.
  final bool useSpeedColoredGraph;

  /// Active tanks for the dive (compacted list, one entry per active
  /// slot). Drives the legend labels. Same length as [SampleSet.tankPressuresBar].
  final List<DiveTank>? tanks;

  /// Channel-keyed cylinders mapped via the user's `PressureMappings`.
  /// When present, overrides the parser-derived legend label per tank.
  final Map<int, Cylinder>? mappedCylinders;

  /// Gas mix table for this dive. Indexed by [SampleSet.gasMixIndex].
  /// When present, drives the gas-change markers and bailout highlighting.
  final List<DiveGasMix>? gasMixes;

  /// Whether oxygen counts as narcotic when computing END.
  /// Passed through to [computeEndSeries] when the END trace is visible.
  /// Defaults to `true` — the GUE / DIR convention (O₂ has narcotic
  /// potency equivalent to N₂), which is also standard tech-diving.
  /// `false` falls back to the older N₂-only formula.
  final bool endCountsOxygen;

  /// True when the dive is a closed-circuit / semi-closed CCR dive.
  /// Enables loop-gas-aware density + END computation: instead of using
  /// the static gas at the sample's `gasMixIndex`, density/END are
  /// derived from the diluent's inert composition + the per-sample
  /// voted PPO₂. Critical for CCR dives where the parser may have
  /// assigned the wrong static mix per sample (e.g. the bailout air
  /// instead of the helium diluent).
  final bool isCcr;

  /// Optional deco replay result. When non-null and [visibleTraces] contains
  /// [TraceType.gf99] or [TraceType.ceiling], the corresponding traces are
  /// painted on the chart.
  final DecoReplayResult? decoReplay;

  const ProfileChart({
    super.key,
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
    this.cellCalibration,
    this.cellsBySlot,
    this.maxDescentEndIndex,
    this.maxAscentEndIndex,
    this.useSpeedColoredGraph = true,
    this.tanks,
    this.mappedCylinders,
    this.gasMixes,
    this.endCountsOxygen = true,
    this.isCcr = false,
    this.decoReplay,
    this.viewStart = 0.0,
    this.viewEnd = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final mixes = gasMixes;
    final showTanks = visibleTraces.contains(TraceType.tanks) &&
        (tanks?.isNotEmpty ?? false) &&
        samples.tankPressuresBar.isNotEmpty;

    // Compute density + END series here so they are available to the painter
    // without coupling the painter to SettingsNotifier.
    //
    // For CCR dives, feed the voted/measured PPO2 trace through so the
    // analyses run against the LIVE LOOP GAS (diluent inert + PPO2-derived
    // O2) at each sample, instead of whichever static mix the parser
    // happened to assign. For OC dives, ppo2Bar is null and the analyses
    // use the static gas at each sample's gasMixIndex.
    final ppo2Trace = isCcr ? samples.ppo2Bar : null;
    final densitySeries = (visibleTraces.contains(TraceType.density) &&
            mixes != null &&
            mixes.isNotEmpty &&
            samples.gasMixIndex.isNotEmpty)
        ? computeDensitySeries(
            depthMeters: samples.depthMeters,
            gasMixIndex: samples.gasMixIndex,
            gasMixes: mixes,
            atmosphericPressureMbar: kStandardAtmosphericPressureMbar,
            ppo2Bar: ppo2Trace,
          )
        : null;

    final endSeries = (visibleTraces.contains(TraceType.end) &&
            mixes != null &&
            mixes.isNotEmpty &&
            samples.gasMixIndex.isNotEmpty)
        ? computeEndSeries(
            depthMeters: samples.depthMeters,
            gasMixIndex: samples.gasMixIndex,
            gasMixes: mixes,
            countsOxygen: endCountsOxygen,
            ppo2Bar: ppo2Trace,
          )
        : null;

    return Stack(children: [
      CustomPaint(
        painter: ProfileChartPainter(
          samples: samples,
          visibleTraces: visibleTraces,
          crosshairIndex: crosshairIndex,
          cellCalibration: cellCalibration,
          useSpeedColoredGraph: useSpeedColoredGraph,
          gasMixes: gasMixes,
          densitySeries: densitySeries,
          endSeries: endSeries,
          decoReplay: decoReplay,
          viewStart: viewStart,
          viewEnd: viewEnd,
          palette: context.palette,
        ),
        child: const SizedBox.expand(),
      ),
      if (visibleTraces.contains(TraceType.cells) &&
          (cellsBySlot?.isNotEmpty ?? false))
        Positioned(
          left: _leftPad + 4,
          top: _topPad + 2,
          child: _CellLegend(cellsBySlot: cellsBySlot!),
        ),
      if (showTanks)
        Positioned(
          right: _rightPad + 4,
          top: _topPad + 2,
          child: _TankLegend(
              tanks: tanks!, mappedCylinders: mappedCylinders),
        ),
    ]);
  }
}

class _TankLegend extends StatelessWidget {
  final List<DiveTank> tanks;
  final Map<int, Cylinder>? mappedCylinders;
  const _TankLegend({required this.tanks, this.mappedCylinders});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xC0152238),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tanks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: _tankColors[i % _tankColors.length],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(
                  labelForTank(tanks[i], mappedCylinders),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

String cellTraceLabelForSlot(Map<int, OxygenCell>? cellsBySlot, int slot) {
  final cell = cellsBySlot?[slot];
  if (cell == null) return '—';
  final lbl = cell.label?.trim();
  if (lbl == null || lbl.isEmpty) return 'Slot $slot';
  return lbl;
}

class _CellLegend extends StatelessWidget {
  final Map<int, OxygenCell> cellsBySlot;
  const _CellLegend({required this.cellsBySlot});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = [palette.cell1, palette.cell2, palette.cell3];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xC0152238),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var slot = 1; slot <= 3; slot++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: colors[slot - 1],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(
                  cellTraceLabelForSlot(cellsBySlot, slot),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── Painter ─────────────────────────────────────────────────────

/// [CustomPainter] that performs all rendering for [ProfileChart].
///
/// Exposed as public so tests can access [shouldRepaint] directly.
class ProfileChartPainter extends CustomPainter {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;
  final List<double>? cellCalibration;
  final bool useSpeedColoredGraph;
  final List<DiveGasMix>? gasMixes;

  /// Pre-computed per-sample gas density (g/L). Non-null only when
  /// [TraceType.density] is in [visibleTraces] and gas-mix data is available.
  final Float32List? densitySeries;

  /// Pre-computed per-sample END (m). Non-null only when [TraceType.end] is
  /// in [visibleTraces] and gas-mix data is available.
  final Float32List? endSeries;

  /// Optional deco replay result. When non-null and [visibleTraces] contains
  /// [TraceType.gf99] or [TraceType.ceiling], the corresponding traces are
  /// painted on the chart.
  final DecoReplayResult? decoReplay;

  /// Viewport range as fractions of the total sample count (0.0–1.0).
  final double viewStart;
  final double viewEnd;

  /// Colours for the themed traces and grid.
  final ThemePalette palette;

  const ProfileChartPainter({
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
    required this.palette,
    this.cellCalibration,
    this.useSpeedColoredGraph = true,
    this.gasMixes,
    this.densitySeries,
    this.endSeries,
    this.decoReplay,
    this.viewStart = 0.0,
    this.viewEnd = 1.0,
  });

  // ── shouldRepaint ──────────────────────────────────────────────

  @override
  bool shouldRepaint(ProfileChartPainter old) {
    return !identical(old.palette, palette) ||
        old.crosshairIndex != crosshairIndex ||
        !_setEquals(old.visibleTraces, visibleTraces) ||
        old.useSpeedColoredGraph != useSpeedColoredGraph ||
        !identical(old.samples, samples) ||
        !identical(old.gasMixes, gasMixes) ||
        !identical(old.densitySeries, densitySeries) ||
        !identical(old.endSeries, endSeries) ||
        !identical(old.decoReplay, decoReplay) ||
        old.viewStart != viewStart ||
        old.viewEnd != viewEnd;
  }

  static bool _setEquals(Set<TraceType> a, Set<TraceType> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  // ── paint ──────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.sampleCount == 0) return;

    final n = samples.sampleCount;

    // Chart area bounds.
    final chartLeft = _leftPad;
    final chartTop = _topPad;
    final chartRight = size.width - _rightPad;
    final chartBottom = size.height - _bottomPad;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final chartRect = Rect.fromLTRB(chartLeft, chartTop, chartRight, chartBottom);

    // ── Depth scale ────────────────────────────────────────────────
    double maxDepth = 0.0;
    for (int i = 0; i < n; i++) {
      if (samples.depthMeters[i] > maxDepth) maxDepth = samples.depthMeters[i];
    }
    // Round up to nearest 5m, minimum 10m.
    final depthMax = math.max(10.0, (maxDepth / 5.0).ceil() * 5.0);

    // Helpers: convert data coordinates to canvas coordinates.
    // When zoomed (viewStart/viewEnd != 0.0/1.0), only the visible
    // fraction of the dive maps to chartWidth. Samples outside the
    // view produce off-screen x values; Canvas.clipRect handles that.
    final viewSpan = viewEnd - viewStart;
    double xOf(int i) {
      final frac = n > 1 ? i / (n - 1) : 0.0;
      return chartLeft + ((frac - viewStart) / viewSpan) * chartWidth;
    }
    double yDepth(double d) => chartTop + (d / depthMax) * chartHeight;
    double yPpo2(double p) => chartBottom - (p / _ppo2Max) * chartHeight;

    // ── Grid lines ─────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = palette.chartGrid
      ..strokeWidth = 1.0;

    // Depth grid: every 5m (but skip if too many lines on small charts).
    final depthStep = depthMax <= 30 ? 5.0 : depthMax <= 60 ? 10.0 : 20.0;
    var d = depthStep;
    while (d <= depthMax) {
      final y = yDepth(d);
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
      d += depthStep;
    }

    // ── Clip traces to chart area ──────────────────────────────────
    canvas.save();
    canvas.clipRect(chartRect);

    // ── Deco ceiling fill ──────────────────────────────────────────
    if (visibleTraces.contains(TraceType.deco)) {
      bool hasAnyDeco = false;
      for (int i = 0; i < n; i++) {
        if (samples.decoStopDepthMeters[i] > 0) {
          hasAnyDeco = true;
          break;
        }
      }
      if (hasAnyDeco) {
        final decoPaint = Paint()
          ..color = _decoColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;

        final decoPath = Path();
        decoPath.moveTo(xOf(0), chartTop);
        for (int i = 0; i < n; i++) {
          final ceiling = samples.decoStopDepthMeters[i];
          decoPath.lineTo(xOf(i), ceiling > 0 ? yDepth(ceiling) : chartTop);
        }
        decoPath.lineTo(xOf(n - 1), chartTop);
        decoPath.close();
        canvas.drawPath(decoPath, decoPaint);
      }
    }

    // ── Depth fill + trace ─────────────────────────────────────────
    {
      final fillPaint = Paint()
        ..color = palette.chartTraceDepth.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;

      final fillPath = Path();
      fillPath.moveTo(xOf(0), chartBottom);
      fillPath.lineTo(xOf(0), yDepth(samples.depthMeters[0]));
      for (int i = 1; i < n; i++) {
        fillPath.lineTo(xOf(i), yDepth(samples.depthMeters[i]));
      }
      fillPath.lineTo(xOf(n - 1), chartBottom);
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);

      if (useSpeedColoredGraph) {
        // Per-segment line pieces, coloured by local vertical speed.
        final segPaint = Paint()
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final mpmPerSample = 60000.0 / samples.sampleIntervalMs;
        for (int i = 1; i < n; i++) {
          final rate =
              (samples.depthMeters[i] - samples.depthMeters[i - 1]) *
                  mpmPerSample;
          segPaint.color = _colorForRate(rate);
          canvas.drawLine(
            Offset(xOf(i - 1), yDepth(samples.depthMeters[i - 1])),
            Offset(xOf(i), yDepth(samples.depthMeters[i])),
            segPaint,
          );
        }
      } else {
        final strokePaint = Paint()
          ..color = palette.chartTraceDepth
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final strokePath = Path();
        strokePath.moveTo(xOf(0), yDepth(samples.depthMeters[0]));
        for (int i = 1; i < n; i++) {
          strokePath.lineTo(xOf(i), yDepth(samples.depthMeters[i]));
        }
        canvas.drawPath(strokePath, strokePaint);
      }
    }

    // ── PPO2 trace ─────────────────────────────────────────────────
    if (visibleTraces.contains(TraceType.ppo2)) {
      _drawSolidTrace(
        canvas,
        samples.ppo2Bar,
        n,
        xOf,
        yPpo2,
        palette.chartTracePpo2,
        1.5,
      );
    }

    // ── Setpoint trace (dashed) ────────────────────────────────────
    if (visibleTraces.contains(TraceType.setpoint)) {
      _drawDashedTrace(
        canvas,
        samples.setpointBar,
        n,
        xOf,
        yPpo2,
        palette.chartTraceSetpoint,
        1.0,
      );
    }

    // ── Water temperature trace ────────────────────────────────────
    // Fixed 0–35 °C scale (extended only if the dive itself exceeds
    // those bounds). Auto-scaling to the per-dive range made a 2 °C
    // swing fill the entire chart height and dominate the visual
    // hierarchy; a fixed scale puts the trace in a calmer band that
    // reflects the actual temperature variation. Min + max are
    // annotated inline so the diver can read values without summoning
    // the crosshair scrubber.
    if (visibleTraces.contains(TraceType.waterTemp) &&
        samples.temperatureCelsius.isNotEmpty) {
      double tMin = double.infinity;
      double tMax = double.negativeInfinity;
      int iMin = 0;
      int iMax = 0;
      for (var i = 0; i < n; i++) {
        final t = samples.temperatureCelsius[i];
        if (t < tMin) {
          tMin = t;
          iMin = i;
        }
        if (t > tMax) {
          tMax = t;
          iMax = i;
        }
      }
      if (tMin.isFinite && tMax.isFinite) {
        final yLo = math.min(0.0, tMin - 1.0);
        final yHi = math.max(35.0, tMax + 1.0);
        final tRange = yHi - yLo;
        double yTemp(double c) =>
            chartBottom - ((c - yLo) / tRange) * chartHeight;
        _drawSolidTrace(
          canvas,
          samples.temperatureCelsius,
          n,
          xOf,
          yTemp,
          _waterTempColor,
          1.5,
        );
        // Annotate min + max temps so the chart is readable without
        // the crosshair. Skip when the dive has effectively no
        // temperature variation (< 0.5 °C — typically a sensor that
        // didn't equilibrate); the two labels would just overprint
        // each other.
        if ((tMax - tMin) >= 0.5) {
          final labelStyle = TextStyle(
            color: _waterTempColor,
            fontSize: 9,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          // Max label sits ABOVE the warmest point; min label sits
          // BELOW the coldest. Clamp to chart bounds so labels that
          // fall near the top/bottom edges don't get clipped.
          _drawTempLabel(
            canvas,
            '${tMax.toStringAsFixed(0)}°C',
            xOf(iMax),
            yTemp(tMax) - 12,
            labelStyle,
            chartLeft,
            chartRight,
            chartTop,
            chartBottom,
          );
          _drawTempLabel(
            canvas,
            '${tMin.toStringAsFixed(0)}°C',
            xOf(iMin),
            yTemp(tMin) + 4,
            labelStyle,
            chartLeft,
            chartRight,
            chartTop,
            chartBottom,
          );
        }
      }
    }

    // ── Tank pressure traces ───────────────────────────────────────
    if (visibleTraces.contains(TraceType.tanks) &&
        samples.tankPressuresBar.isNotEmpty) {
      double yTank(double bar) =>
          chartBottom - (bar / _tankBarMax) * chartHeight;
      for (var t = 0; t < samples.tankPressuresBar.length; t++) {
        final ch = samples.tankPressuresBar[t];
        var anyNonZero = false;
        for (var i = 0; i < n; i++) {
          if (ch[i] > 0) {
            anyNonZero = true;
            break;
          }
        }
        if (!anyNonZero) continue;
        _drawSolidTrace(
          canvas,
          ch,
          n,
          xOf,
          yTank,
          _tankColors[t % _tankColors.length],
          1.5,
        );
      }
    }

    // ── Cell mV traces ─────────────────────────────────────────────
    if (visibleTraces.contains(TraceType.cells)) {
      // Convert raw mV → PPO2 (bar) using per-cell calibration; fall back
      // to a Petrel default when calibration is missing or invalid.
      final cal = cellCalibration;
      double calOf(int idx) {
        if (cal == null || idx >= cal.length) return _defaultCellCal;
        final c = cal[idx];
        return (c > 0) ? c : _defaultCellCal;
      }

      final c0 = calOf(0);
      final c1 = calOf(1);
      final c2 = calOf(2);
      _drawSolidTrace(canvas, samples.cellMv0, n, xOf,
          (mv) => yPpo2(mv * c0), palette.cell1, 1.0);
      _drawSolidTrace(canvas, samples.cellMv1, n, xOf,
          (mv) => yPpo2(mv * c1), palette.cell2, 1.0);
      _drawSolidTrace(canvas, samples.cellMv2, n, xOf,
          (mv) => yPpo2(mv * c2), palette.cell3, 1.0);
    }

    // ── Gas-change markers ─────────────────────────────────────────
    if (visibleTraces.contains(TraceType.gasChanges) &&
        (gasMixes?.isNotEmpty ?? false) &&
        samples.gasMixIndex.isNotEmpty) {
      _drawGasChangeMarkers(canvas, chartRect, n, xOf);
    }

    // Both density and END are only meaningful while the diver is in the
    // water — once they surface, the traces collapse to surface values and
    // visually run off into post-dive logging time. Skip those samples.
    bool isUnderwater(int i) => samples.depthMeters[i] >= _surfaceDepthM;

    // ── Gas density trace ──────────────────────────────────────────
    // Mapped to an implicit 0–7 g/L scale on the same vertical space as
    // the depth trace. Each segment is colour-coded by its density band.
    final ds = densitySeries;
    if (ds != null && ds.length >= 2) {
      final segPaint = Paint()
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < ds.length && i < n; i++) {
        if (!isUnderwater(i - 1) || !isUnderwater(i)) continue;
        final d0 = ds[i - 1];
        final d1 = ds[i];
        if (d0.isNaN || d1.isNaN) continue;
        segPaint.color = _colorForDensityBand(densityBand((d0 + d1) / 2));
        canvas.drawLine(
          Offset(xOf(i - 1), chartTop + (d0 / _densityGLMax) * chartHeight),
          Offset(xOf(i), chartTop + (d1 / _densityGLMax) * chartHeight),
          segPaint,
        );
      }
    }

    // ── END trace ──────────────────────────────────────────────────
    // END ≤ current depth so the trace draws above (shallower than) the
    // depth fill.  Shares the depth y-axis scale.
    final es = endSeries;
    if (es != null && es.length >= 2) {
      final segPaint = Paint()
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < es.length && i < n; i++) {
        if (!isUnderwater(i - 1) || !isUnderwater(i)) continue;
        final e0 = es[i - 1];
        final e1 = es[i];
        if (e0.isNaN || e1.isNaN) continue;
        segPaint.color = _colorForEndBand(endBand((e0 + e1) / 2));
        canvas.drawLine(
          Offset(xOf(i - 1), yDepth(e0)),
          Offset(xOf(i), yDepth(e1)),
          segPaint,
        );
      }
    }

    // ── GF99 trace ────────────────────────────────────────────────
    // Mapped to the right-axis chart space: 0% at chartBottom, 150% at
    // chartTop. Violet line, drawn over the depth fill.
    if (decoReplay != null && visibleTraces.contains(TraceType.gf99)) {
      final s = decoReplay!.gf99Series;
      final gfPaint = Paint()
        ..color = const Color(0xFF9333EA)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < s.length && i < n; i++) {
        if (s[i - 1].isNaN || s[i].isNaN) continue;
        final x0 = xOf(i - 1);
        final x1 = xOf(i);
        final y0 =
            chartTop + (1 - (s[i - 1] / 150.0).clamp(0.0, 1.0)) * chartHeight;
        final y1 =
            chartTop + (1 - (s[i] / 150.0).clamp(0.0, 1.0)) * chartHeight;
        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), gfPaint);
      }
    }

    // ── Ceiling trace ─────────────────────────────────────────────
    // Shares the depth y-axis. Amber line. Only drawn where ceiling > 0
    // (skips no-stop samples).
    if (decoReplay != null && visibleTraces.contains(TraceType.ceiling)) {
      final s = decoReplay!.ceilingMeters;
      final ceilPaint = Paint()
        ..color = const Color(0xFFEAB308)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < s.length && i < n; i++) {
        if (s[i - 1] <= 0 || s[i] <= 0) continue;
        final x0 = xOf(i - 1);
        final x1 = xOf(i);
        final y0 = yDepth(s[i - 1]);
        final y1 = yDepth(s[i]);
        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), ceilPaint);
      }
    }

    // ── Crosshair ──────────────────────────────────────────────────
    if (crosshairIndex != null) {
      final ci = crosshairIndex!.clamp(0, n - 1);
      final x = xOf(ci);
      final crossPaint = Paint()
        ..color = _crosshairColor
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(x, chartTop), Offset(x, chartBottom), crossPaint);
    }

    canvas.restore();

    // ── Axis labels (outside clip rect) ───────────────────────────
    _drawDepthLabels(canvas, chartLeft, chartTop, chartBottom, depthMax, depthStep);
    _drawPpo2Labels(canvas, chartRight, chartTop, chartBottom);
    _drawTimeLabels(canvas, chartLeft, chartRight, chartBottom, size.height, n, samples.sampleIntervalMs);
  }

  // ── Gas-change markers ─────────────────────────────────────────

  void _drawGasChangeMarkers(
    Canvas canvas,
    Rect chartRect,
    int n,
    double Function(int) xOf,
  ) {
    final mixes = gasMixes!;
    final indices = samples.gasMixIndex;
    if (indices.length < 2 || n < 2) return;

    final hasDiluent = mixes.any((m) => m.isDiluent);

    final transitions = <int>[];
    final limit = n < indices.length ? n : indices.length;
    for (var i = 1; i < limit; i++) {
      if (indices[i] != indices[i - 1]) transitions.add(i);
    }
    if (transitions.isEmpty) return;

    final labelStyleNormal = const TextStyle(
      color: Colors.white,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );
    final labelStyleBailout = const TextStyle(
      color: Colors.white,
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );

    // Stack labels vertically when their boxes would overlap. We track
    // the right edge of the last-placed label per row and pick the
    // lowest row where the new box's left edge starts past it.
    final rowRightEdges = <double>[];
    const rowSpacing = 2.0;

    for (final i in transitions) {
      final newIdx = indices[i];
      if (newIdx >= mixes.length) continue;
      final newMix = mixes[newIdx];
      final isBailout = hasDiluent && !newMix.isDiluent;

      final color = isBailout ? _bailoutColor : _gasChangeColor;
      final x = xOf(i);

      final linePaint = Paint()
        ..color = color.withValues(alpha: isBailout ? 0.7 : 0.5)
        ..strokeWidth = isBailout ? 2.0 : 1.2;
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        linePaint,
      );

      final label = isBailout
          ? '⚠ ${_gasMixLabel(newMix)}'
          : _gasMixLabel(newMix);
      final span = TextSpan(
        text: label,
        style: isBailout ? labelStyleBailout : labelStyleNormal,
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      const padX = 3.0;
      const padY = 1.5;
      final boxWidth = tp.width + 2 * padX;
      final boxHeight = tp.height + 2 * padY;
      var boxLeft = x - boxWidth / 2;
      if (boxLeft < chartRect.left) boxLeft = chartRect.left;
      if (boxLeft + boxWidth > chartRect.right) {
        boxLeft = chartRect.right - boxWidth;
      }

      var row = 0;
      while (row < rowRightEdges.length && rowRightEdges[row] > boxLeft) {
        row++;
      }
      if (row == rowRightEdges.length) {
        rowRightEdges.add(boxLeft + boxWidth);
      } else {
        rowRightEdges[row] = boxLeft + boxWidth;
      }

      final boxTop = chartRect.top + 2 + row * (boxHeight + rowSpacing);
      final boxRect =
          Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      tp.paint(canvas, Offset(boxLeft + padX, boxTop + padY));
    }
  }

  static String _gasMixLabel(DiveGasMix mix) {
    if (mix.heliumPercent > 0) {
      return '${mix.oxygenPercent}/${mix.heliumPercent}';
    }
    if (mix.oxygenPercent == 21) return 'Air';
    if (mix.oxygenPercent == 100) return 'O₂';
    return 'EAN${mix.oxygenPercent}';
  }

  // ── Trace helpers ──────────────────────────────────────────────

  Color _colorForRate(double mPerMin) {
    final anchors = _vSpeedAnchorsFor(palette.chartTraceDepth);
    if (mPerMin <= anchors.first.speed) {
      return anchors.first.color;
    }
    if (mPerMin >= anchors.last.speed) {
      return anchors.last.color;
    }
    for (var i = 0; i < anchors.length - 1; i++) {
      final a = anchors[i];
      final b = anchors[i + 1];
      if (mPerMin >= a.speed && mPerMin <= b.speed) {
        final t = (mPerMin - a.speed) / (b.speed - a.speed);
        return Color.lerp(a.color, b.color, t)!;
      }
    }
    return palette.chartTraceDepth;
  }

  void _drawSolidTrace(
    Canvas canvas,
    Float32List data,
    int n,
    double Function(int) xOf,
    double Function(double) yOf,
    Color color,
    double width,
  ) {
    if (n == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(buildBrokenTracePath(data, n, xOf, yOf), paint);
  }

  void _drawDashedTrace(
    Canvas canvas,
    Float32List data,
    int n,
    double Function(int) xOf,
    double Function(double) yOf,
    Color color,
    double width,
  ) {
    if (n == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    final fullPath = buildBrokenTracePath(data, n, xOf, yOf);

    // Materialise as dashes: 6px on, 4px off.
    const dashOn = 6.0;
    const dashOff = 4.0;
    final dashedPath = Path();

    for (final metric in fullPath.computeMetrics()) {
      double distance = 0.0;
      bool drawing = true;
      while (distance < metric.length) {
        final segLen = drawing ? dashOn : dashOff;
        final end = math.min(distance + segLen, metric.length);
        if (drawing) {
          dashedPath.addPath(
            metric.extractPath(distance, end),
            Offset.zero,
          );
        }
        distance = end;
        drawing = !drawing;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  // ── Label helpers ──────────────────────────────────────────────

  void _drawDepthLabels(
    Canvas canvas,
    double chartLeft,
    double chartTop,
    double chartBottom,
    double depthMax,
    double depthStep,
  ) {
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final chartHeight = chartBottom - chartTop;

    var d = depthStep;
    while (d <= depthMax) {
      final y = chartTop + (d / depthMax) * chartHeight;
      final span = TextSpan(text: '${d.toInt()}m', style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(chartLeft - tp.width - 3, y - tp.height / 2));
      d += depthStep;
    }
  }

  /// Paint a single `NN°C` annotation centred horizontally on
  /// (`x`, `y`), clamped so it never overflows the chart edges. Used
  /// to mark the min + max temperatures on the watertemp trace.
  void _drawTempLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle style,
    double chartLeft,
    double chartRight,
    double chartTop,
    double chartBottom,
  ) {
    final span = TextSpan(text: text, style: style);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    var left = x - tp.width / 2;
    if (left < chartLeft) left = chartLeft;
    if (left + tp.width > chartRight) left = chartRight - tp.width;
    var top = y;
    if (top < chartTop) top = chartTop;
    if (top + tp.height > chartBottom) top = chartBottom - tp.height;
    tp.paint(canvas, Offset(left, top));
  }

  void _drawPpo2Labels(
    Canvas canvas,
    double chartRight,
    double chartTop,
    double chartBottom,
  ) {
    if (!visibleTraces.contains(TraceType.ppo2) &&
        !visibleTraces.contains(TraceType.setpoint) &&
        !visibleTraces.contains(TraceType.cells)) {
      return;
    }
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final chartHeight = chartBottom - chartTop;
    for (final ppo2 in [0.5, 1.0, 1.5, 2.0]) {
      final y = chartBottom - (ppo2 / _ppo2Max) * chartHeight;
      final span = TextSpan(text: ppo2.toStringAsFixed(1), style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(chartRight + 3, y - tp.height / 2));
    }
  }

  void _drawTimeLabels(
    Canvas canvas,
    double chartLeft,
    double chartRight,
    double chartBottom,
    double totalHeight,
    int n,
    int intervalMs,
  ) {
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final totalSeconds = n * (intervalMs / 1000.0);
    final chartWidth = chartRight - chartLeft;

    // Show ~4 time labels.
    const labelCount = 4;
    for (int k = 0; k <= labelCount; k++) {
      final frac = k / labelCount;
      final secs = (totalSeconds * frac).round();
      final mins = secs ~/ 60;
      final x = chartLeft + frac * chartWidth;
      final label = '${mins}m';
      final span = TextSpan(text: label, style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartBottom + 4));
    }
  }
}
