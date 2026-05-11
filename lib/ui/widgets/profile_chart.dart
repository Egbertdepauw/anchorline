/// Multi-trace dive profile chart.
///
/// Renders depth, PPO2, setpoint, deco ceiling, O2 cells, and an
/// optional crosshair scrubber on a [CustomPaint] canvas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../theme/tokens.dart';
import '../util/tank_labels.dart';

// ── Layout constants ────────────────────────────────────────────

const double _leftPad = 40.0;
const double _rightPad = 44.0;
const double _topPad = 8.0;
const double _bottomPad = 24.0;

// ── Trace colours ───────────────────────────────────────────────
//
// Sourced from `AppColors.wreck` so the chart stays in sync with the
// rest of the design system. Cell colours are locked across the app:
// Cell 1 green / Cell 2 blue / Cell 3 pink (`AppColors.wreck.cell1/2/3`).

final Color _depthColor = AppColors.wreck.chartTraceDepth;
final Color _ppo2Color = AppColors.wreck.chartTracePpo2;
final Color _setpointColor = AppColors.wreck.chartTraceSetpoint;
final Color _decoColor = AppColors.wreck.statusWarning;
final Color _cell0Color = AppColors.wreck.cell1;
final Color _cell1Color = AppColors.wreck.cell2;
final Color _cell2Color = AppColors.wreck.cell3;
const Color _crosshairColor = Color(0x80FFFFFF);
final Color _gridColor = AppColors.wreck.chartGrid;
final Color _gasChangeColor = AppColors.wreck.statusInfo;
final Color _bailoutColor = AppColors.wreck.statusDanger;

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
final Color _vSpeedStableColor = _depthColor;            // light blue
const Color _vSpeedSlowColor = Color(0xFFA8D957);        // lime
const Color _vSpeedModerateColor = Color(0xFFE5C73F);    // amber
const Color _vSpeedFastColor = Color(0xFFEC8A3D);        // orange
const Color _vSpeedCrazyColor = Color(0xFFE65656);       // red

// Anchor table sorted by speed ascending. _colorForRate finds the bracket
// containing the segment's signed rate and lerps between the two anchors.
final List<({double speed, Color color})> _vSpeedAnchors = [
  (speed: -30.0, color: _vSpeedCrazyColor),
  (speed: -18.2, color: _vSpeedCrazyColor),
  (speed: -9.1, color: _vSpeedFastColor),
  (speed: -4.6, color: _vSpeedModerateColor),
  (speed: -1.5, color: _vSpeedSlowColor),
  (speed: 0.0, color: _vSpeedStableColor),
  (speed: 1.5, color: _vSpeedSlowColor),
  (speed: 9.1, color: _vSpeedModerateColor),
  (speed: 18.2, color: _vSpeedFastColor),
  (speed: 30.4, color: _vSpeedCrazyColor),
  (speed: 60.0, color: _vSpeedCrazyColor),
];

const double _ppo2Max = 2.0;

/// Petrel default per-cell calibration factor when none is available.
/// Multiplying raw mV by this value yields PPO2 in bar.
const double _defaultCellCal = 0.021;

// ── Widget ──────────────────────────────────────────────────────

/// A [StatelessWidget] that renders a multi-trace dive profile chart.
class ProfileChart extends StatelessWidget {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;

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
  /// as a single solid stroke in [_depthColor] with no overlay.
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
  });

  @override
  Widget build(BuildContext context) {
    final showTanks = visibleTraces.contains(TraceType.tanks) &&
        (tanks?.isNotEmpty ?? false) &&
        samples.tankPressuresBar.isNotEmpty;
    return Stack(children: [
      CustomPaint(
        painter: ProfileChartPainter(
          samples: samples,
          visibleTraces: visibleTraces,
          crosshairIndex: crosshairIndex,
          cellCalibration: cellCalibration,
          useSpeedColoredGraph: useSpeedColoredGraph,
          gasMixes: gasMixes,
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
    final colors = [_cell0Color, _cell1Color, _cell2Color];
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

  const ProfileChartPainter({
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
    this.cellCalibration,
    this.useSpeedColoredGraph = true,
    this.gasMixes,
  });

  // ── shouldRepaint ──────────────────────────────────────────────

  @override
  bool shouldRepaint(ProfileChartPainter old) {
    return old.crosshairIndex != crosshairIndex ||
        !_setEquals(old.visibleTraces, visibleTraces) ||
        old.useSpeedColoredGraph != useSpeedColoredGraph ||
        !identical(old.samples, samples) ||
        !identical(old.gasMixes, gasMixes);
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
    double xOf(int i) => chartLeft + (i / (n - 1)) * chartWidth;
    double yDepth(double d) => chartTop + (d / depthMax) * chartHeight;
    double yPpo2(double p) => chartBottom - (p / _ppo2Max) * chartHeight;

    // ── Grid lines ─────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = _gridColor
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
        ..color = _depthColor.withValues(alpha: 0.10)
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
          ..color = _depthColor
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
        _ppo2Color,
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
        _setpointColor,
        1.0,
      );
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
          (mv) => yPpo2(mv * c0), _cell0Color, 1.0);
      _drawSolidTrace(canvas, samples.cellMv1, n, xOf,
          (mv) => yPpo2(mv * c1), _cell1Color, 1.0);
      _drawSolidTrace(canvas, samples.cellMv2, n, xOf,
          (mv) => yPpo2(mv * c2), _cell2Color, 1.0);
    }

    // ── Gas-change markers ─────────────────────────────────────────
    if (visibleTraces.contains(TraceType.gasChanges) &&
        (gasMixes?.isNotEmpty ?? false) &&
        samples.gasMixIndex.isNotEmpty) {
      _drawGasChangeMarkers(canvas, chartRect, n, xOf);
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
    if (mPerMin <= _vSpeedAnchors.first.speed) {
      return _vSpeedAnchors.first.color;
    }
    if (mPerMin >= _vSpeedAnchors.last.speed) {
      return _vSpeedAnchors.last.color;
    }
    for (var i = 0; i < _vSpeedAnchors.length - 1; i++) {
      final a = _vSpeedAnchors[i];
      final b = _vSpeedAnchors[i + 1];
      if (mPerMin >= a.speed && mPerMin <= b.speed) {
        final t = (mPerMin - a.speed) / (b.speed - a.speed);
        return Color.lerp(a.color, b.color, t)!;
      }
    }
    return _vSpeedStableColor;
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

    final path = Path();
    path.moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < n; i++) {
      path.lineTo(xOf(i), yOf(data[i]));
    }
    canvas.drawPath(path, paint);
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

    final fullPath = Path();
    fullPath.moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < n; i++) {
      fullPath.lineTo(xOf(i), yOf(data[i]));
    }

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
